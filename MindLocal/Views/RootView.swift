import SwiftUI
import FoundationModels

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
                message: "Decision Memory needs Apple Intelligence, which this device doesn't support."
            )
        case .unavailable(.appleIntelligenceNotEnabled):
            UnavailableView(
                title: "Turn On Apple Intelligence",
                message: "Enable Apple Intelligence in Settings to use Decision Memory."
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
    var body: some View {
        TabView {
            Tab("Decisions", systemImage: "list.bullet.rectangle") {
                DecisionListView()
            }
            Tab("Experiences", systemImage: "sparkle") {
                ExperienceListView()
            }
            Tab("Capture", systemImage: "mic.circle.fill") {
                CaptureView()
            }
            Tab("Calendar", systemImage: "calendar") {
                CalendarView()
            }
            Tab("Advise", systemImage: "sparkles") {
                AdviceView()
            }
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

#Preview { RootView() }
