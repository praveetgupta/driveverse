#if canImport(ActivityKit) && canImport(WidgetKit)
import WidgetKit
import SwiftUI
import ActivityKit

@main
struct DriveVerseWidgetsBundle: WidgetBundle {
    var body: some Widget {
        LyricsLiveActivity()
    }
}

struct LyricsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LyricsAttributes.self) { context in
            // Lock screen — on iOS 26 this same presentation is shown on the
            // CarPlay screen, so it stays high-contrast and sparse:
            // one small meta row, two text rows, a progress bar.
            LockScreenLyricsView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.isPlaying ? "music.note" : "pause.fill")
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.state.currentLine)
                            .font(.headline)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                        Text(context.state.nextLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: context.state.progress)
                        .tint(.white.opacity(0.85))
                        .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: context.state.isPlaying ? "music.note" : "pause.fill")
                    .foregroundStyle(.tint)
            } compactTrailing: {
                Text(context.state.currentLine)
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(maxWidth: 72)
            } minimal: {
                Image(systemName: "music.note")
                    .foregroundStyle(.tint)
            }
        }
        // CarPlay (and the Watch Smart Stack) render the .small family;
        // without this opt-in they fall back to the compact Dynamic Island
        // views, which truncate the lyric to one short marquee.
        .supplementalActivityFamilies([.small])
    }
}

struct LockScreenLyricsView: View {
    let context: ActivityViewContext<LyricsAttributes>
    @Environment(\.activityFamily) private var family

    var body: some View {
        Group {
            if family == .small {
                smallBody
            } else {
                mediumBody
            }
        }
        .activityBackgroundTint(Color.black.opacity(0.75))
        .activitySystemActionForegroundColor(.white)
    }

    /// CarPlay tile / Watch Smart Stack: no room for meta chrome — the
    /// lyric IS the content. Two rows, high contrast. No progress bar:
    /// an observer app can't seek, so it would never be interactive and
    /// only steals space from the lyric.
    private var smallBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(context.state.currentLine)
                .font(.title3.bold())
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .contentTransition(.opacity)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(context.state.nextLine)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .id(context.state.nextLine)
                .transition(.push(from: .bottom))
        }
        .padding(10)
        .animation(.smooth(duration: 0.5), value: context.state)
    }

    private var mediumBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: context.state.isPlaying ? "music.note" : "pause.fill")
                    .font(.caption2)
                Text("\(context.state.title) — \(context.state.artist)")
                    .font(.caption)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(context.state.sourceName)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.15), in: Capsule())
            }
            .foregroundStyle(.secondary)

            Text(context.state.currentLine)
                .font(.title2.bold())
                .lineLimit(2)
                .minimumScaleFactor(0.75)

            Text(context.state.nextLine)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            ProgressView(value: context.state.progress)
                .tint(.white.opacity(0.85))
        }
        .padding(14)
    }
}
#endif
