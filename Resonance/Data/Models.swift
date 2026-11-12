import Foundation

enum AppFiles {
    /// The app's Documents folder. It shows up in the Files app, so the user can copy music into it.
    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var support: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

struct Track: Identifiable, Hashable, Codable {
    /// Path relative to the Documents folder, so it survives the app container being moved.
    let id: String
    var title: String
    var artist: String
    var album: String
    var duration: Double

    var url: URL { AppFiles.documents.appendingPathComponent(id) }
    var lrcURL: URL { url.deletingPathExtension().appendingPathExtension("lrc") }
    var displayArtist: String { artist.isEmpty ? "Unknown artist" : artist }
}

struct Album: Identifiable, Hashable {
    var id: String { artist + "\u{1}" + name }
    let name: String
    let artist: String
    let tracks: [Track]
    var duration: Double { tracks.reduce(0) { $0 + $1.duration } }
}

struct Artist: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let tracks: [Track]
    var albums: [Album] { Grouping.albums(tracks) }
}

struct Playlist: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var trackIds: [String] = []
}

enum Grouping {
    static func albums(_ tracks: [Track]) -> [Album] {
        let groups = Dictionary(grouping: tracks) { $0.album.isEmpty ? "Unknown album" : $0.album }
        return groups.map { name, list in
            let sorted = list.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
            let artists = Set(sorted.map { $0.artist }.filter { !$0.isEmpty })
            return Album(name: name, artist: artists.count == 1 ? artists.first! : (artists.isEmpty ? "" : "Various artists"), tracks: sorted)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func artists(_ tracks: [Track]) -> [Artist] {
        let groups = Dictionary(grouping: tracks) { $0.artist.isEmpty ? "Unknown artist" : $0.artist }
        return groups.map { Artist(name: $0.key, tracks: $0.value.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

enum TimeFormat {
    static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
