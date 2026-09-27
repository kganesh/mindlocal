import SwiftUI
import FoundationModels
import SwiftData

/// Availability gate (spec §8) + tab shell (spec §4).
struct RootView: View {
    private let model = SystemLanguageModel.default

    var body: some View {
        switch model.availability {
        case .available:
            MainTabView()
        case .unavailable(.deviceNotEligible):
            UnavailableView(
                title: "Device Not Supported",
                message: "MindLocal needs Apple Intelligence, which this device doesn't support."
            )
        case .unavailable(.appleIntelligenceNotEnabled):
            UnavailableView(
                title: "Turn On Apple Intelligence",
                message: "Enable Apple Intelligence in Settings to use MindLocal."
            )
        case .unavailable(.modelNotReady):
            UnavailableView(
                title: "Getting Ready",
                message: "The on-device model is downloading. You can capture notes; they'll be processed when it's ready."
            )
        case .unavailable:
            UnavailableView(
                title: "Temporarily Unavailable",
                message: "The on-device model isn't available right now. Please try again later."
            )
        }
    }
}

struct MainTabView: View {
    /// AlbumTheme's tokens are statics read from 28 files, so changing the
    /// palette does not invalidate any view on its own. Watching the same key
    /// here rebuilds the tree, and every token is re-read on the way down.
    @AppStorage(AlbumTheme.paletteKey) private var paletteID = AlbumPalette.album.id

    @Environment(NightlyCheckInRouter.self) private var checkInRouter
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        @Bindable var router = checkInRouter
        TabView {
            Tab("Today", systemImage: "book.pages") {
                TodayDiaryView()
            }
            Tab("Journal", systemImage: "book") {
                ExperienceListView()
            }
            Tab("People", systemImage: "person.2") {
                PeopleListView()
            }
            Tab("Ask", systemImage: "bubble.left") {
                AdviceView()
            }
        }
        .tint(AlbumTheme.accent)
        .id(paletteID)
        // Night Sky has no light variant to switch to, so it takes the whole
        // app dark rather than letting system chrome — sheets, pickers, the
        // keyboard — come back in light while the walls stay black.
        .preferredColorScheme(AlbumTheme.palette.forcesDarkAppearance ? .dark : nil)
        .toolbarBackground(AlbumTheme.barStyle, for: .tabBar)
        // Same omission as the navigation bar had: setting the colour without
        // setting visibility leaves the bar transparent at scroll edge, and
        // scroll content runs underneath it. On Today that clipped the bottom
        // off "Your moments will collect here, one entry at a time."
        .toolbarBackground(.visible, for: .tabBar)
        // Tapping the nightly reminder opens the voice check-in.
        .fullScreenCover(isPresented: $router.isActive) {
            JournalConversationView()
        }
        .task {
            await BirthdayEventDeriver.ensureUpcomingEvents(in: modelContext)
            MemoryGraphStore.rebuildAndPersist(in: modelContext)
        }
    }
}

struct UnavailableView: View {
    let title: String
    let message: String

    var body: some View {
        ContentUnavailableView(
            title,
            systemImage: "brain",
            description: Text(message)
        )
    }
}

#Preview { RootView().environment(NightlyCheckInRouter.shared) }
