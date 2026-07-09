import Foundation
import CryptoKit

struct CachedLyrics: Codable, Equatable {
    let result: LyricsFetchResult
    let storedAt: Date
}

/// Disk cache for lyric lookups, keyed by track signature.
/// Per CLAUDE.md §2.5: local-only, entries never served past 30 days.
/// Negative results (`notFound`) are retried after a day.
final class LyricsCache {
    static let maxAge: TimeInterval = 30 * 24 * 3600
    static let notFoundMaxAge: TimeInterval = 24 * 3600

    private let directory: URL
    private let fileManager = FileManager.default
    var now: () -> Date

    init(directory: URL? = nil, now: @escaping () -> Date = Date.init) {
        self.directory = directory ?? FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LyricsCache", isDirectory: true)
        self.now = now
        try? fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    func lookup(signature: String) -> LyricsFetchResult? {
        let url = fileURL(for: signature)
        guard let data = try? Data(contentsOf: url),
              let cached = try? JSONDecoder().decode(CachedLyrics.self, from: data) else {
            return nil
        }
        let age = now().timeIntervalSince(cached.storedAt)
        let limit = cached.result == .notFound ? Self.notFoundMaxAge : Self.maxAge
        guard age >= 0, age < limit else {
            try? fileManager.removeItem(at: url)
            return nil
        }
        return cached.result
    }

    func store(_ result: LyricsFetchResult, signature: String) {
        let cached = CachedLyrics(result: result, storedAt: now())
        guard let data = try? JSONEncoder().encode(cached) else { return }
        try? data.write(to: fileURL(for: signature), options: .atomic)
    }

    func clear() {
        try? fileManager.removeItem(at: directory)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func fileURL(for signature: String) -> URL {
        let digest = SHA256.hash(data: Data(signature.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name + ".json")
    }
}
