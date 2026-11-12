import SwiftUI

enum AppTab: Int, CaseIterable, Identifiable {
    case songs, albums, artists, playlists, settings
    var id: Int { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .songs: return "Songs"
        case .albums: return "Albums"
        case .artists: return "Artists"
        case .playlists: return "Playlists"
        case .settings: return "Settings"
        }
    }
    var symbol: String {
        switch self {
        case .songs: return "music.note"
        case .albums: return "square.stack"
        case .artists: return "music.mic"
        case .playlists: return "music.note.list"
        case .settings: return "gearshape"
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var settings: Settings
    @EnvironmentObject private var player: PlayerModel
    @Environment(\.colorScheme) private var scheme
    @State private var tab: AppTab = .songs
    @State private var showPlayer = false

    var body: some View {
        let pal = Palette(seed: settings.accent, dark: scheme == .dark, amoled: settings.themeMode == .amoled)
        ZStack {
            pal.surface.ignoresSafeArea()
            // All tabs stay alive so each keeps its scroll position and navigation.
            ZStack {
                SongsView().tabVisible(tab == .songs)
                AlbumsView().tabVisible(tab == .albums)
                ArtistsView().tabVisible(tab == .artists)
                PlaylistsView().tabVisible(tab == .playlists)
                SettingsView().tabVisible(tab == .settings)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    if player.current != nil {
                        MiniPlayer { showPlayer = true }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    TabBar(selection: $tab)
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: player.current?.id == nil)
            }
        }
        .environment(\.palette, pal)
        .tint(pal.primary)
        .fullScreenCover(isPresented: $showPlayer) {
            PlayerView().environment(\.palette, pal)
        }
    }
}

private extension View {
    func tabVisible(_ visible: Bool) -> some View {
        opacity(visible ? 1 : 0).allowsHitTesting(visible).accessibilityHidden(!visible)
    }
}

struct TabBar: View {
    @Binding var selection: AppTab
    @Environment(\.palette) private var palette

    var body: some View {
        HStack {
            ForEach(AppTab.allCases) { tab in
                Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selection = tab } } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 18, weight: .medium))
                            .frame(width: 58, height: 30)
                            .background(Capsule().fill(selection == tab ? palette.secondaryContainer : .clear))
                            .foregroundStyle(selection == tab ? palette.onSecondaryContainer : palette.onSurfaceVariant)
                        Text(tab.title)
                            .font(.caption2.weight(selection == tab ? .semibold : .regular))
                            .foregroundStyle(selection == tab ? palette.onSurface : palette.onSurfaceVariant)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(palette.surfaceContainer.ignoresSafeArea(edges: .bottom))
    }
}

struct MiniPlayer: View {
    let onOpen: () -> Void
    @EnvironmentObject private var player: PlayerModel
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                CoverImage(track: player.current, corner: 10, maxSide: 140)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.current?.title ?? "").font(.subheadline.weight(.semibold)).lineLimit(1)
                        .foregroundStyle(palette.onPrimaryContainer)
                    Text(player.current?.displayArtist ?? "").font(.caption).lineLimit(1)
                        .foregroundStyle(palette.onPrimaryContainer.opacity(0.75))
                }
                Spacer()
                PlayPauseButton(isPlaying: player.isPlaying, size: 44) { player.togglePlay() }
                Button { player.next() } label: {
                    Image(systemName: "forward.fill").font(.title3).frame(width: 44, height: 44)
                }
            }
            .foregroundStyle(palette.onPrimaryContainer)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            MiniProgress(clock: player.clock)
        }
        .background(palette.primaryContainer)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }
}

private struct MiniProgress: View {
    @ObservedObject var clock: PlaybackClock
    @Environment(\.palette) private var palette

    var body: some View {
        GeometryReader { geo in
            let fraction = clock.duration > 0 ? clock.position / clock.duration : 0
            ZStack(alignment: .leading) {
                Rectangle().fill(palette.onPrimaryContainer.opacity(0.12))
                Rectangle().fill(palette.primary).frame(width: geo.size.width * CGFloat(min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 3)
    }
}
