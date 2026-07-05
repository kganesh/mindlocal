import SwiftUI
import SwiftData

/// Shows an event and proactively generates advice grounded in the user's
/// relevant past decisions and experiences (auto on open, cached). For outdoor
/// events with a location, it also factors in the weather forecast.
struct EventDetailView: View {
    @Bindable var event: Event
    @Query private var decisions: [Decision]
    @Query private var experiences: [Experience]

    @State private var phase: Phase = .idle
    @State private var weatherLine: String?
    private let advisor: AdvisingServicing = AdviceService()
    private let weather: WeatherProviding = WeatherKitService()

    enum Phase: Equatable {
        case idle, thinking, ready, noHistory, error(String)
    }

    var body: some View {
        Form {
            Section("Event") {
                TextField("Title", text: $event.title)
                DatePicker("When", selection: $event.date)
                Picker("Domain", selection: $event.domainRaw) {
                    ForEach(Domain.allCases) { Text($0.label).tag($0.rawValue) }
                }
                TextField("Notes", text: $event.notes, axis: .vertical)
            }

            Section("Setting") {
                Toggle("Outdoor event", isOn: $event.isOutdoor)
                TextField("Location (city or address)", text: $event.location)
                if let weatherLine {
                    Label(weatherLine, systemImage: "cloud.sun")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                adviceContent
            } header: {
                Label("Suggested advice", systemImage: "sparkles")
            } footer: {
                Text("Grounded in your logged decisions and experiences (on-device). Weather uses Apple WeatherKit.")
            }
        }
        .navigationTitle("Event")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadIfNeeded() }
    }

    @ViewBuilder
    private var adviceContent: some View {
        switch phase {
        case .idle, .thinking:
            HStack { ProgressView(); Text("Thinking…").foregroundStyle(.secondary) }
        case .ready:
            Text(event.generatedAdvice ?? "")
                .textSelection(.enabled)
        case .noHistory:
            Text("Log a related decision or experience first — advice draws only on what you've recorded.")
                .foregroundStyle(.secondary)
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
        }
    }

    private func loadIfNeeded() async {
        if event.generatedAdvice != nil { phase = .ready } else { await generate() }
    }

    private func generate() async {
        phase = .thinking

        let decisionSummaries = decisions.map(DecisionSummary.init)
        let experienceSummaries = experiences.map(ExperienceSummary.init)
        let keywords = EventMatcher.keywords("\(event.title) \(event.notes)")
        let relevant = EventMatcher.relevant(
            eventDomain: event.domain.label,
            keywords: keywords,
            decisions: decisionSummaries,
            experiences: experienceSummaries
        )
        guard !(relevant.decisions.isEmpty && relevant.experiences.isEmpty) else {
            phase = .noHistory
            return
        }

        // Weather only for outdoor, upcoming events with a location.
        var weatherText: String?
        if event.isOutdoor, !event.location.isEmpty, event.date > .now {
            if let summary = await weather.forecast(location: event.location, date: event.date) {
                weatherText = summary.line
                weatherLine = summary.line
            }
        }

        do {
            let advice = try await advisor.eventAdvice(
                event: event.title,
                when: event.date,
                weather: weatherText,
                decisions: relevant.decisions,
                experiences: relevant.experiences
            )
            event.generatedAdvice = advice
            event.adviceGeneratedAt = .now
            phase = .ready
        } catch AdviceError.modelUnavailable {
            phase = .error("Apple Intelligence isn't available right now.")
        } catch {
            phase = .error("Couldn't generate advice.")
        }
    }
}
