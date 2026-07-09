import Foundation

/// Cache-first lyrics lookup: signature → cache → LRCLIB → cache.
final class LyricsService {
    private let client: LRCLIBClient
    private let cache: LyricsCache

    init(client: LRCLIBClient = LRCLIBClient(), cache: LyricsCache = LyricsCache()) {
        self.client = client
        self.cache = cache
    }

    func lyrics(for state: NowPlayingState) async throws -> LyricsFetchResult {
        let signature = LyricsMatcher.signature(
            title: state.title, artist: state.artist, durationMs: state.durationMs
        )
        if let hit = cache.lookup(signature: signature) {
            return hit
        }
        let result = try await client.fetchLyrics(
            title: state.title, artist: state.artist,
            album: state.album, durationMs: state.durationMs
        )
        cache.store(result, signature: signature)
        return result
    }

    func clearCache() {
        cache.clear()
    }
}
