import Testing
import Foundation
@testable import DriveVerse

@Suite struct LiveActivityUpdateThrottleTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 810_000_000)

    @Test func firstUpdateSendsImmediately() {
        var throttle = LiveActivityUpdateThrottle(minInterval: 1.5)
        #expect(throttle.decide(critical: false, now: t0) == .sendNow)
    }

    @Test func spacedUpdatesAllSend() {
        var throttle = LiveActivityUpdateThrottle(minInterval: 1.5)
        #expect(throttle.decide(critical: false, now: t0) == .sendNow)
        #expect(throttle.decide(critical: false, now: t0.addingTimeInterval(2)) == .sendNow)
        #expect(throttle.decide(critical: false, now: t0.addingTimeInterval(4)) == .sendNow)
    }

    @Test func rapidLineCoalescesWithRemainingDelay() {
        var throttle = LiveActivityUpdateThrottle(minInterval: 1.5)
        _ = throttle.decide(critical: false, now: t0)
        let decision = throttle.decide(critical: false, now: t0.addingTimeInterval(0.5))
        guard case .coalesce(let fireIn) = decision else {
            Issue.record("expected coalesce, got \(decision)")
            return
        }
        #expect(abs(fireIn - 1.0) < 0.0001)
    }

    @Test func criticalAlwaysSendsImmediately() {
        var throttle = LiveActivityUpdateThrottle(minInterval: 1.5)
        _ = throttle.decide(critical: false, now: t0)
        // Track change 0.1 s after a line update must not wait.
        #expect(throttle.decide(critical: true, now: t0.addingTimeInterval(0.1)) == .sendNow)
        // …and it re-anchors the spacing for what follows.
        let after = throttle.decide(critical: false, now: t0.addingTimeInterval(0.2))
        guard case .coalesce = after else {
            Issue.record("expected coalesce after critical send")
            return
        }
    }

    @Test func trailingEdgeReanchorsSpacing() {
        var throttle = LiveActivityUpdateThrottle(minInterval: 1.5)
        _ = throttle.decide(critical: false, now: t0)
        _ = throttle.decide(critical: false, now: t0.addingTimeInterval(0.5)) // pending, fires at 1.5
        throttle.noteSent(now: t0.addingTimeInterval(1.5))
        let decision = throttle.decide(critical: false, now: t0.addingTimeInterval(2.0))
        guard case .coalesce(let fireIn) = decision else {
            Issue.record("expected coalesce, got \(decision)")
            return
        }
        #expect(abs(fireIn - 1.0) < 0.0001)
    }

    /// Stress: a 60 s chorus with a line change every 0.4 s. Sends must never
    /// be closer than the interval, and the newest line must always land via
    /// the trailing edge — nothing may starve.
    @Test func sustainedBurstNeverStarvesAndNeverExceedsRate() {
        var throttle = LiveActivityUpdateThrottle(minInterval: 1.5)
        var sendTimes: [TimeInterval] = []
        var pendingFire: TimeInterval?

        var step = 0.0
        while step < 60 {
            if let fire = pendingFire, fire <= step {
                throttle.noteSent(now: t0.addingTimeInterval(fire))
                sendTimes.append(fire)
                pendingFire = nil
            }
            switch throttle.decide(critical: false, now: t0.addingTimeInterval(step)) {
            case .sendNow:
                sendTimes.append(step)
                pendingFire = nil
            case .coalesce(let fireIn):
                if pendingFire == nil { pendingFire = step + fireIn }
            }
            step += 0.4
        }
        if let fire = pendingFire { sendTimes.append(fire) }

        for pair in zip(sendTimes, sendTimes.dropFirst()) {
            #expect(pair.1 - pair.0 >= 1.5 - 0.0001)
        }
        #expect(sendTimes.count >= 35 && sendTimes.count <= 45) // ~1 per 1.5 s
    }
}

@Suite struct StressTests {
    @Test func parserHandlesHugeDocument() {
        var doc = "[ti:Stress]\n[ar:Nobody]\n"
        for i in 0..<5000 {
            doc += String(format: "[%02d:%02d.00]line %d\n", i / 60, i % 60, i)
        }
        let lines = LRCParser.parse(doc)
        #expect(lines.count == 5000)
        #expect(lines.first?.text == "line 0")
        #expect(lines.last?.text == "line 4999")
        for pair in zip(lines, lines.dropFirst()) {
            #expect(pair.0.timeMs <= pair.1.timeMs)
        }
    }

    @Test func lineIndexBinarySearchOverHugeSheet() {
        let lines = (0..<20_000).map { LRCLine(timeMs: $0 * 250, text: "l\($0)") }
        #expect(SyncEngine.lineIndex(forPositionMs: 0, in: lines) == 0)
        #expect(SyncEngine.lineIndex(forPositionMs: 1_234_567, in: lines) == 4938)
        #expect(SyncEngine.lineIndex(forPositionMs: 20_000 * 250, in: lines) == 19_999)
        for position in stride(from: 0, to: 5_000_000, by: 99_991) {
            #expect(SyncEngine.lineIndex(forPositionMs: position, in: lines) == min(position / 250, 19_999))
        }
    }
}
