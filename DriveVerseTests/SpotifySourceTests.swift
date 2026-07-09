import Testing
import Foundation
@testable import DriveVerse

private let playingFixture = Data("""
{
  "timestamp": 1719900000000,
  "progress_ms": 44120,
  "is_playing": true,
  "currently_playing_type": "track",
  "item": {
    "name": "Blinding Lights",
    "duration_ms": 200040,
    "artists": [{"name": "The Weeknd"}, {"name": "Guest Artist"}],
    "album": {"name": "After Hours"}
  }
}
""".utf8)

@Suite struct SpotifyParsingTests {
    private let at = Date(timeIntervalSinceReferenceDate: 790_000_000)

    @Test func fullFixture() throws {
        let state = try SpotifySource.parseCurrentlyPlaying(playingFixture, capturedAt: at)
        #expect(state == NowPlayingState(
            title: "Blinding Lights", artist: "The Weeknd", album: "After Hours",
            durationMs: 200_040, positionMs: 44_120,
            isPlaying: true, source: .spotify, capturedAt: at
        ))
    }

    @Test func pausedTrack() throws {
        let fixture = Data(#"{"progress_ms": 1000, "is_playing": false, "item": {"name": "T"}}"#.utf8)
        let state = try SpotifySource.parseCurrentlyPlaying(fixture, capturedAt: at)
        #expect(state?.isPlaying == false)
        #expect(state?.artist == "")
        #expect(state?.durationMs == nil)
    }

    @Test func nullItemMapsToNil() throws {
        let fixture = Data(#"{"progress_ms": null, "is_playing": false, "item": null}"#.utf8)
        #expect(try SpotifySource.parseCurrentlyPlaying(fixture, capturedAt: at) == nil)
    }

    @Test func garbageThrows() {
        #expect(throws: (any Error).self) {
            _ = try SpotifySource.parseCurrentlyPlaying(Data("not json".utf8), capturedAt: at)
        }
    }
}

@MainActor
private final class FakeTokenProvider: SpotifyTokenProviding {
    var isConnected = true
    var token = "test-token"
    var failTokenFetch = false
    private(set) var unauthorizedCalls = 0

    func validAccessToken() async throws -> String {
        if failTokenFetch { throw SpotifyAuthError.notConnected }
        return token
    }

    func handleUnauthorized() async {
        unauthorizedCalls += 1
    }
}

extension HTTPStubbedTests {
@Suite struct SpotifySourcePollTests {
    @MainActor
    private func makeSource(provider: FakeTokenProvider) -> SpotifySource {
        SpotifySource(session: StubURLProtocol.makeSession(), tokenProvider: provider)
    }

    @MainActor @Test func playingTrackEmitsStateAtActiveInterval() async throws {
        StubURLProtocol.reset { _ in (200, playingFixture) }
        let provider = FakeTokenProvider()
        let source = makeSource(provider: provider)

        var captured: NowPlayingState??
        let sub = source.statePublisher.sink { captured = $0 }
        defer { sub.cancel() }

        let delay = await source.pollOnce()
        #expect(delay == SpotifySource.defaultActiveInterval)
        #expect((captured ?? nil)?.title == "Blinding Lights")
        #expect((captured ?? nil)?.isPlaying == true)

        let request = try #require(StubURLProtocol.requests.first)
        #expect(request.url == SpotifySource.endpoint)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
    }

    @MainActor @Test func pausedTrackPollsAtIdleInterval() async {
        StubURLProtocol.reset { _ in
            (200, Data(#"{"progress_ms": 1000, "is_playing": false, "item": {"name": "T"}}"#.utf8))
        }
        let delay = await makeSource(provider: FakeTokenProvider()).pollOnce()
        #expect(delay == SpotifySource.idleInterval)
    }

    @MainActor @Test func nothingPlaying204ClearsState() async {
        StubURLProtocol.reset { _ in (204, Data()) }
        let provider = FakeTokenProvider()
        let source = makeSource(provider: provider)

        var captured: NowPlayingState??
        let sub = source.statePublisher.sink { captured = $0 }
        defer { sub.cancel() }

        let delay = await source.pollOnce()
        #expect(delay == SpotifySource.idleInterval)
        #expect(captured != nil)          // did emit…
        #expect((captured ?? nil) == nil) // …and the emission was nil
    }

    @MainActor @Test func unauthorizedTriggersTokenRecovery() async {
        StubURLProtocol.reset { _ in (401, Data()) }
        let provider = FakeTokenProvider()
        _ = await makeSource(provider: provider).pollOnce()
        #expect(provider.unauthorizedCalls == 1)
    }

    @MainActor @Test func rateLimitHonorsRetryAfter() async {
        StubURLProtocol.reset(headers: ["Retry-After": "42"]) { _ in (429, Data()) }
        let delay = await makeSource(provider: FakeTokenProvider()).pollOnce()
        #expect(delay == 42)
    }

    @MainActor @Test func rateLimitWithoutHeaderFallsBackToIdle() async {
        StubURLProtocol.reset { _ in (429, Data()) }
        let delay = await makeSource(provider: FakeTokenProvider()).pollOnce()
        #expect(delay == SpotifySource.idleInterval)
    }

    @MainActor @Test func disconnectedSkipsNetwork() async {
        StubURLProtocol.reset { _ in (200, playingFixture) }
        let provider = FakeTokenProvider()
        provider.isConnected = false
        let delay = await makeSource(provider: provider).pollOnce()
        #expect(delay == SpotifySource.idleInterval)
        #expect(StubURLProtocol.requests.isEmpty)
    }

    @MainActor @Test func tokenFailureEmitsNil() async {
        StubURLProtocol.reset { _ in (200, playingFixture) }
        let provider = FakeTokenProvider()
        provider.failTokenFetch = true
        let source = makeSource(provider: provider)

        var captured: NowPlayingState??
        let sub = source.statePublisher.sink { captured = $0 }
        defer { sub.cancel() }

        let delay = await source.pollOnce()
        #expect(delay == SpotifySource.idleInterval)
        #expect((captured ?? nil) == nil)
        #expect(StubURLProtocol.requests.isEmpty)
    }
}
}
