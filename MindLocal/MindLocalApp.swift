import SwiftUI
import SwiftData

@main
struct MindLocalApp: App {
    @State private var checkInRouter = NightlyCheckInRouter.shared

    init() {
        FontRegistration.registerBundledFonts()
        NightlyCheckInRouter.shared.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(checkInRouter)
        }
        .modelContainer(SharedStore.container)
    }
}
