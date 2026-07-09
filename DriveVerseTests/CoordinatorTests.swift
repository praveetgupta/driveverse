import Testing
import Foundation
@testable import DriveVerse
import Combine

private func track(
    _ title: String,
    source: MusicSource,
    isPlaying: Bool
) -> NowPlayingState {
    NowPlayingState(
        title: title, artist: "Artist", album: nil,
        durationMs: 200_000, positionMs: 10_000,
        isPlaying: isPlaying, source: source,
        capturedAt: Date(timeIntervalSinceReferenceDate: 810_000_000)
    )
}

@Suite struct NowPlayingArbiterTests {
    @Test func appleMusicPlayingBeatsSpotifyPlaying() {
        let winner = NowPlayingArbiter.arbitrate(
            apple: track("AM", source: .appleMusic, isPlaying: true),
            spotify: track("SP", source: .spotify, isPlaying: true),
            pin: .auto, previous: nil
        )
        #expect(winner?.title == "AM")
        #expect(winner?.source == .appleMusic)
    }

    @Test func spotifyPlayingBeatsIdleAppleMusic() {
        let winner = NowPlayingArbiter.arbitrate(
            apple: track("AM", source: .appleMusic, isPlaying: false),
            spotify: track("SP", source: .spotify, isPlaying: true),
            pin: .auto, previous: nil
        )
        #expect(winner?.title == "SP")
    }

    @Test func spotifyPlayingBeatsNilAppleMusic() {
        let winner = NowPlayingArbiter.arbitrate(
            apple: nil,
            spotify: track("SP", source: .spotify, isPlaying: true),
            pin: .auto, previous: nil
        )
        #expect(winner?.title == "SP")
    }

    @Test func bothIdleKeepsLastKnownStopped() {
        let previous = track("LAST", source: .spotify, isPlaying: true)
        let winner = NowPlayingArbiter.arbitrate(
            apple: nil, spotify: nil,
            pin: .auto, previous: previous
        )
        #expect(winner?.title == "LAST")
        #expect(winner?.isPlaying == false)
    }

    @Test func bothIdlePrefersSourceStillReportingAnItem() {
        let winner = NowPlayingArbiter.arbitrate(
            apple: track("AM-paused", source: .appleMusic, isPlaying: false),
            spotify: track("SP-paused", source: .spotify, isPlaying: false),
            pin: .auto, previous: nil
        )
        #expect(winner?.title == "AM-paused")
        #expect(winner?.isPlaying == false)
    }

    @Test func nothingAnywhereIsNil() {
        #expect(NowPlayingArbiter.arbitrate(apple: nil, spotify: nil, pin: .auto, previous: nil) == nil)
    }

    @Test func pinSpotifyIgnoresPlayingAppleMusic() {
        let winner = NowPlayingArbiter.arbitrate(
            apple: track("AM", source: .appleMusic, isPlaying: true),
            spotify: track("SP", source: .spotify, isPlaying: false),
            pin: .spotify, previous: nil
        )
        #expect(winner?.title == "SP")
    }

    @Test func pinAppleMusicIgnoresPlayingSpotify() {
        let winner = NowPlayingArbiter.arbitrate(
            apple: nil,
            spotify: track("SP", source: .spotify, isPlaying: true),
            pin: .appleMusic, previous: nil
        )
        #expect(winner == nil)
    }

    @Test func pinnedSourceCarriesOverItsOwnLastTrack() {
        let previous = track("SP-LAST", source: .spotify, isPlaying: true)
        let winner = NowPlayingArbiter.arbitrate(
            apple: nil, spotify: nil,
            pin: .spotify, previous: previous
        )
        #expect(winner?.title == "SP-LAST")
        #expect(winner?.isPlaying == false)

        let crossSource = NowPlayingArbiter.arbitrate(
            apple: nil, spotify: nil,
            pin: .appleMusic, previous: previous
        )
        #expect(crossSource == nil)
    }
}

@Suite struct NowPlayingCoordinatorTests {
    @Test func republishesArbitratedStateAndReactsToPinChange() {
        let apple = CurrentValueSubject<NowPlayingState?, Never>(nil)
        let spotify = CurrentValueSubject<NowPlayingState?, Never>(nil)
        let coordinator = NowPlayingCoordinator(
            applePublisher: apple.eraseToAnyPublisher(),
            spotifyPublisher: spotify.eraseToAnyPublisher()
        )

        var received: [NowPlayingState?] = []
        let sub = coordinator.statePublisher.sink { received.append($0) }
        defer { sub.cancel() }

        spotify.send(track("SP", source: .spotify, isPlaying: true))
        #expect(received.last??.title == "SP")

        apple.send(track("AM", source: .appleMusic, isPlaying: true))
        #expect(received.last??.title == "AM")

        coordinator.pin = .spotify
        #expect(received.last??.title == "SP")
    }
}
