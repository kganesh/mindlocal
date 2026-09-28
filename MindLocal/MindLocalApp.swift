import SwiftUI
import SwiftData

@main
struct MindLocalApp: App {
    @State private var checkInRouter = NightlyCheckInRouter.shared
    @State private var lock = AppLock.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        FontRegistration.registerBundledFonts()
        NightlyCheckInRouter.shared.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(checkInRouter)
                .tint(AlbumTheme.accent)
                // The cover goes on at `.inactive`, not `.background`, because
                // iOS photographs the screen for the app switcher on the way
                // out and that snapshot is as readable as the journal is.
                .overlay {
                    if lock.isLocked || (lock.isEnabled && scenePhase != .active) {
                        LockScreenView { await lock.unlock() }
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.15), value: lock.isLocked)
                .onChange(of: scenePhase) { previous, phase in
                    // Only a real trip to the background re-locks. Pulling down
                    // Control Centre makes a scene inactive and back again, and
                    // demanding a face for that would make the app exhausting.
                    if phase == .background { lock.lockIfNeeded() }
                    if phase == .active, previous == .background, lock.isLocked {
                        Task { await lock.unlock() }
                    }
                }
                .task {
                    if lock.isLocked { await lock.unlock() }
                }
        }
        .modelContainer(SharedStore.container)
    }
}
