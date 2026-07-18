import Foundation

#if os(iOS) && canImport(ActivityKit)
import ActivityKit

/// Owns the lyrics Live Activity lifecycle.
///
/// One activity spans the whole listening session: iOS refuses
/// Activity.request from a backgrounded app, so the original
/// end-and-restart-per-track design lost the tile on every backgrounded song
/// change. Track changes are now plain updates (allowed from the background);
/// the activity ends only after playback has stopped for the grace period.
/// Lyric-less tracks keep the tile alive showing "♪ title" so a later track
/// with lyrics doesn't need a (background-impossible) fresh start.
/// On iOS 26 the lock-screen presentation is mirrored onto CarPlay for free.
@MainActor
final class LiveActivityController {
    static let endDelay: TimeInterval = 30

    private var activity: Activity<LyricsAttributes>?
    private var policy = LiveActivityUpdatePolicy()
    private var endTask: Task<Void, Never>?

    /// Drive Mode's keep-alive only runs while an activity is actually up.
    var isActive: Bool { activity != nil }

    /// While Drive Mode is on the session must survive arbitrary pauses:
    /// hold the activity (pause glyph) instead of ending it after the grace
    /// period, because a fresh start would need the foreground.
    var holdWhilePaused = false

    init() {
        // Clean up activities orphaned by a previous app termination.
        Task {
            for stale in Activity<LyricsAttributes>.activities {
                await stale.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    /// Single entry point, called from AppModel on every state/position change.
    func sync(state: NowPlayingState?, position: LyricsPosition?, hasSyncedLyrics: Bool) {
        guard let state else {
            if holdWhilePaused { cancelScheduledEnd() } else { scheduleEnd() }
            return
        }

        guard let activity else {
            // First start needs a playing track with synced lyrics and a
            // foregrounded app — the request throws in the background and is
            // simply retried on a later sync (heals on foreground resync).
            // The Start Drive Mode intent bypasses this via beginSession.
            if state.isPlaying, hasSyncedLyrics {
                beginSession(state: state, position: position)
            }
            return
        }

        if state.isPlaying || holdWhilePaused {
            cancelScheduledEnd()
        } else {
            scheduleEnd()
        }

        if policy.shouldUpdate(
            trackKey: Self.key(for: state),
            lineIndex: position?.lineIndex,
            isPlaying: state.isPlaying
        ) {
            let content = Self.content(state: state, position: position)
            Task {
                await activity.update(ActivityContent(state: content, staleDate: nil))
            }
        }
    }

    /// Requests the session's activity. Reached two ways: from sync() once a
    /// lyric-bearing track plays in the foreground, or from the Start Drive
    /// Mode intent — the one background context iOS grants Activity.request
    /// to. The intent path may run before any music plays; the placeholder
    /// content matters because a background app can only *update* from then on.
    func beginSession(state: NowPlayingState?, position: LyricsPosition?) {
        guard activity == nil, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let content = state.map { Self.content(state: $0, position: position) }
            ?? LyricsAttributes.ContentState(
                title: "DriveVerse", artist: "", sourceName: "",
                currentLine: "♪ Waiting for music…", nextLine: "",
                progress: 0, isPlaying: false
            )
        do {
            activity = try Activity.request(
                attributes: LyricsAttributes(),
                content: ActivityContent(state: content, staleDate: nil)
            )
            if let state {
                policy.seed(
                    trackKey: Self.key(for: state),
                    lineIndex: position?.lineIndex,
                    isPlaying: state.isPlaying
                )
            } else {
                policy.reset()
            }
        } catch {
            activity = nil
        }
    }

    func endNow() async {
        endTask?.cancel()
        endTask = nil
        guard let activity else { return }
        self.activity = nil
        policy.reset()
        await activity.end(nil, dismissalPolicy: .immediate)
    }

    // MARK: - Internals

    private func scheduleEnd() {
        guard endTask == nil, activity != nil else { return }
        endTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.endDelay))
            guard !Task.isCancelled else { return }
            await self?.endNow()
        }
    }

    private func cancelScheduledEnd() {
        endTask?.cancel()
        endTask = nil
    }

    private static func key(for state: NowPlayingState) -> String {
        "\(state.title)|\(state.artist)|\(state.source.rawValue)"
    }

    private static func content(state: NowPlayingState, position: LyricsPosition?) -> LyricsAttributes.ContentState {
        LyricsAttributes.ContentState(
            title: state.title,
            artist: state.artist,
            sourceName: state.source.displayName,
            currentLine: position?.currentLine ?? "♪ \(state.title)",
            nextLine: position?.nextLine ?? "",
            progress: position?.trackProgress ?? 0,
            isPlaying: state.isPlaying
        )
    }
}
#endif
