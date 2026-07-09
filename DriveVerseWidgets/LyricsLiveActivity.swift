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
    }
}

struct LockScreenLyricsView: View {
    let context: ActivityViewContext<LyricsAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: context.state.isPlaying ? "music.note" : "pause.fill")
                    .font(.caption2)
                Text("\(context.attributes.title) — \(context.attributes.artist)")
                    .font(.caption)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(context.attributes.sourceName)
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
        .activityBackgroundTint(Color.black.opacity(0.75))
        .activitySystemActionForegroundColor(.white)
    }
}
#endif
