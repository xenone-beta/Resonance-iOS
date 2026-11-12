import AVFoundation
import SwiftUI
import UIKit

/// Scans the Documents folder for audio files, reads their tags and serves covers.
@MainActor
final class Library: ObservableObject {
    @Published private(set) var tracks: [Track] = []
    @Published private(set) var isScanning = false

    private struct CacheEntry: Codable {
        var modified: Double
        var track: Track
    }

    private var cache: [String: CacheEntry] = [:]
    private let cacheURL = AppFiles.support.appendingPathComponent("library-cache.json")
    private let covers = NSCache<NSString, UIImage>()
    private var missingCovers = Set<String>()
    private let exts: Set<String> = ["mp3", "m4a", "aac", "wav", "aif", "aiff", "caf", "flac", "alac"]

    init() {
        if let data = try? Data(contentsOf: cacheURL),
           let saved = try? JSONDecoder().decode([String: CacheEntry].self, from: data) {
            cache = saved
            tracks = saved.values.map { $0.track }.sorted(by: Library.byTitle)
        }
        covers.countLimit = 60
    }

    private static func byTitle(_ a: Track, _ b: Track) -> Bool {
        a.title.localizedStandardCompare(b.title) == .orderedAscending
    }

    func track(id: String) -> Track? { tracks.first { $0.id == id } }

    // MARK: Scanning

    func rescan() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        let found = Library.findAudioFiles(root: AppFiles.documents, exts: exts)

        var fresh: [String: CacheEntry] = [:]
        for item in found {
            if let old = cache[item.rel], old.modified == item.modified {
                fresh[item.rel] = old
            } else if let track = await Library.readTrack(id: item.rel, url: item.url) {
                fresh[item.rel] = CacheEntry(modified: item.modified, track: track)
            }
        }
        cache = fresh
        tracks = fresh.values.map { $0.track }.sorted(by: Library.byTitle)
        if let data = try? JSONEncoder().encode(fresh) { try? data.write(to: cacheURL, options: .atomic) }
    }

    /// Synchronous on purpose: NSEnumerator cannot be iterated from async code.
    nonisolated private static func findAudioFiles(root: URL, exts: Set<String>) -> [(rel: String, url: URL, modified: Double)] {
        var found: [(rel: String, url: URL, modified: Double)] = []
        guard let en = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return found }
        while let next = en.nextObject() {
            guard let url = next as? URL, exts.contains(url.pathExtension.lowercased()) else { continue }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            let rel = String(url.path.dropFirst(root.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            found.append((rel, url, values?.contentModificationDate?.timeIntervalSince1970 ?? 0))
        }
        return found
    }

    nonisolated private static func readTrack(id: String, url: URL) async -> Track? {
        let asset = AVURLAsset(url: url)
        let duration = (try? await asset.load(.duration).seconds) ?? 0
        var title = "", artist = "", album = ""
        if let items = try? await asset.load(.commonMetadata) {
            title = await string(items, .commonIdentifierTitle)
            artist = await string(items, .commonIdentifierArtist)
            album = await string(items, .commonIdentifierAlbumName)
        }
        if title.isEmpty { title = url.deletingPathExtension().lastPathComponent }
        return Track(id: id, title: title, artist: artist, album: album, duration: duration.isFinite ? duration : 0)
    }

    nonisolated private static func string(_ items: [AVMetadataItem], _ id: AVMetadataIdentifier) async -> String {
        guard let item = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: id).first else { return "" }
        let value = try? await item.load(.stringValue)
        return (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Importing

    /// Copies picked files or folders into Documents and rescans.
    func importItems(_ urls: [URL]) async {
        let fm = FileManager.default
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let target = AppFiles.documents.appendingPathComponent(url.lastPathComponent)
            if fm.fileExists(atPath: target.path) { continue }
            try? fm.copyItem(at: url, to: target)
        }
        await rescan()
    }

    func delete(_ track: Track) async {
        try? FileManager.default.removeItem(at: track.url)
        try? FileManager.default.removeItem(at: track.lrcURL)
        cache[track.id] = nil
        tracks.removeAll { $0.id == track.id }
        if let data = try? JSONEncoder().encode(cache) { try? data.write(to: cacheURL, options: .atomic) }
    }

    // MARK: Covers

    /// A cover that is already in memory, or nil. Lets views draw it on their first frame.
    func cachedCover(for track: Track, maxSide: CGFloat = 700) -> UIImage? {
        covers.object(forKey: "\(track.id)@\(Int(maxSide))" as NSString)
    }

    /// The cover of a track, scaled down to about [maxSide] points: embedded art, or cover/folder image beside the file.
    func cover(for track: Track, maxSide: CGFloat = 700) async -> UIImage? {
        let key = "\(track.id)@\(Int(maxSide))" as NSString
        if let hit = covers.object(forKey: key) { return hit }
        if missingCovers.contains(key as String) { return nil }
        let url = track.url
        let image = await Library.loadCover(url: url, maxSide: maxSide)
        if let image { covers.setObject(image, forKey: key) } else { missingCovers.insert(key as String) }
        return image
    }

    nonisolated private static func loadCover(url: URL, maxSide: CGFloat) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        if let items = try? await asset.load(.commonMetadata) {
            let arts = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .commonIdentifierArtwork)
            if let item = arts.first, let data = try? await item.load(.dataValue), let image = UIImage(data: data) {
                return image.scaled(maxSide: maxSide)
            }
        }
        let folder = url.deletingLastPathComponent()
        for name in ["cover.jpg", "cover.png", "folder.jpg", "folder.png", "front.jpg", "album.jpg"] {
            let file = folder.appendingPathComponent(name)
            if let data = try? Data(contentsOf: file), let image = UIImage(data: data) {
                return image.scaled(maxSide: maxSide)
            }
        }
        return nil
    }
}

extension UIImage {
    func scaled(maxSide: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return self }
        let k = maxSide / longest
        let target = CGSize(width: size.width * k, height: size.height * k)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
