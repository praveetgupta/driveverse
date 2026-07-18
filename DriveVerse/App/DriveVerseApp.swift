#if os(iOS)
import SwiftUI

@main
struct DriveVerseApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(model)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.foregroundResync() }
                }
        }
    }
}
#endif
