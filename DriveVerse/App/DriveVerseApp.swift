#if os(iOS)
import SwiftUI

@main
struct DriveVerseApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(model)
        }
    }
}
#endif
