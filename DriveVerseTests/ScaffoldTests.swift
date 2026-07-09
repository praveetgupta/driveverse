import Testing
import Foundation
@testable import DriveVerse

@Test func scaffoldSanity() {
    let state = NowPlayingState(
        title: "Test Track", artist: "Test Artist", album: nil,
        durationMs: 180_000, positionMs: 0,
        isPlaying: true, source: .appleMusic, capturedAt: Date()
    )
    #expect(state.isPlaying)
    #expect(state.with(isPlaying: false).isPlaying == false)
    #expect(state.isSameTrack(as: state.with(isPlaying: false)))
}
