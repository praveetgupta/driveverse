#if os(iOS)
import SwiftUI

@main
struct DriveVerseApp: App {
    private let model = AppModel.shared
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
