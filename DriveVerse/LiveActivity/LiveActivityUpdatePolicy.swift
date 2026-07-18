import Foundation

/// Gate for Activity.update calls, per CLAUDE.md §5: update only when the
/// current line index changes, play/pause flips, or the track itself changes —
/// never on the 500 ms tick.
/// Pure value type so the policy is unit-testable without ActivityKit.
struct LiveActivityUpdatePolicy {
    private struct Snapshot: Equatable {
        var trackKey: String
        var lineIndex: Int?
        var isPlaying: Bool
    }

    private var last: Snapshot?

    mutating func shouldUpdate(trackKey: String, lineIndex: Int?, isPlaying: Bool) -> Bool {
        let snapshot = Snapshot(trackKey: trackKey, lineIndex: lineIndex, isPlaying: isPlaying)
        guard snapshot != last else { return false }
        last = snapshot
        return true
    }

    /// Call after starting a fresh activity whose initial content already
    /// reflects the given state, or after ending one.
    mutating func seed(trackKey: String, lineIndex: Int?, isPlaying: Bool) {
        last = Snapshot(trackKey: trackKey, lineIndex: lineIndex, isPlaying: isPlaying)
    }

    mutating func reset() {
        last = nil
    }
}
