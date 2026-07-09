import Foundation
#if canImport(ActivityKit) && os(iOS)
import ActivityKit

/// Shared between the app target and the widget extension.
/// Keep ContentState tiny — it is serialized on every Activity.update.
struct LyricsAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var currentLine: String
        var nextLine: String
        /// 0–1 progress through the whole track.
        var progress: Double
        var isPlaying: Bool
    }

    // Fixed for the lifetime of one activity (one track).
    var title: String
    var artist: String
    var sourceName: String
}
#endif
