import SwiftUI
import SwiftData

/// Shows an event and proactively generates advice grounded in the user's
/// relevant past decisions and experiences (auto on open, cached). For outdoor
/// events with a location, it also factors in the weather forecast.
struct EventDetailView: View {
    @Bindable var event: Event
    @Environment(\.modelContext) private var modelContext
    @Query private var decisions: [Decision]
    @Query private var experiences: [Experience]

    @State private var phase: Phase = .idle
    @State private var weatherStatus: WeatherStatus = .none
    @State private var speaker = SpeechSpeaker()
    @State private var pickingLocation = false
    private let advisor: AdvisingServicing = AdviceService()
    private let weather: WeatherProviding = WeatherKitService()

    enum Phase: Equatable {
        case idle, thinking, ready, noHistory, error(String)
    }
    enum WeatherStatus: Equatable {
        case none                 // not an outdoor/upcoming/located event
        case loaded(String)
        case unavailable
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
                Button {
                    pickingLocation = true
                } label: {
                    Label(event.location.isEmpty ? "Choose location" : event.location, systemImage: "mappin.circle")
                        .foregroundStyle(event.location.isEmpty ? Color.accentColor : .primary)
                }
                if let lat = event.latitude, let lon = event.longitude {
                    LocationMapPreview(latitude: lat, longitude: lon, name: event.location)
                        .listRowInsets(EdgeInsets())
                }
                switch weatherStatus {
                case .loaded(let line):
                    Label(line, systemImage: "cloud.sun")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                case .unavailable:
                    Label("Weather unavailable for this location or date.", systemImage: "cloud.slash")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                case .none:
                    EmptyView()
                }
            }

            Section {
                adviceContent
            } header: {
                HStack {
                    Label("Suggested advice", systemImage: "sparkles")
                    Spacer()
                    if canRegenerate {
                        Button("Regenerate") { Task { await regenerate() } }
                            .font(.caption)
                    }
                }
            } footer: {
                Text("Grounded in your logged decisions and experiences (on-device). Weather uses Apple WeatherKit.")
            }
        }
        .navigationTitle("Event")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadIfNeeded() }
        .onDisappear { speaker.stop() }
        .sheet(isPresented: $pickingLocation) {
            LocationPickerView { name, lat, lon in
                event.location = name
                event.latitude = lat
                event.longitude = lon
                weatherStatus = .none   // refetch for the new place
            }
        }
    }

    @ViewBuilder
    private var adviceContent: some View {
        switch phase {
        case .idle, .thinking:
            HStack { ProgressView(); Text("Thinking…").foregroundStyle(.secondary) }
        case .ready:
            VStack(alignment: .leading, spacing: 8) {
                Text((event.generatedAdvice ?? "").renderedMarkdown)
                    .textSelection(.enabled)
                Button {
                    speaker.toggle((event.generatedAdvice ?? "").strippedMarkdown)
                } label: {
                    Label(speaker.isSpeaking ? "Stop" : "Read aloud",
                          systemImage: speaker.isSpeaking ? "stop.circle.fill" : "speaker.wave.2.fill")
                        .font(.caption)
                }
            }
        case .noHistory:
            Text("Log a related decision or experience first — advice draws only on what you've recorded.")
                .foregroundStyle(.secondary)
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
        }
    }

    private var canRegenerate: Bool {
        switch phase {
        case .ready, .noHistory, .error: true
        case .idle, .thinking: false
        }
    }

    /// Re-runs advice (e.g. after editing the event's details), refreshing
    /// weather first and overwriting the cached advice.
    private func regenerate() async {
        await refreshWeather()
        await generate()
    }

    private func loadIfNeeded() async {
        // Already generated → show the cached advice immediately, never regenerate.
        if event.generatedAdvice != nil {
            phase = .ready
            await refreshWeather()   // for the forecast line only
            return
        }
        await refreshWeather()       // needed before first generation
        await generate()
    }

    /// Fetches the forecast for outdoor, upcoming, located events; otherwise
    /// leaves the status as `.none`. Sets `.unavailable` if the fetch fails.
    private func refreshWeather() async {
        guard event.isOutdoor, !event.location.isEmpty, event.date > .now else {
            weatherStatus = .none
            return
        }
        // Prefer exact map coordinates; fall back to geocoding the place name.
        let summary: WeatherSummary?
        if let lat = event.latitude, let lon = event.longitude {
            summary = await weather.forecast(latitude: lat, longitude: lon, date: event.date)
        } else {
            summary = await weather.forecast(location: event.location, date: event.date)
        }
        weatherStatus = summary.map { .loaded($0.line) } ?? .unavailable
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

        let weatherText: String? = if case .loaded(let line) = weatherStatus { line } else { nil }

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
            try? modelContext.save()   // persist the cache immediately
            phase = .ready
        } catch AdviceError.modelUnavailable {
            phase = .error("Apple Intelligence isn't available right now.")
        } catch {
            phase = .error("Couldn't generate advice.")
        }
    }
}
