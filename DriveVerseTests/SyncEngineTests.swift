import Testing
import Foundation
@testable import DriveVerse

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func state(
    title: String = "Track",
    positionMs: Int,
    isPlaying: Bool = true,
    durationMs: Int? = 240_000,
    capturedAt: Date = t0,
    source: MusicSource = .spotify
) -> NowPlayingState {
    NowPlayingState(
        title: title, artist: "Artist", album: nil,
        durationMs: durationMs, positionMs: positionMs,
        isPlaying: isPlaying, source: source, capturedAt: capturedAt
    )
}

@Suite struct SyncEngineExtrapolationTests {
    @Test func extrapolatesWhilePlaying() {
        let anchor = state(positionMs: 10_000)
        let pos = SyncEngine.extrapolatedPositionMs(anchor: anchor, at: t0.addingTimeInterval(2.5))
        #expect(pos == 12_500)
    }

    @Test func frozenWhilePaused() {
        let anchor = state(positionMs: 10_000, isPlaying: false)
        let pos = SyncEngine.extrapolatedPositionMs(anchor: anchor, at: t0.addingTimeInterval(30))
        #expect(pos == 10_000)
    }

    @Test func clampedToDuration() {
        let anchor = state(positionMs: 239_000, durationMs: 240_000)
        let pos = SyncEngine.extrapolatedPositionMs(anchor: anchor, at: t0.addingTimeInterval(10))
        #expect(pos == 240_000)
    }
}

@Suite struct SyncEngineLineIndexTests {
    let lines = [
        LRCLine(timeMs: 5_000, text: "one"),
        LRCLine(timeMs: 10_000, text: "two"),
        LRCLine(timeMs: 20_000, text: "three"),
        LRCLine(timeMs: 30_000, text: "four"),
    ]

    @Test func beforeFirstLineIsNil() {
        #expect(SyncEngine.lineIndex(forPositionMs: 0, in: lines) == nil)
        #expect(SyncEngine.lineIndex(forPositionMs: 4_999, in: lines) == nil)
    }

    @Test func exactTimestampSelectsLine() {
        #expect(SyncEngine.lineIndex(forPositionMs: 5_000, in: lines) == 0)
        #expect(SyncEngine.lineIndex(forPositionMs: 20_000, in: lines) == 2)
    }

    @Test func betweenTimestampsSelectsEarlier() {
        #expect(SyncEngine.lineIndex(forPositionMs: 12_345, in: lines) == 1)
    }

    @Test func afterLastSelectsLast() {
        #expect(SyncEngine.lineIndex(forPositionMs: 500_000, in: lines) == 3)
    }

    @Test func emptyLyrics() {
        #expect(SyncEngine.lineIndex(forPositionMs: 10_000, in: []) == nil)
    }
}

@Suite struct SyncEngineSeekTests {
    @Test func jitterWithinThresholdKeepsAnchor() {
        var fakeNow = t0
        let engine = SyncEngine(now: { fakeNow })
        engine.apply(state(positionMs: 10_000, capturedAt: t0))

        // 1 s later Spotify reports 10.5 s where we extrapolate 11 s — jitter, ignore.
        fakeNow = t0.addingTimeInterval(1)
        engine.apply(state(positionMs: 10_500, capturedAt: fakeNow))
        #expect(engine.anchor?.positionMs == 10_000)
        #expect(engine.anchor?.capturedAt == t0)
    }

    @Test func seekBeyondThresholdSnaps() {
        var fakeNow = t0
        let engine = SyncEngine(now: { fakeNow })
        engine.apply(state(positionMs: 10_000, capturedAt: t0))

        // 1 s later the report says 25 s — a real seek, snap to it.
        fakeNow = t0.addingTimeInterval(1)
        engine.apply(state(positionMs: 25_000, capturedAt: fakeNow))
        #expect(engine.anchor?.positionMs == 25_000)
    }

    @Test func trackChangeAlwaysSnaps() {
        let engine = SyncEngine(now: { t0 })
        engine.apply(state(title: "Old", positionMs: 100_000))
        engine.apply(state(title: "New", positionMs: 500, capturedAt: t0.addingTimeInterval(0.1)))
        #expect(engine.anchor?.title == "New")
        #expect(engine.anchor?.positionMs == 500)
    }

    @Test func playPauseFlipAdoptsNewAnchor() {
        let engine = SyncEngine(now: { t0 })
        engine.apply(state(positionMs: 10_000, isPlaying: true))
        engine.apply(state(positionMs: 10_400, isPlaying: false, capturedAt: t0.addingTimeInterval(0.4)))
        #expect(engine.anchor?.isPlaying == false)
        #expect(engine.anchor?.positionMs == 10_400)
    }
}

@Suite struct SyncEnginePositionOutputTests {
    let lines = [
        LRCLine(timeMs: 5_000, text: "one"),
        LRCLine(timeMs: 10_000, text: "two"),
        LRCLine(timeMs: 20_000, text: "three"),
    ]

    @Test func publishesCurrentAndNextLine() {
        var fakeNow = t0
        let engine = SyncEngine(now: { fakeNow })
        engine.setLyrics(lines)
        engine.apply(state(positionMs: 10_000, capturedAt: t0))

        fakeNow = t0.addingTimeInterval(2) // extrapolated to 12 s
        engine.tick()

        let pos = try? #require(engine.positionSubject.value)
        #expect(pos?.lineIndex == 1)
        #expect(pos?.currentLine == "two")
        #expect(pos?.nextLine == "three")
        #expect(pos?.positionMs == 12_000)
        // line window 10 s → 20 s, position 12 s ⇒ 20 %
        #expect(abs((pos?.lineProgress ?? 0) - 0.2) < 0.001)
        // track 240 s, position 12 s ⇒ 5 %
        #expect(abs((pos?.trackProgress ?? 0) - 0.05) < 0.001)
    }

    @Test func beforeFirstLineShowsUpcoming() {
        let engine = SyncEngine(now: { t0 })
        engine.setLyrics(lines)
        engine.apply(state(positionMs: 1_000, capturedAt: t0))

        let pos = engine.positionSubject.value
        #expect(pos?.lineIndex == nil)
        #expect(pos?.currentLine == nil)
        #expect(pos?.nextLine == "one")
    }

    @Test func nilStateClearsPosition() {
        let engine = SyncEngine(now: { t0 })
        engine.setLyrics(lines)
        engine.apply(state(positionMs: 10_000))
        #expect(engine.positionSubject.value != nil)
        engine.apply(nil)
        #expect(engine.positionSubject.value == nil)
    }
}
