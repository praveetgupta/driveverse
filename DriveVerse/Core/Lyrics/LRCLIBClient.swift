import Foundation

struct LRCLIBResponse: Codable, Equatable {
    let id: Int?
    let trackName: String?
    let artistName: String?
    let albumName: String?
    /// Seconds.
    let duration: Double?
    let instrumental: Bool?
    let plainLyrics: String?
    let syncedLyrics: String?
}

enum LyricsFetchResult: Codable, Equatable {
    /// Raw LRC text — parse with LRCParser.
    case synced(String)
    /// Un-synced lyrics — display without highlighting.
    case plain(String)
    case instrumental
    case notFound
}

/// LRCLIB (https://lrclib.net) client. No API key; identifies itself with a
/// descriptive User-Agent per LRCLIB's request.
struct LRCLIBClient {
    enum ClientError: Error, Equatable {
        case badStatus(Int)
    }

    static let userAgent = "DriveVerse/1.0 personal project"

    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = URL(string: "https://lrclib.net")!) {
        self.session = session
        self.baseURL = baseURL
    }

    /// Fallback chain per CLAUDE.md §4.7:
    /// `/api/get` with album → `/api/get` without album → `/api/search`
    /// (best result = duration within ±3 s and normalized title match).
    func fetchLyrics(title: String, artist: String, album: String?, durationMs: Int?) async throws -> LyricsFetchResult {
        let normTitle = LyricsMatcher.normalizeTitle(title)
        let normArtist = LyricsMatcher.normalizeArtist(artist)
        let normAlbum = album.map { LyricsMatcher.normalizeTitle($0) }
        let durationSec = durationMs.map { Int((Double($0) / 1000).rounded()) }

        if let hit = try await get(track: normTitle, artist: normArtist, album: normAlbum, duration: durationSec) {
            return Self.result(from: hit)
        }
        if normAlbum != nil,
           let hit = try await get(track: normTitle, artist: normArtist, album: nil, duration: durationSec) {
            return Self.result(from: hit)
        }
        let candidates = try await search(track: normTitle, artist: normArtist)
        if let best = LyricsMatcher.bestMatch(from: candidates, title: title, durationMs: durationMs) {
            return Self.result(from: best)
        }
        return .notFound
    }

    static func result(from response: LRCLIBResponse) -> LyricsFetchResult {
        if response.instrumental == true { return .instrumental }
        if let synced = response.syncedLyrics, !synced.isEmpty { return .synced(synced) }
        if let plain = response.plainLyrics, !plain.isEmpty { return .plain(plain) }
        return .notFound
    }

    // MARK: - Requests

    private func get(track: String, artist: String, album: String?, duration: Int?) async throws -> LRCLIBResponse? {
        var items = [
            URLQueryItem(name: "track_name", value: track),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        if let album {
            items.append(URLQueryItem(name: "album_name", value: album))
        }
        if let duration {
            items.append(URLQueryItem(name: "duration", value: String(duration)))
        }
        guard let data = try await perform(path: "/api/get", queryItems: items) else { return nil }
        return try JSONDecoder().decode(LRCLIBResponse.self, from: data)
    }

    private func search(track: String, artist: String) async throws -> [LRCLIBResponse] {
        let items = [
            URLQueryItem(name: "track_name", value: track),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        guard let data = try await perform(path: "/api/search", queryItems: items) else { return [] }
        return try JSONDecoder().decode([LRCLIBResponse].self, from: data)
    }

    /// Returns nil on 404 (drives the fallback chain), throws on other errors.
    private func perform(path: String, queryItems: [URLQueryItem]) async throws -> Data? {
        var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        comps.queryItems = queryItems
        var request = URLRequest(url: comps.url!)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        switch http.statusCode {
        case 200: return data
        case 404: return nil
        default: throw ClientError.badStatus(http.statusCode)
        }
    }
}
