import SwiftUI
import SwiftData

@main
struct MindLocalApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [Decision.self, OptionConsidered.self, Outcome.self, Experience.self])
    }
}
