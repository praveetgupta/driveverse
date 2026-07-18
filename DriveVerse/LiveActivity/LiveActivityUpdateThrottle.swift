import Foundation

/// Spacing decision for Activity.update calls. Rapid line changes (choruses)
/// are coalesced instead of dropped: the caller replaces the pending content
/// and fires it when the interval elapses, so the tile always converges to
/// the newest line — at worst `minInterval` late — and no line ever sticks.
/// Track changes and play/pause flips are critical and always send now.
/// Pure value type so the spacing rules are unit-testable without ActivityKit.
struct LiveActivityUpdateThrottle {
    enum Decision: Equatable {
        case sendNow
        /// Replace any pending content with the newest and (if not already
        /// armed) schedule it to fire after this delay.
        case coalesce(fireIn: TimeInterval)
    }

    let minInterval: TimeInterval
    private var lastSentAt: Date?

    init(minInterval: TimeInterval) {
        self.minInterval = minInterval
    }

    mutating func decide(critical: Bool, now: Date) -> Decision {
        if critical {
            lastSentAt = now
            return .sendNow
        }
        if let last = lastSentAt {
            let remaining = minInterval - now.timeIntervalSince(last)
            if remaining > 0 {
                return .coalesce(fireIn: remaining)
            }
        }
        lastSentAt = now
        return .sendNow
    }

    /// Record a send performed outside decide() — the initial
    /// Activity.request, or a coalesced update firing.
    mutating func noteSent(now: Date) {
        lastSentAt = now
    }
}
