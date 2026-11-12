import Foundation

/// Favorites and playlists, kept on the device only.
@MainActor
final class UserData: ObservableObject {
    @Published private(set) var favorites: Set<String>
    @Published private(set) var playlists: [Playlist]

    private let playlistsURL = AppFiles.support.appendingPathComponent("playlists.json")

    init() {
        favorites = Set(UserDefaults.standard.stringArray(forKey: "favorites") ?? [])
        if let data = try? Data(contentsOf: AppFiles.support.appendingPathComponent("playlists.json")),
           let saved = try? JSONDecoder().decode([Playlist].self, from: data) {
            playlists = saved
        } else {
            playlists = []
        }
    }

    func isFavorite(_ id: String) -> Bool { favorites.contains(id) }

    func toggleFavorite(_ id: String) {
        if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
        UserDefaults.standard.set(Array(favorites), forKey: "favorites")
    }

    func createPlaylist(named name: String, with ids: [String] = []) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        playlists.append(Playlist(name: trimmed, trackIds: ids))
        save()
    }

    func rename(_ playlist: Playlist, to name: String) {
        guard let i = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { playlists[i].name = trimmed; save() }
    }

    func delete(_ playlist: Playlist) {
        playlists.removeAll { $0.id == playlist.id }
        save()
    }

    func add(_ trackId: String, to playlist: Playlist) {
        guard let i = playlists.firstIndex(where: { $0.id == playlist.id }),
              !playlists[i].trackIds.contains(trackId) else { return }
        playlists[i].trackIds.append(trackId)
        save()
    }

    func remove(_ trackId: String, from playlist: Playlist) {
        guard let i = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists[i].trackIds.removeAll { $0 == trackId }
        save()
    }

    func move(in playlist: Playlist, from: IndexSet, to: Int) {
        guard let i = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists[i].trackIds.move(fromOffsets: from, toOffset: to)
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(playlists) { try? data.write(to: playlistsURL, options: .atomic) }
    }
}
