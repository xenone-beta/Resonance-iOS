import SwiftUI

struct QueueSheet: View {
    @EnvironmentObject private var player: PlayerModel
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(player.items.enumerated()), id: \.offset) { index, track in
                        Button { player.jump(to: index) } label: {
                            HStack(spacing: 12) {
                                CoverImage(track: track, corner: 8, maxSide: 120).frame(width: 42, height: 42)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(track.title).lineLimit(1)
                                        .foregroundStyle(index == player.position ? palette.primary : palette.onSurface)
                                        .fontWeight(index == player.position ? .semibold : .regular)
                                    Text(track.displayArtist).font(.caption).lineLimit(1)
                                        .foregroundStyle(palette.onSurfaceVariant)
                                }
                                Spacer()
                                if index == player.position {
                                    Image(systemName: "waveform").foregroundStyle(palette.primary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .id(index)
                    }
                    .onDelete { offsets in
                        for i in offsets.sorted(by: >) { player.removeFromQueue(at: i) }
                    }
                }
                .listStyle(.plain)
                .onAppear { proxy.scrollTo(player.position, anchor: .center) }
            }
            .background(palette.surface)
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }
}

struct EqualizerSheet: View {
    @EnvironmentObject private var player: PlayerModel
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(EQPreset.all) { preset in
                                let selected = player.eqGains == preset.gains
                                Button { player.eqGains = preset.gains } label: {
                                    Text(LocalizedStringKey(preset.id))
                                        .font(.subheadline.weight(.medium))
                                        .padding(.horizontal, 14).padding(.vertical, 8)
                                        .background(Capsule().fill(selected ? palette.primaryContainer : palette.surfaceContainer))
                                        .foregroundStyle(selected ? palette.onPrimaryContainer : palette.onSurface)
                                }
                            }
                        }
                    }
                    ForEach(0..<10, id: \.self) { i in
                        HStack {
                            Text(label(EQPreset.frequencies[i]))
                                .font(.caption.monospacedDigit())
                                .frame(width: 56, alignment: .leading)
                                .foregroundStyle(palette.onSurfaceVariant)
                            Slider(value: Binding(
                                get: { Double(player.eqGains[i]) },
                                set: { player.eqGains[i] = Float($0) }
                            ), in: -12...12, step: 0.5)
                            .tint(palette.primary)
                            Text(String(format: "%+.1f", player.eqGains[i]))
                                .font(.caption.monospacedDigit())
                                .frame(width: 40, alignment: .trailing)
                                .foregroundStyle(palette.onSurfaceVariant)
                        }
                    }
                }
                .padding(20)
            }
            .background(palette.surface)
            .navigationTitle("Equalizer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } } }
        }
    }

    private func label(_ hz: Float) -> String {
        hz >= 1000 ? "\(Int(hz / 1000)) kHz" : "\(Int(hz)) Hz"
    }
}

struct SpeedSheet: View {
    @EnvironmentObject private var player: PlayerModel
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Speed") {
                    HStack {
                        Slider(value: Binding(get: { Double(player.speed) }, set: { player.speed = Float($0) }), in: 0.5...2, step: 0.05)
                            .tint(palette.primary)
                        Text(String(format: "%.2f×", player.speed)).font(.body.monospacedDigit()).frame(width: 64, alignment: .trailing)
                    }
                    Button("Reset") { player.speed = 1 }
                }
                Section("Pitch") {
                    Stepper(value: $player.pitchSemitones, in: -6...6) {
                        Text(String(format: "%+d", player.pitchSemitones) + " ")
                            + Text("semitones")
                    }
                    Button("Reset") { player.pitchSemitones = 0 }
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.surface)
            .navigationTitle("Speed and pitch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

struct SleepSheet: View {
    @EnvironmentObject private var player: PlayerModel
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let end = player.sleepEndsAt {
                    Section {
                        HStack {
                            Text("Stops at")
                            Spacer()
                            Text(end, style: .time).foregroundStyle(palette.primary)
                        }
                        Button("Turn off timer", role: .destructive) { player.setSleepTimer(minutes: nil); dismiss() }
                    }
                }
                Section("Stop playback in") {
                    ForEach([15, 30, 45, 60, 90], id: \.self) { minutes in
                        Button { player.setSleepTimer(minutes: minutes); dismiss() } label: {
                            Text("\(minutes) min").foregroundStyle(palette.onSurface)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.surface)
            .navigationTitle("Sleep timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

struct LyricsSheet: View {
    @EnvironmentObject private var player: PlayerModel
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var lines: [LrcLine] = []
    @State private var plain: String?

    var body: some View {
        NavigationStack {
            Group {
                if !lines.isEmpty {
                    SyncedLyrics(lines: lines, clock: player.clock) { player.seek(to: $0) }
                } else if let plain {
                    ScrollView { Text(plain).padding(24).frame(maxWidth: .infinity, alignment: .leading) }
                } else {
                    Text("No lyrics. Put a .lrc file with the same name next to the song.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(palette.onSurfaceVariant)
                        .padding(32)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(palette.surface)
            .navigationTitle("Lyrics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } } }
        }
        .task(id: player.current?.id) { load() }
    }

    private func load() {
        lines = []; plain = nil
        guard let track = player.current,
              let text = try? String(contentsOf: track.lrcURL, encoding: .utf8) else { return }
        let parsed = Lrc.parse(text)
        if parsed.isEmpty { plain = text } else { lines = parsed }
    }
}

private struct SyncedLyrics: View {
    let lines: [LrcLine]
    @ObservedObject var clock: PlaybackClock
    let onTap: (Double) -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        let active = Lrc.index(in: lines, at: clock.position)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(lines) { line in
                        let isActive = line.id == active
                        Button { onTap(line.time) } label: {
                            Text(line.text.isEmpty ? "♪" : line.text)
                                .font(.title3.weight(isActive ? .bold : .regular))
                                .foregroundStyle(isActive ? palette.primary : palette.onSurfaceVariant)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .id(line.id)
                    }
                }
                .padding(24)
            }
            .onChange(of: active) { newValue in
                if let newValue { withAnimation(.easeInOut(duration: 0.4)) { proxy.scrollTo(newValue, anchor: .center) } }
            }
        }
    }
}
