import SwiftUI
import SwiftData

@main
struct MindLocalApp: App {
    @State private var checkInRouter = NightlyCheckInRouter.shared

    init() {
        NightlyCheckInRouter.shared.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(checkInRouter)
        }
        .modelContainer(for: [Decision.self, OptionConsidered.self, Outcome.self, Experience.self, Event.self])
    }
}
