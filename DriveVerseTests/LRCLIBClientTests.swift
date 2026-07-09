import Testing
import Foundation
@testable import DriveVerse

/// Serialization umbrella: every suite that touches StubURLProtocol's static
/// state must be nested in here (via extension), because `.serialized` only
/// orders tests within one suite tree — sibling suites run in parallel.
@Suite(.serialized) enum HTTPStubbedTests {}

/// Records every request and answers from a per-run handler.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (status: Int, body: Data))?
    nonisolated(unsafe) static var headers: [String: String]?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    static func reset(headers: [String: String]? = nil, handler: @escaping (URLRequest) -> (status: Int, body: Data)) {
        self.handler = handler
        self.headers = headers
        self.requests = []
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        let (status, body) = Self.handler?(request) ?? (500, Data())
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil, headerFields: Self.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func json(_ s: String) -> Data { Data(s.utf8) }

private let syncedHit = json("""
{"id": 1, "trackName": "song", "artistName": "artist", "albumName": "album",
 "duration": 200.0, "instrumental": false,
 "plainLyrics": "Hello world", "syncedLyrics": "[00:01.00]Hello world"}
""")

private func queryValue(_ request: URLRequest, _ name: String) -> String? {
    URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
        .queryItems?.first { $0.name == name }?.value
}

extension HTTPStubbedTests {
@Suite struct LRCLIBClientTests {
    private var client: LRCLIBClient { LRCLIBClient(session: StubURLProtocol.makeSession()) }

    @Test func directHitReturnsSynced() async throws {
        StubURLProtocol.reset { _ in (200, syncedHit) }

        let result = try await client.fetchLyrics(
            title: "Song (Remastered 2011)", artist: "Artist feat. Other",
            album: "Album (Deluxe)", durationMs: 200_000
        )
        #expect(result == .synced("[00:01.00]Hello world"))
        #expect(StubURLProtocol.requests.count == 1)

        let request = try #require(StubURLProtocol.requests.first)
        #expect(request.url?.path == "/api/get")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "DriveVerse/1.0 personal project")
        // Queries are sent normalized, with duration in seconds.
        #expect(queryValue(request, "track_name") == "song")
        #expect(queryValue(request, "artist_name") == "artist")
        #expect(queryValue(request, "album_name") == "album")
        #expect(queryValue(request, "duration") == "200")
    }

    @Test func fallbackChainGetGetSearch() async throws {
        StubURLProtocol.reset { request in
            let path = request.url!.path
            if path == "/api/get" { return (404, Data()) }
            // /api/search: one wrong-duration candidate, one match without
            // synced lyrics, one match with — the last should win.
            return (200, json("""
            [
              {"id": 1, "trackName": "song", "duration": 300.0, "syncedLyrics": "[00:01.00]Wrong"},
              {"id": 2, "trackName": "song", "duration": 201.0, "plainLyrics": "Plain only"},
              {"id": 3, "trackName": "song", "duration": 199.0, "syncedLyrics": "[00:01.00]Right"}
            ]
            """))
        }

        let result = try await client.fetchLyrics(
            title: "Song", artist: "Artist", album: "Album", durationMs: 200_000
        )
        #expect(result == .synced("[00:01.00]Right"))

        let paths = StubURLProtocol.requests.map { $0.url!.path }
        #expect(paths == ["/api/get", "/api/get", "/api/search"])
        // First get carries the album, the retry drops it.
        #expect(queryValue(StubURLProtocol.requests[0], "album_name") == "album")
        #expect(queryValue(StubURLProtocol.requests[1], "album_name") == nil)
    }

    @Test func instrumentalTrack() async throws {
        StubURLProtocol.reset { _ in
            (200, json("""
            {"id": 9, "trackName": "song", "instrumental": true,
             "plainLyrics": null, "syncedLyrics": null}
            """))
        }
        let result = try await client.fetchLyrics(title: "Song", artist: "Artist", album: nil, durationMs: 100_000)
        #expect(result == .instrumental)
    }

    @Test func plainLyricsFallback() async throws {
        StubURLProtocol.reset { _ in
            (200, json("""
            {"id": 9, "trackName": "song", "instrumental": false,
             "plainLyrics": "Just words", "syncedLyrics": null}
            """))
        }
        let result = try await client.fetchLyrics(title: "Song", artist: "Artist", album: nil, durationMs: nil)
        #expect(result == .plain("Just words"))
    }

    @Test func nothingFoundAnywhere() async throws {
        StubURLProtocol.reset { request in
            request.url!.path == "/api/search" ? (200, json("[]")) : (404, Data())
        }
        let result = try await client.fetchLyrics(title: "Song", artist: "Artist", album: "Album", durationMs: 100_000)
        #expect(result == .notFound)
        #expect(StubURLProtocol.requests.count == 3)
    }

    @Test func noAlbumSkipsSecondGet() async throws {
        StubURLProtocol.reset { request in
            request.url!.path == "/api/search" ? (200, json("[]")) : (404, Data())
        }
        _ = try await client.fetchLyrics(title: "Song", artist: "Artist", album: nil, durationMs: 100_000)
        let paths = StubURLProtocol.requests.map { $0.url!.path }
        #expect(paths == ["/api/get", "/api/search"])
    }

    @Test func serverErrorThrows() async {
        StubURLProtocol.reset { _ in (500, Data()) }
        await #expect(throws: LRCLIBClient.ClientError.badStatus(500)) {
            _ = try await client.fetchLyrics(title: "Song", artist: "Artist", album: nil, durationMs: nil)
        }
    }

    // Lives in this suite (not its own) because it shares StubURLProtocol's
    // static state — suites run in parallel, .serialized only orders within one.
    @Test func secondLookupServedFromCache() async throws {
        StubURLProtocol.reset { _ in (200, syncedHit) }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("driveverse-tests-\(UUID().uuidString)")
        let service = LyricsService(
            client: LRCLIBClient(session: StubURLProtocol.makeSession()),
            cache: LyricsCache(directory: dir)
        )
        let state = NowPlayingState(
            title: "Song", artist: "Artist", album: "Album",
            durationMs: 200_000, positionMs: 0,
            isPlaying: true, source: .spotify, capturedAt: Date()
        )

        let first = try await service.lyrics(for: state)
        #expect(first == .synced("[00:01.00]Hello world"))
        #expect(StubURLProtocol.requests.count == 1)

        let second = try await service.lyrics(for: state)
        #expect(second == first)
        #expect(StubURLProtocol.requests.count == 1) // no extra network hit

        try? FileManager.default.removeItem(at: dir)
    }
}
}
