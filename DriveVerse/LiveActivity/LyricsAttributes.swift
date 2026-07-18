import Foundation
#if canImport(ActivityKit) && os(iOS)
import ActivityKit

/// Shared between the app target and the widget extension.
/// Keep ContentState tiny — it is serialized on every Activity.update.
///
/// There are deliberately no fixed attributes: one activity spans a whole
/// listening session (iOS refuses Activity.request from a backgrounded app,
/// so per-track activities would vanish on every backgrounded song change).
/// Everything, including the track metadata, must be updatable.
struct LyricsAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var artist: String
        var sourceName: String
        var currentLine: String
        var nextLine: String
        /// 0–1 progress through the whole track.
        var progress: Double
        var isPlaying: Bool
    }
}
#endif
