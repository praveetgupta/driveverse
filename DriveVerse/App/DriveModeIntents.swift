#if os(iOS)
import AppIntents

/// Run by the Shortcuts CarPlay automations (see README). LiveActivityIntent
/// executes in the app's process — launching it into the background if it
/// isn't running — and is the one context iOS allows Activity.request from
/// without the app being foregrounded.
struct StartDriveModeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start Drive Mode"
    static let description = IntentDescription(
        "Turns on Drive Mode and starts the lyrics Live Activity for whatever plays next."
    )

    func perform() async throws -> some IntentResult {
        let model = await AppModel.shared
        await model.startDriveSession()
        // Hold the intent open so the first player/Spotify read flows through
        // the pipeline while the LiveActivityIntent grant is in effect.
        try? await Task.sleep(for: .seconds(3))
        return .result()
    }
}

struct StopDriveModeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Drive Mode"
    static let description = IntentDescription(
        "Turns off Drive Mode and ends the lyrics Live Activity."
    )

    func perform() async throws -> some IntentResult {
        let model = await AppModel.shared
        await model.stopDriveSession()
        return .result()
    }
}

struct DriveVerseShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartDriveModeIntent(),
            phrases: ["Start \(.applicationName) Drive Mode"],
            shortTitle: "Start Drive Mode",
            systemImageName: "car.fill"
        )
        AppShortcut(
            intent: StopDriveModeIntent(),
            phrases: ["Stop \(.applicationName) Drive Mode"],
            shortTitle: "Stop Drive Mode",
            systemImageName: "car"
        )
    }
}
#endif
