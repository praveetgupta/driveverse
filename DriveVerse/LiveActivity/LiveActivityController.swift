import Foundation

#if os(iOS) && canImport(ActivityKit)
import ActivityKit

/// Owns the lyrics Live Activity lifecycle:
/// start when a track with synced lyrics is playing, update only on line
/// change / play-pause flip (see LiveActivityUpdatePolicy), end 30 s after
/// playback stops or immediately when a lyric-less track takes over.
/// On iOS 26 the lock-screen presentation is mirrored onto CarPlay for free.
@MainActor
final class LiveActivityController {
    static let endDelay: TimeInterval = 30

    private var activity: Activity<LyricsAttributes>?
    private var currentKey: String?
    private var policy = LiveActivityUpdatePolicy()
    private var endTask: Task<Void, Never>?
    private var pendingStart = false

    /// Drive Mode's keep-alive only runs while an activity is actually up.
    var isActive: Bool { activity != nil }

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
        guard let state, hasSyncedLyrics else {
            // Nothing displayable. Kill a stale activity right away if another
            // (lyric-less) track took over, else wind down after the grace period.
            if activity != nil {
                if let state, Self.key(for: state) != currentKey {
                    Task { await endNow() }
                } else {
                    scheduleEnd()
                }
            }
            return
        }

        let key = Self.key(for: state)
        if activity == nil || key != currentKey {
            guard !pendingStart else { return }
            pendingStart = true
            Task {
                await startFresh(state: state, position: position, key: key)
                pendingStart = false
            }
            return
        }

        if state.isPlaying {
            cancelScheduledEnd()
        } else {
            scheduleEnd()
        }

        if policy.shouldUpdate(lineIndex: position?.lineIndex, isPlaying: state.isPlaying) {
            let content = Self.content(state: state, position: position)
            Task {
                await activity?.update(ActivityContent(state: content, staleDate: nil))
            }
        }
    }

    func endNow() async {
        endTask?.cancel()
        endTask = nil
        guard let activity else { return }
        self.activity = nil
        currentKey = nil
        policy.reset()
        await activity.end(nil, dismissalPolicy: .immediate)
    }

    // MARK: - Internals

    private func startFresh(state: NowPlayingState, position: LyricsPosition?, key: String) async {
        await endNow()
        // Only begin an activity when playback is actually running.
        guard state.isPlaying, ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = LyricsAttributes(
            title: state.title,
            artist: state.artist,
            sourceName: state.source.displayName
        )
        let content = Self.content(state: state, position: position)
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: content, staleDate: nil)
            )
            currentKey = key
            policy.seed(lineIndex: position?.lineIndex, isPlaying: state.isPlaying)
        } catch {
            activity = nil
            currentKey = nil
        }
    }

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
            currentLine: position?.currentLine ?? "♪",
            nextLine: position?.nextLine ?? "",
            progress: position?.trackProgress ?? 0,
            isPlaying: state.isPlaying
        )
    }
}
#endif
