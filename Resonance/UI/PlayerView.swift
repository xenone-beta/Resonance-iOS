import SwiftUI

enum PlayerSheet: String, Identifiable {
    case queue, equalizer, speed, sleep, lyrics
    var id: String { rawValue }
}

struct PlayerView: View {
    @EnvironmentObject private var player: PlayerModel
    @EnvironmentObject private var settings: Settings
    @EnvironmentObject private var userData: UserData
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var sheet: PlayerSheet?

    private var seed: UInt32 {
        settings.coverColors ? (player.coverSeed ?? settings.accent) : settings.accent
    }

    var body: some View {
        let pal = Palette(seed: seed, dark: scheme == .dark, amoled: settings.themeMode == .amoled)
        ZStack {
            pal.surface.ignoresSafeArea()
            if settings.playerGradient {
                // Cover colors fade from the top into the plain surface and follow the cover change.
                LinearGradient(
                    stops: [
                        .init(color: pal.primaryContainer.opacity(0.95), location: 0),
                        .init(color: pal.secondaryContainer.opacity(0.45), location: 0.45),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()
            }
            VStack(spacing: 0) {
                topBar(pal)
                Spacer(minLength: 8)
                CoverStrip(spectrum: player.spectrum, onClose: { dismiss() })
                    .padding(.horizontal, 24)
                Spacer(minLength: 8)
                titleRow(pal)
                    .padding(.horizontal, 28)
                SeekBar(clock: player.clock, isPlaying: player.isPlaying, wavy: settings.wavySeek) { player.seek(to: $0) }
                    .padding(.horizontal, 28)
                    .padding(.top, 8)
                quickActions(pal)
                    .padding(.top, 10)
                controls(pal)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 18)
            }
        }
        .environment(\.palette, pal)
        .animation(.easeInOut(duration: 0.6), value: seed)
        .sheet(item: $sheet) { which in
            Group {
                switch which {
                case .queue: QueueSheet()
                case .equalizer: EqualizerSheet()
                case .speed: SpeedSheet()
                case .sleep: SleepSheet()
                case .lyrics: LyricsSheet()
                }
            }
            .environment(\.palette, pal)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func topBar(_ pal: Palette) -> some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down").font(.title3.weight(.semibold)).frame(width: 44, height: 44)
            }
            Spacer()
            Text("Now playing").font(.subheadline.weight(.medium)).foregroundStyle(pal.onSurfaceVariant)
            Spacer()
            Button { sheet = .queue } label: {
                Image(systemName: "list.bullet").font(.title3).frame(width: 44, height: 44)
            }
        }
        .foregroundStyle(pal.onSurface)
        .padding(.horizontal, 12)
    }

    private func titleRow(_ pal: Palette) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(player.current?.title ?? " ")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(pal.onSurface)
                    .lineLimit(1)
                Text(player.current?.displayArtist ?? " ")
                    .font(.body)
                    .foregroundStyle(pal.onSurfaceVariant)
                    .lineLimit(1)
            }
            Spacer()
            if let track = player.current {
                Button { userData.toggleFavorite(track.id) } label: {
                    Image(systemName: userData.isFavorite(track.id) ? "heart.fill" : "heart")
                        .font(.title2)
                        .foregroundStyle(userData.isFavorite(track.id) ? pal.primary : pal.onSurfaceVariant)
                        .frame(width: 44, height: 44)
                }
            }
        }
    }

    private func quickActions(_ pal: Palette) -> some View {
        HStack(spacing: 0) {
            quick("slider.horizontal.3", .equalizer, pal)
            quick("speedometer", .speed, pal)
            quick(player.sleepEndsAt == nil ? "moon" : "moon.fill", .sleep, pal)
            quick("quote.bubble", .lyrics, pal)
        }
        .padding(.horizontal, 28)
    }

    private func quick(_ symbol: String, _ target: PlayerSheet, _ pal: Palette) -> some View {
        Button { sheet = target } label: {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(pal.onSecondaryContainer)
                .frame(width: 48, height: 48)
                .background(Circle().fill(pal.secondaryContainer))
        }
        .frame(maxWidth: .infinity)
    }

    private func controls(_ pal: Palette) -> some View {
        HStack {
            Button { player.setShuffle(!player.shuffle) } label: {
                Image(systemName: "shuffle").font(.title3)
                    .foregroundStyle(player.shuffle ? pal.primary : pal.onSurfaceVariant)
            }
            Spacer()
            Button { player.previous() } label: {
                Image(systemName: "backward.fill").font(.title).foregroundStyle(pal.onSurface)
            }
            Spacer()
            PlayPauseButton(isPlaying: player.isPlaying) { player.togglePlay() }
            Spacer()
            Button { player.next() } label: {
                Image(systemName: "forward.fill").font(.title).foregroundStyle(pal.onSurface)
            }
            Spacer()
            Button { player.cycleRepeat() } label: {
                Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat").font(.title3)
                    .foregroundStyle(player.repeatMode == .off ? pal.onSurfaceVariant : pal.primary)
            }
        }
    }
}

// MARK: Cover strip

/// The covers sit on a strip: drag sideways and the neighbouring cover slides in under the finger;
/// let go past a third of the way (or flick) and the song changes, otherwise the strip springs back.
/// Drag down to close. Double-tap the left or right side for ±10 seconds; tap toggles the ring.
struct CoverStrip: View {
    @ObservedObject var spectrum: SpectrumModel
    let onClose: () -> Void
    @EnvironmentObject private var player: PlayerModel
    @EnvironmentObject private var settings: Settings
    @State private var dragX: CGFloat = 0
    @State private var dragY: CGFloat = 0
    @State private var axis = 0 // 0 = undecided, 1 = sideways, 2 = down
    @State private var committed = false
    @State private var skipHint = 0

    private struct Slot: Identifiable {
        let track: Track
        let index: Int
        var id: String { track.id }
    }

    private var slots: [Slot] {
        var result: [Slot] = []
        if let p = player.previousTrack { result.append(Slot(track: p, index: -1)) }
        if let c = player.current { result.append(Slot(track: c, index: 0)) }
        if let n = player.nextTrack, n.id != player.previousTrack?.id, n.id != player.current?.id {
            result.append(Slot(track: n, index: 1))
        }
        return result
    }

    var body: some View {
        GeometryReader { geo in
            let stage = min(geo.size.width, geo.size.height)
            let ring = settings.visualizer
            let side = ring ? stage * 0.66 : stage
            let pitch = side + 20
            ZStack {
                if ring {
                    RingView(spectrum: spectrum, coverSide: side, stage: stage, isPlaying: player.isPlaying)
                        .opacity(1 - Double(min(abs(dragX) / pitch, 1)))
                }
                ForEach(slots) { slot in
                    let away = min(abs(dragX + CGFloat(slot.index) * pitch) / pitch, 1)
                    CoverImage(track: slot.track, corner: ring ? side / 2 : 24, maxSide: 700)
                        .frame(width: side, height: side)
                        .shadow(color: .black.opacity(ring ? 0 : 0.22), radius: 18, y: 10)
                        .scaleEffect(scale(for: slot.index, away: away))
                        .opacity(opacity(for: slot.index, away: away))
                        .offset(x: dragX + CGFloat(slot.index) * pitch, y: slot.index == 0 ? dragY * 0.6 : 0)
                }
                if skipHint != 0 {
                    Text(skipHint < 0 ? "−10" : "+10")
                        .font(.headline)
                        .padding(18)
                        .background(Circle().fill(.ultraThinMaterial))
                        .frame(maxWidth: .infinity, alignment: skipHint < 0 ? .leading : .trailing)
                        .transition(.opacity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: ring)
            .gesture(
                SpatialTapGesture(count: 2)
                    .onEnded { value in
                        let x = value.location.x / max(geo.size.width, 1)
                        if x < 0.35 { player.skip(by: -10); flash(-1) }
                        else if x > 0.65 { player.skip(by: 10); flash(1) }
                        else { player.togglePlay() }
                    }
                    .exclusively(before: TapGesture(count: 1).onEnded { settings.visualizer.toggle() })
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in dragChanged(value) }
                    .onEnded { value in dragEnded(value, pitch: pitch) }
            )
            .onChange(of: player.current?.id) { _ in
                // The song changed: the strip now rests on the new cover, so jump back to zero without animating.
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) { dragX = 0; dragY = 0 }
                committed = false
            }
        }
        .frame(height: 340)
    }

    private func scale(for index: Int, away: CGFloat) -> CGFloat {
        if index != 0 { return 0.82 + 0.18 * (1 - away) }
        let resting: CGFloat = player.isPlaying ? 1 : 0.94
        let fall = min(dragY / 400, 1)
        return resting * (1 - 0.12 * away) * (1 - 0.25 * fall)
    }

    private func opacity(for index: Int, away: CGFloat) -> Double {
        if index != 0 { return 1 - 0.8 * Double(away) }
        let fall = Double(min(dragY / 400, 1))
        return (1 - 0.55 * Double(away)) * (1 - 0.7 * fall)
    }

    private func flash(_ direction: Int) {
        withAnimation(.easeOut(duration: 0.15)) { skipHint = direction }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeIn(duration: 0.2)) { skipHint = 0 }
        }
    }

    private func dragChanged(_ value: DragGesture.Value) {
        if axis == 0 {
            let dx = value.translation.width, dy = value.translation.height
            guard abs(dx) + abs(dy) > 12 else { return }
            axis = abs(dx) >= abs(dy) ? 1 : 2
        }
        if axis == 1 {
            var x = value.translation.width
            // Nothing in that direction: the strip resists like a rubber band.
            if (x < 0 && player.nextTrack == nil) || (x > 0 && player.previousTrack == nil) { x *= 0.35 }
            dragX = x
        } else {
            dragY = max(0, value.translation.height)
        }
    }

    private func dragEnded(_ value: DragGesture.Value, pitch: CGFloat) {
        defer { axis = 0 }
        let spring = Animation.spring(response: 0.4, dampingFraction: 0.82)
        if axis == 1 {
            let direction = value.translation.width < 0 ? 1 : -1 // 1 = towards the next song
            let available = direction == 1 ? player.nextTrack != nil : player.previousTrack != nil
            let predicted = value.predictedEndTranslation.width
            let flick = abs(predicted) > pitch * 1.2 && (predicted < 0) == (direction == 1)
            if available && (abs(value.translation.width) > pitch * 0.33 || flick) {
                committed = true
                withAnimation(spring) { dragX = CGFloat(-direction) * pitch }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                    if direction == 1 { player.next() } else { player.goToPreviousTrack() }
                }
                // If the player did not move on, bring the strip back.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                    if committed { committed = false; withAnimation(spring) { dragX = 0 } }
                }
            } else {
                withAnimation(spring) { dragX = 0 }
            }
        } else if axis == 2 {
            if value.translation.height > 140 || value.predictedEndTranslation.height > 420 {
                withAnimation(.easeIn(duration: 0.2)) { dragY = 600 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { onClose() }
            } else {
                withAnimation(spring) { dragY = 0 }
            }
        }
    }
}

/// Spectrum bars in a ring around the circular cover.
struct RingView: View {
    @ObservedObject var spectrum: SpectrumModel
    let coverSide: CGFloat
    let stage: CGFloat
    let isPlaying: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        Canvas { gc, size in
            let bands = spectrum.bands
            let count = bands.count * 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let inner = coverSide / 2 + 6
            let room = max(10, stage / 2 - inner)
            let width = max(2, (2 * CGFloat.pi * inner / CGFloat(count)) * 0.55)
            for bar in 0..<count {
                // Mirrored left and right, bass at the bottom.
                let band = bar < bands.count ? bar : count - 1 - bar
                let level = CGFloat(min(max(bands[band], 0), 1))
                let angle = Double.pi / 2 + (Double(bar) + 0.5) * 2 * Double.pi / Double(count)
                let dx = CGFloat(cos(angle)), dy = CGFloat(sin(angle))
                let length = 3 + room * level
                var path = Path()
                path.move(to: CGPoint(x: center.x + dx * inner, y: center.y + dy * inner))
                path.addLine(to: CGPoint(x: center.x + dx * (inner + length), y: center.y + dy * (inner + length)))
                let color = palette.primary.opacity(0.35 + 0.65 * Double(level))
                gc.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
        }
        .frame(width: stage, height: stage)
        .allowsHitTesting(false)
    }
}
