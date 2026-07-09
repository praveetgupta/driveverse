import Testing
@testable import DriveVerse

// #expect can't evaluate mutating calls inline, so results land in locals first.
@Suite struct LiveActivityUpdatePolicyTests {
    @Test func updateCountEqualsLineChangesNotTicks() {
        var policy = LiveActivityUpdatePolicy()
        // A song's worth of synthetic 500 ms ticks: 16 ticks, but only
        // 4 distinct line transitions after the initial state.
        let lineIndexPerTick: [Int?] = [
            nil, nil, nil,      // intro, before the first line
            0, 0, 0, 0,
            1, 1,
            2, 2, 2, 2, 2,
            3, 3,
        ]
        var updates = 0
        for index in lineIndexPerTick where policy.shouldUpdate(lineIndex: index, isPlaying: true) {
            updates += 1
        }
        #expect(updates == 5) // initial (nil) + 4 line changes — not 16
    }

    @Test func playPauseFlipTriggersUpdate() {
        var policy = LiveActivityUpdatePolicy()
        let initial = policy.shouldUpdate(lineIndex: 3, isPlaying: true)
        let repeated = policy.shouldUpdate(lineIndex: 3, isPlaying: true)
        let paused = policy.shouldUpdate(lineIndex: 3, isPlaying: false)
        let stillPaused = policy.shouldUpdate(lineIndex: 3, isPlaying: false)
        let resumed = policy.shouldUpdate(lineIndex: 3, isPlaying: true)
        #expect(initial)
        #expect(!repeated)
        #expect(paused)
        #expect(!stillPaused)
        #expect(resumed)
    }

    @Test func seedSuppressesTheImmediateFollowUp() {
        var policy = LiveActivityUpdatePolicy()
        policy.seed(lineIndex: 2, isPlaying: true)
        // Activity.request already showed this exact content.
        let sameAsSeed = policy.shouldUpdate(lineIndex: 2, isPlaying: true)
        let nextLine = policy.shouldUpdate(lineIndex: 3, isPlaying: true)
        #expect(!sameAsSeed)
        #expect(nextLine)
    }

    @Test func resetAllowsNextUpdate() {
        var policy = LiveActivityUpdatePolicy()
        let first = policy.shouldUpdate(lineIndex: 1, isPlaying: true)
        policy.reset()
        let afterReset = policy.shouldUpdate(lineIndex: 1, isPlaying: true)
        #expect(first)
        #expect(afterReset)
    }
}
