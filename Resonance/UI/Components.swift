import SwiftUI

/// A track cover, or a placeholder. Draws from the memory cache on its first frame when it can.
struct CoverImage: View {
    @EnvironmentObject private var library: Library
    @Environment(\.palette) private var palette
    let track: Track?
    var corner: CGFloat = 12
    var maxSide: CGFloat = 160
    @State private var loaded: UIImage?

    var body: some View {
        let image = loaded ?? track.flatMap { library.cachedCover(for: $0, maxSide: maxSide) }
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                ZStack {
                    palette.secondaryContainer
                    if let image {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        Image(systemName: "music.note")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(palette.onSecondaryContainer)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .task(id: track?.id) {
                guard let track else { loaded = nil; return }
                if let hit = library.cachedCover(for: track, maxSide: maxSide) { loaded = hit; return }
                loaded = await library.cover(for: track, maxSide: maxSide)
            }
    }
}

/// The big play/pause button. One value runs from 0 (paused) to 1 (playing) on a spring, and the
/// shape, both icons and their rotation follow it, so one icon turns into the other.
struct PlayPauseButton: View {
    let isPlaying: Bool
    var size: CGFloat = 80
    let action: () -> Void
    @Environment(\.palette) private var palette
    @State private var progress: CGFloat = 0

    var body: some View {
        let p = min(max(progress, 0), 1)
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: max(10, (size / 2 - size * 0.15 * progress)), style: .continuous)
                    .fill(palette.primary)
                Image(systemName: "play.fill")
                    .font(.system(size: size * 0.4, weight: .bold))
                    .foregroundStyle(palette.onPrimary)
                    .opacity(1 - p)
                    .rotationEffect(.degrees(Double(-90 * progress)))
                    .scaleEffect(1 - 0.5 * p)
                Image(systemName: "pause.fill")
                    .font(.system(size: size * 0.4, weight: .bold))
                    .foregroundStyle(palette.onPrimary)
                    .opacity(p)
                    .rotationEffect(.degrees(Double(90 * (1 - progress))))
                    .scaleEffect(0.5 + 0.5 * p)
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(PressScaleStyle())
        .onAppear { progress = isPlaying ? 1 : 0 }
        .onChange(of: isPlaying) { playing in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.58)) { progress = playing ? 1 : 0 }
        }
        .accessibilityLabel(isPlaying ? Text("Pause") : Text("Play"))
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// The song's progress. When [wavy], the played part is a travelling wave that calms into a line when paused.
struct SeekBar: View {
    @ObservedObject var clock: PlaybackClock
    let isPlaying: Bool
    let wavy: Bool
    let onSeek: (Double) -> Void
    @Environment(\.palette) private var palette
    @State private var dragFraction: Double?
    @State private var changedAt = Date.distantPast
    @State private var settling = false

    var body: some View {
        let shown = dragFraction ?? (clock.duration > 0 ? clock.position / clock.duration : 0)
        VStack(spacing: 2) {
            GeometryReader { geo in
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !(wavy && (isPlaying || settling)))) { context in
                    Canvas { gc, size in
                        draw(&gc, size: size, fraction: shown, time: context.date)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in dragFraction = min(max(value.location.x / geo.size.width, 0), 1) }
                        .onEnded { value in
                            let f = min(max(value.location.x / geo.size.width, 0), 1)
                            onSeek(f * clock.duration)
                            dragFraction = nil
                        }
                )
            }
            .frame(height: 40)
            HStack {
                Text(TimeFormat.clock(shown * clock.duration))
                Spacer()
                Text(TimeFormat.clock(clock.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(palette.onSurfaceVariant)
        }
        .onChange(of: isPlaying) { _ in
            changedAt = Date()
            settling = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { settling = false }
        }
    }

    private func draw(_ gc: inout GraphicsContext, size: CGSize, fraction: Double, time: Date) {
        let inset: CGFloat = 8
        let width = size.width - inset * 2
        let midY = size.height / 2
        let x = inset + width * CGFloat(min(max(fraction, 0), 1))
        let stroke = StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)

        // Wave height eases in and out for about half a second after play/pause.
        let ease = min(1, time.timeIntervalSince(changedAt) / 0.5)
        let amp: CGFloat = wavy ? CGFloat(isPlaying ? ease : 1 - ease) * 4.5 : 0
        let phase = time.timeIntervalSinceReferenceDate * 5

        var rest = Path()
        rest.move(to: CGPoint(x: x, y: midY))
        rest.addLine(to: CGPoint(x: inset + width, y: midY))
        gc.stroke(rest, with: .color(palette.onSurface.opacity(0.18)), style: stroke)

        var played = Path()
        played.move(to: CGPoint(x: inset, y: midY + amp * CGFloat(sin(-phase))))
        var px = inset
        while px < x {
            px = min(px + 2, x)
            let angle = Double((px - inset) / 26) * 2 * Double.pi - phase
            played.addLine(to: CGPoint(x: px, y: midY + amp * CGFloat(sin(angle))))
        }
        gc.stroke(played, with: .color(palette.primary), style: stroke)

        let thumb = CGRect(x: x - 2.5, y: midY - 14, width: 5, height: 28)
        gc.fill(Path(roundedRect: thumb, cornerRadius: 2.5), with: .color(palette.primary))
    }
}

/// Section label in the app's accent color.
struct SectionLabel: View {
    let key: LocalizedStringKey
    @Environment(\.palette) private var palette
    init(_ key: LocalizedStringKey) { self.key = key }
    var body: some View {
        Text(key)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(palette.primary)
    }
}
