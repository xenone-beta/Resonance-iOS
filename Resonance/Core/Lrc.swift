import Foundation

struct LrcLine: Identifiable, Equatable {
    let id: Int
    let time: Double
    let text: String
}

enum Lrc {
    /// Parses "[mm:ss.xx] text" lines. A line may carry several time tags. Result is sorted by time.
    static func parse(_ raw: String) -> [LrcLine] {
        var out: [(Double, String)] = []
        for line in raw.components(separatedBy: .newlines) {
            var rest = Substring(line)
            var times: [Double] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                if let t = seconds(String(tag)) { times.append(t) }
                else if times.isEmpty { break } // [ar:...] and other metadata tags
                rest = rest[rest.index(after: close)...]
            }
            let text = rest.trimmingCharacters(in: .whitespaces)
            for t in times { out.append((t, text)) }
        }
        out.sort { $0.0 < $1.0 }
        return out.enumerated().map { LrcLine(id: $0.offset, time: $0.element.0, text: $0.element.1) }
    }

    private static func seconds(_ tag: String) -> Double? {
        let parts = tag.split(separator: ":")
        guard parts.count == 2, let m = Double(parts[0]), let s = Double(parts[1]) else { return nil }
        return m * 60 + s
    }

    /// Index of the line that is current at [time], or nil before the first line.
    static func index(in lines: [LrcLine], at time: Double) -> Int? {
        var lo = 0, hi = lines.count - 1, found: Int?
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lines[mid].time <= time { found = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        return found
    }
}
