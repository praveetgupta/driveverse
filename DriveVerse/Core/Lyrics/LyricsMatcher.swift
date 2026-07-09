import Foundation

/// Title/artist normalization for querying LRCLIB and for cache keys.
enum LyricsMatcher {
    /// "Song (feat. X) - Remix" → "song"
    static func normalizeTitle(_ raw: String) -> String {
        var s = raw.lowercased()
        s = stripBracketed(s)
        if let dash = s.range(of: " - ") {
            s = String(s[..<dash.lowerBound])
        }
        s = stripFeatClause(s)
        return collapseWhitespace(s)
    }

    /// "Rihanna feat. JAY-Z" → "rihanna"
    static func normalizeArtist(_ raw: String) -> String {
        var s = raw.lowercased()
        s = stripBracketed(s)
        s = stripFeatClause(s)
        return collapseWhitespace(s)
    }

    /// Cache key for a track. Duration is bucketed to 5 s so slightly different
    /// reports of the same track (Apple Music vs Spotify) usually collide.
    static func signature(title: String, artist: String, durationMs: Int?) -> String {
        let bucket = durationMs.map { Int((Double($0) / 5000.0).rounded()) } ?? -1
        return "\(normalizeTitle(title))|\(normalizeArtist(artist))|\(bucket)"
    }

    /// Picks the `/api/search` result whose normalized title matches and whose
    /// duration is within ±3 s (when we know ours); prefers synced lyrics.
    static func bestMatch(from candidates: [LRCLIBResponse], title: String, durationMs: Int?) -> LRCLIBResponse? {
        let wantedTitle = normalizeTitle(title)
        let matches = candidates.filter { candidate in
            guard normalizeTitle(candidate.trackName ?? "") == wantedTitle else { return false }
            guard let durationMs else { return true }
            guard let duration = candidate.duration else { return false }
            return abs(duration * 1000 - Double(durationMs)) <= 3000
        }
        return matches.first { $0.syncedLyrics?.isEmpty == false } ?? matches.first
    }

    // MARK: - Helpers

    /// Removes every `(…)` and `[…]` segment.
    private static func stripBracketed(_ s: String) -> String {
        var out = ""
        var depth = 0
        for ch in s {
            if ch == "(" || ch == "[" {
                depth += 1
            } else if ch == ")" || ch == "]" {
                if depth > 0 { depth -= 1 }
            } else if depth == 0 {
                out.append(ch)
            }
        }
        return out
    }

    private static let featMarkers = [" feat. ", " feat ", " featuring ", " ft. ", " ft "]

    private static func stripFeatClause(_ s: String) -> String {
        var s = s
        for marker in featMarkers {
            if let r = s.range(of: marker) {
                s = String(s[..<r.lowerBound])
            }
        }
        return s
    }

    private static func collapseWhitespace(_ s: String) -> String {
        s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
