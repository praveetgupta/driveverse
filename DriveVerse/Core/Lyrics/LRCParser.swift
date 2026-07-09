import Foundation

struct LRCLine: Equatable, Hashable {
    let timeMs: Int
    let text: String
}

/// Pure LRC parser. No I/O, no state — heavily unit-tested.
enum LRCParser {
    /// Parses LRC text into time-sorted, non-empty lyric lines.
    ///
    /// Supports multiple timestamp tags per line (`[00:10.00][00:45.00]Chorus`),
    /// `[mm:ss]`, `[mm:ss.x]`–`[mm:ss.xxx]`, and `[mm:ss:xx]` timestamps, and the
    /// `[offset:±ms]` tag (positive offset shifts lyrics earlier, per LRC
    /// convention). Metadata tags (`[ar:]`, `[ti:]`, `[al:]`, …) are ignored.
    static func parse(_ raw: String) -> [LRCLine] {
        var offsetMs = 0
        var entries: [(timeMs: Int, text: String)] = []

        for rawLine in raw.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("[") else { continue }

            var times: [Int] = []
            var rest = Substring(line)
            while rest.first == "[", let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                rest = rest[rest.index(after: close)...]
                if let ms = timestampMs(tag) {
                    times.append(ms)
                } else if let offset = offsetValue(tag) {
                    offsetMs = offset
                }
                // else: metadata tag — ignore
            }

            let text = rest.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            for time in times {
                entries.append((time, text))
            }
        }

        return entries
            .map { LRCLine(timeMs: max(0, $0.timeMs - offsetMs), text: $0.text) }
            .sorted { $0.timeMs < $1.timeMs }
    }

    /// `mm:ss`, `mm:ss.frac` (1–3 digits), or `mm:ss:frac`. Returns nil for
    /// anything else, which is how metadata tags are filtered out.
    private static func timestampMs(_ tag: Substring) -> Int? {
        let comps = tag.split(separator: ":")
        guard comps.count == 2 || comps.count == 3, let minutes = Int(comps[0]) else { return nil }

        var secondsPart = comps[1]
        var fracPart: Substring? = comps.count == 3 ? comps[2] : nil
        if fracPart == nil, let dot = secondsPart.firstIndex(of: ".") {
            fracPart = secondsPart[secondsPart.index(after: dot)...]
            secondsPart = secondsPart[..<dot]
        }
        guard let seconds = Int(secondsPart), minutes >= 0, (0..<60).contains(seconds) else { return nil }

        var fracMs = 0
        if let frac = fracPart, !frac.isEmpty {
            let digits = frac.prefix(3)
            guard let value = Int(digits) else { return nil }
            switch digits.count {
            case 1: fracMs = value * 100
            case 2: fracMs = value * 10
            default: fracMs = value
            }
        }
        return (minutes * 60 + seconds) * 1000 + fracMs
    }

    private static func offsetValue(_ tag: Substring) -> Int? {
        let lower = tag.lowercased()
        guard lower.hasPrefix("offset:") else { return nil }
        return Int(lower.dropFirst("offset:".count).trimmingCharacters(in: .whitespaces))
    }
}
