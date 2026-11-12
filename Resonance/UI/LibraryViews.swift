import SwiftUI
import UniformTypeIdentifiers

// MARK: Rows

struct TrackRow: View {
    let track: Track
    var isCurrent = false
    @EnvironmentObject private var player: PlayerModel
    @EnvironmentObject private var userData: UserData
    @EnvironmentObject private var library: Library
    @Environment(\.palette) private var palette
    @State private var confirmDelete = false

    var body: some View {
        HStack(spacing: 12) {
            CoverImage(track: track, corner: 10, maxSide: 140)
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.body.weight(isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? palette.primary : palette.onSurface)
                    .lineLimit(1)
                Text(track.displayArtist)
                    .font(.subheadline)
                    .foregroundStyle(palette.onSurfaceVariant)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if userData.isFavorite(track.id) {
                Image(systemName: "heart.fill").font(.caption).foregroundStyle(palette.primary)
            }
            Text(TimeFormat.clock(track.duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(palette.onSurfaceVariant)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button { player.playNext(track) } label: { Label("Play next", systemImage: "text.insert") }
            Button { player.addToQueue([track]) } label: { Label("Add to queue", systemImage: "text.append") }
            Button { userData.toggleFavorite(track.id) } label: {
                Label(userData.isFavorite(track.id) ? "Remove from favorites" : "Add to favorites",
                      systemImage: userData.isFavorite(track.id) ? "heart.slash" : "heart")
            }
            if !userData.playlists.isEmpty {
                Menu {
                    ForEach(userData.playlists) { playlist in
                        Button(playlist.name) { userData.add(track.id, to: playlist) }
                    }
                } label: { Label("Add to playlist", systemImage: "music.note.list") }
            }
            Button(role: .destructive) { confirmDelete = true } label: { Label("Delete file", systemImage: "trash") }
        }
        .confirmationDialog("Delete this song from the app?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await library.delete(track) } }
        }
    }
}

/// A list of songs with Play / Shuffle buttons on top. Tapping a row plays the list from there.
struct TrackList: View {
    let tracks: [Track]
    var showButtons = true
    @EnvironmentObject private var player: PlayerModel
    @Environment(\.palette) private var palette

    var body: some View {
        if showButtons && !tracks.isEmpty {
            HStack(spacing: 12) {
                Button { player.play(tracks, start: 0, shuffled: false) } label: {
                    Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button { player.play(tracks, start: Int.random(in: 0..<tracks.count), shuffled: true) } label: {
                    Label("Shuffle", systemImage: "shuffle").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
            .tint(palette.primary)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
            Button {
                player.play(tracks, start: index)
            } label: {
                TrackRow(track: track, isCurrent: player.current?.id == track.id)
            }
            .buttonStyle(.plain)
        }
    }
}

struct EmptyLibraryView: View {
    @Environment(\.palette) private var palette
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "music.note.house")
                .font(.system(size: 54))
                .foregroundStyle(palette.primary)
            Text("No music yet").font(.title3.weight(.semibold))
            Text("Tap + to import songs, or copy them to the Resonance folder in the Files app (On My iPhone).")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.onSurfaceVariant)
        }
        .padding(32)
    }
}

// MARK: Songs

struct SongsView: View {
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var userData: UserData
    @Environment(\.palette) private var palette
    @State private var query = ""
    @State private var importing = false

    private var shown: [Track] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return library.tracks }
        return library.tracks.filter {
            $0.title.localizedCaseInsensitiveContains(q)
                || $0.artist.localizedCaseInsensitiveContains(q)
                || $0.album.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if library.tracks.isEmpty && !library.isScanning {
                    EmptyLibraryView()
                } else {
                    List { TrackList(tracks: shown, showButtons: query.isEmpty) }
                        .listStyle(.plain)
                        .refreshable { await library.rescan() }
                }
            }
            .background(palette.surface)
            .navigationTitle("Songs")
            .searchable(text: $query, prompt: Text("Search"))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if library.isScanning { ProgressView() }
                    else { Button { importing = true } label: { Image(systemName: "plus") } }
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.audio, .folder], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { Task { await library.importItems(urls) } }
            }
        }
    }
}

// MARK: Albums

struct AlbumsView: View {
    @EnvironmentObject private var library: Library
    @Environment(\.palette) private var palette
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        NavigationStack {
            let albums = Grouping.albums(library.tracks)
            ScrollView {
                if albums.isEmpty { EmptyLibraryView() }
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(albums) { album in
                        NavigationLink(value: album) {
                            VStack(alignment: .leading, spacing: 6) {
                                CoverImage(track: album.tracks.first, corner: 18, maxSide: 360)
                                Text(album.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                    .foregroundStyle(palette.onSurface)
                                Group {
                                    if album.artist.isEmpty { Text("Unknown artist") } else { Text(verbatim: album.artist) }
                                }
                                .font(.caption).lineLimit(1)
                                .foregroundStyle(palette.onSurfaceVariant)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(palette.surface)
            .navigationTitle("Albums")
            .navigationDestination(for: Album.self) { AlbumDetail(album: $0) }
        }
    }
}

struct AlbumDetail: View {
    let album: Album
    @Environment(\.palette) private var palette

    var body: some View {
        List {
            VStack(spacing: 10) {
                CoverImage(track: album.tracks.first, corner: 22, maxSide: 600)
                    .frame(width: 220, height: 220)
                    .shadow(color: .black.opacity(0.2), radius: 14, y: 8)
                Text(album.artist).font(.subheadline).foregroundStyle(palette.onSurfaceVariant)
                Text(TimeFormat.clock(album.duration)).font(.caption.monospacedDigit()).foregroundStyle(palette.onSurfaceVariant)
            }
            .frame(maxWidth: .infinity)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            TrackList(tracks: album.tracks)
        }
        .listStyle(.plain)
        .background(palette.surface)
        .navigationTitle(album.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: Artists

struct ArtistsView: View {
    @EnvironmentObject private var library: Library
    @Environment(\.palette) private var palette

    var body: some View {
        NavigationStack {
            let artists = Grouping.artists(library.tracks)
            Group {
                if artists.isEmpty {
                    EmptyLibraryView()
                } else {
                    List(artists) { artist in
                        NavigationLink(value: artist) {
                            HStack(spacing: 12) {
                                CoverImage(track: artist.tracks.first, corner: 24, maxSide: 140)
                                    .frame(width: 48, height: 48)
                                    .clipShape(Circle())
                                VStack(alignment: .leading) {
                                    Text(artist.name).lineLimit(1)
                                    Text("\(artist.tracks.count)")
                                        .font(.caption).foregroundStyle(palette.onSurfaceVariant)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(palette.surface)
            .navigationTitle("Artists")
            .navigationDestination(for: Artist.self) { artist in
                List { TrackList(tracks: artist.tracks) }
                    .listStyle(.plain)
                    .background(palette.surface)
                    .navigationTitle(artist.name)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

// MARK: Playlists

struct PlaylistsView: View {
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var userData: UserData
    @Environment(\.palette) private var palette
    @State private var creating = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                NavigationLink(value: PlaylistRoute.favorites) {
                    Label("Favorites", systemImage: "heart.fill")
                }
                ForEach(userData.playlists) { playlist in
                    NavigationLink(value: PlaylistRoute.playlist(playlist.id)) {
                        Label {
                            Text(playlist.name)
                        } icon: {
                            Image(systemName: "music.note.list")
                        }
                    }
                }
                .onDelete { offsets in
                    let doomed = offsets.map { userData.playlists[$0] }
                    doomed.forEach { userData.delete($0) }
                }
            }
            .listStyle(.plain)
            .background(palette.surface)
            .navigationTitle("Playlists")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { newName = ""; creating = true } label: { Image(systemName: "plus") }
                }
            }
            .alert("New playlist", isPresented: $creating) {
                TextField("Name", text: $newName)
                Button("Create") { userData.createPlaylist(named: newName) }
                Button("Cancel", role: .cancel) {}
            }
            .navigationDestination(for: PlaylistRoute.self) { route in
                switch route {
                case .favorites: FavoritesDetail()
                case .playlist(let id): PlaylistDetail(playlistID: id)
                }
            }
        }
    }
}

enum PlaylistRoute: Hashable {
    case favorites
    case playlist(UUID)
}

struct FavoritesDetail: View {
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var userData: UserData
    @Environment(\.palette) private var palette

    var body: some View {
        let tracks = library.tracks.filter { userData.isFavorite($0.id) }
        List { TrackList(tracks: tracks) }
            .listStyle(.plain)
            .background(palette.surface)
            .navigationTitle("Favorites")
            .navigationBarTitleDisplayMode(.inline)
            .overlay { if tracks.isEmpty { Text("Tap the heart in the player to add songs here.").foregroundStyle(palette.onSurfaceVariant).padding() } }
    }
}

struct PlaylistDetail: View {
    let playlistID: UUID
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var userData: UserData
    @EnvironmentObject private var player: PlayerModel
    @Environment(\.palette) private var palette
    @State private var renaming = false
    @State private var name = ""

    private var playlist: Playlist? { userData.playlists.first { $0.id == playlistID } }

    var body: some View {
        if let playlist {
            let tracks = playlist.trackIds.compactMap { library.track(id: $0) }
            List {
                if !tracks.isEmpty {
                    HStack(spacing: 12) {
                        Button { player.play(tracks, start: 0, shuffled: false) } label: {
                            Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent)
                        Button { player.play(tracks, start: Int.random(in: 0..<tracks.count), shuffled: true) } label: {
                            Label("Shuffle", systemImage: "shuffle").frame(maxWidth: .infinity)
                        }.buttonStyle(.bordered)
                    }
                    .controlSize(.large)
                    .tint(palette.primary)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    Button { player.play(tracks, start: index) } label: {
                        TrackRow(track: track, isCurrent: player.current?.id == track.id)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    for i in offsets { userData.remove(tracks[i].id, from: playlist) }
                }
                .onMove { from, to in userData.move(in: playlist, from: from, to: to) }
            }
            .listStyle(.plain)
            .background(palette.surface)
            .navigationTitle(playlist.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    EditButton()
                    Button { name = playlist.name; renaming = true } label: { Image(systemName: "pencil") }
                }
            }
            .alert("Rename playlist", isPresented: $renaming) {
                TextField("Name", text: $name)
                Button("Save") { userData.rename(playlist, to: name) }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}
