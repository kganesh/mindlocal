import SwiftUI
import SwiftData

/// The app's warm home surface: today's diary page, with direct writing,
/// location/weather context, and the day's structured memories below it.
struct TodayDiaryView: View {
    @Query(sort: \Experience.createdAt, order: .reverse) private var experiences: [Experience]
    @Query(sort: \Event.date, order: .forward) private var events: [Event]
    @Query private var people: [Person]
    @Query private var relationships: [PersonRelationship]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var viewModel = CaptureViewModel()
    @State private var locationProvider = CurrentLocationProvider()
    @State private var weatherService = WeatherKitService()
    @State private var pageLocation = ""
    @State private var pageLatitude: Double?
    @State private var pageLongitude: Double?
    @State private var weatherSummary: WeatherSummary?
    @State private var loadingWeather = false
    @State private var pickingLocation = false
    @State private var addSheet: AddSheet?
    @State private var showingAsk = false
    @State private var showingTimeline = false
    @State private var peopleConfirmed = false
    @FocusState private var editorFocused: Bool

    private let paper = Color(red: 0.98, green: 0.96, blue: 0.89)
    private let paperShadow = Color(red: 0.36, green: 0.28, blue: 0.18).opacity(0.18)
    private let ink = Color(red: 0.20, green: 0.16, blue: 0.12)
    private let rule = Color(red: 0.50, green: 0.42, blue: 0.30).opacity(0.18)

    private var todayExperiences: [Experience] {
        experiences
            .filter { Calendar.current.isDateInToday($0.timelineDate) }
            .sorted { $0.timelineDate > $1.timelineDate }
    }

    private var todayEvents: [Event] {
        events
            .filter { Calendar.current.isDateInToday($0.date) }
            .sorted { $0.date < $1.date }
    }

    private var peopleToConfirm: [String] {
        guard let draft = viewModel.experienceDraft else { return [] }
        return PersonResolver.mentionsNeedingConfirmation(draft.people, people: people, relationships: relationships)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    diaryPage
                    todayMemoryStack
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingTimeline = true } label: {
                        Image(systemName: "calendar")
                    }
                    .accessibilityLabel("Timeline")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { addSheet = .experience } label: {
                            Label("Experience Entry", systemImage: "square.and.pencil")
                        }
                        Button { addSheet = .event } label: {
                            Label("Event", systemImage: "calendar.badge.plus")
                        }
                        Button { addSheet = .conversation } label: {
                            Label("Voice Check-In", systemImage: "moon.stars")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add")
                }
            }
            .sheet(item: $addSheet) { sheet in
                switch sheet {
                case .experience:
                    CaptureView()
                case .event:
                    EventFormView { modelContext.insert($0) }
                case .conversation:
                    JournalConversationView()
                }
            }
            .sheet(isPresented: $showingAsk) { AdviceView() }
            .sheet(isPresented: $showingTimeline) { CalendarView() }
            .sheet(isPresented: $pickingLocation) {
                LocationPickerView { name, lat, lon in
                    pageLocation = name
                    pageLatitude = lat
                    pageLongitude = lon
                    applyPageLocationToDraft()
                    Task { await refreshWeather() }
                }
            }
            .sheet(isPresented: reviewPresented) {
                TodayCaptureReviewSheet(
                    viewModel: viewModel,
                    peopleConfirmed: $peopleConfirmed,
                    peopleToConfirm: peopleToConfirm,
                    onSave: saveExtractedEntry,
                    onSaveRaw: saveRawEntry
                )
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { viewModel.persistWorkInProgress() }
            }
            .task { await loadPageContext() }
        }
    }

    private var diaryPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            Rectangle()
                .fill(rule)
                .frame(height: 1)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $viewModel.typedText)
                    .font(.custom("Caveat-Regular", size: 30))
                    .lineSpacing(6)
                    .foregroundStyle(ink)
                    .frame(minHeight: 260)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .focused($editorFocused)
                    .onChange(of: viewModel.speech.transcript) { _, newValue in
                        if viewModel.speech.isRecording { viewModel.typedText = newValue }
                    }
                if viewModel.typedText.isEmpty && !viewModel.speech.isRecording {
                    Text("Write today's diary log here...")
                        .font(.custom("Caveat-Regular", size: 30))
                        .foregroundStyle(ink.opacity(0.38))
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }

            HStack(spacing: 12) {
                Button {
                    Task { await toggleMic() }
                } label: {
                    Image(systemName: viewModel.speech.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(viewModel.speech.isRecording ? .red : .accentColor)
                        .symbolEffect(.pulse, isActive: viewModel.speech.isRecording)
                }
                .accessibilityLabel(viewModel.speech.isRecording ? "Stop dictation" : "Dictate diary log")

                Button {
                    showingAsk = true
                } label: {
                    Label("Ask", systemImage: "sparkles")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    editorFocused = false
                    applyPageLocationToDraft()
                    Task { await viewModel.submit() }
                } label: {
                    Label(saveButtonTitle, systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(paper, in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: paperShadow, radius: 14, x: 0, y: 8)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button { editorFocused = false } label: {
                    Image(systemName: "checkmark").fontWeight(.semibold)
                }
                .accessibilityLabel("Done")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                .font(.custom("Caveat-Bold", size: 30))
                .foregroundStyle(ink.opacity(0.75))

            Button {
                pickingLocation = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "mappin.and.ellipse")
                    Text(contextLine)
                        .lineLimit(2)
                    if loadingWeather {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }
                .font(.custom("Caveat-Regular", size: 21))
                .foregroundStyle(ink.opacity(0.55))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Location and weather")
        }
    }

    private var todayMemoryStack: some View {
        VStack(alignment: .leading, spacing: 12) {
            if todayExperiences.isEmpty && todayEvents.isEmpty {
                Text("Saved memories for today will appear here after you write, add an experience, or create an event.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            } else {
                if !todayExperiences.isEmpty {
                    memorySection("Entries", systemImage: "book.closed", count: todayExperiences.count) {
                        ForEach(todayExperiences) { experience in
                            NavigationLink {
                                DiaryPageView(experience: experience)
                            } label: {
                                ExperienceMemoryCard(experience: experience, people: people)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !todayEvents.isEmpty {
                    memorySection("Events", systemImage: "calendar", count: todayEvents.count) {
                        ForEach(todayEvents) { event in
                            NavigationLink {
                                EventDetailView(event: event)
                            } label: {
                                EventMemoryCard(event: event)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func memorySection<Content: View>(
        _ title: String,
        systemImage: String,
        count: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("\(title) \(count)", systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.primary)
                .padding(.horizontal, 4)
            content()
        }
    }

    private var contextLine: String {
        let location = pageLocation.isEmpty ? "Add location" : pageLocation
        if let weatherSummary {
            return "\(location) - \(weatherSummary.line)"
        }
        return location
    }

    private var canSubmit: Bool {
        !viewModel.typedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && viewModel.phase != .extracting
    }

    private var saveButtonTitle: String {
        viewModel.phase == .extracting ? "Saving..." : "Save"
    }

    private var reviewPresented: Binding<Bool> {
        Binding {
            switch viewModel.phase {
            case .preview, .nothingFound, .error:
                true
            case .input, .extracting:
                false
            }
        } set: { isPresented in
            if !isPresented, viewModel.phase != .input {
                viewModel.phase = .input
                peopleConfirmed = false
            }
        }
    }

    private func loadPageContext() async {
        if pageLocation.isEmpty {
            await useCurrentLocationIfAvailable()
        }
        if pageLocation.isEmpty {
            useSavedLocationForToday()
        }
        applyPageLocationToDraft()
        await refreshWeather()
    }

    private func useCurrentLocationIfAvailable() async {
        guard locationProvider.isAuthorized else { return }
        guard let location = await locationProvider.currentLocation() else { return }
        pageLocation = await locationProvider.placeName(for: location)
        pageLatitude = location.coordinate.latitude
        pageLongitude = location.coordinate.longitude
    }

    private func useSavedLocationForToday() {
        if let experience = todayExperiences.first(where: { $0.hasLocation }) {
            pageLocation = experience.location
            pageLatitude = experience.latitude
            pageLongitude = experience.longitude
            return
        }
        if let event = todayEvents.first(where: { !$0.location.isEmpty }) {
            pageLocation = event.location
            pageLatitude = event.latitude
            pageLongitude = event.longitude
        }
    }

    private func refreshWeather() async {
        guard let pageLatitude, let pageLongitude else { return }
        loadingWeather = true
        defer { loadingWeather = false }
        weatherSummary = await weatherService.forecast(
            latitude: pageLatitude,
            longitude: pageLongitude,
            date: .now
        )
    }

    private func applyPageLocationToDraft() {
        viewModel.location = pageLocation
        viewModel.latitude = pageLatitude
        viewModel.longitude = pageLongitude
        if Calendar.current.isDateInToday(viewModel.occurredAt) {
            viewModel.occurredAt = .now
        }
    }

    private func toggleMic() async {
        editorFocused = false
        if viewModel.speech.isRecording {
            viewModel.speech.stopRecording()
            viewModel.typedText = viewModel.speech.transcript
        } else if await viewModel.speech.requestAuthorization() {
            try? await viewModel.speech.startRecording()
        }
    }

    private func saveExtractedEntry() {
        let assignments = viewModel.peopleAssignments
        if let experience = viewModel.finalizeEntry() {
            modelContext.insert(experience)
            PersonResolver.linkPeople(to: experience, assignments: assignments, in: modelContext)
            EmbeddingService.embed(experience)
            Task { await HealthService.shared.enrich(experience) }
            Task { await refreshReminderNotifications(for: experience) }
        }
        peopleConfirmed = false
    }

    private func saveRawEntry() {
        let experience = viewModel.finalizeRawEntry()
        modelContext.insert(experience)
        EmbeddingService.embed(experience)
        Task { await HealthService.shared.enrich(experience) }
        peopleConfirmed = false
    }

    private func refreshReminderNotifications(for experience: Experience) async {
        let peopleWithReminders = Set(experience.reminders.compactMap(\.person?.id))
        for person in experience.linkedPeople where peopleWithReminders.contains(person.id) {
            await EventReminderNotificationService.rescheduleAll(for: person, events: events)
        }
    }

    enum AddSheet: String, Identifiable {
        case experience, event, conversation
        var id: String { rawValue }
    }
}

private struct TodayCaptureReviewSheet: View {
    @Bindable var viewModel: CaptureViewModel
    @Binding var peopleConfirmed: Bool
    let peopleToConfirm: [String]
    let onSave: () -> Void
    let onSaveRaw: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.phase {
                case .preview:
                    if !peopleConfirmed && !peopleToConfirm.isEmpty {
                        PeopleConfirmView(mentions: peopleToConfirm, assignments: $viewModel.peopleAssignments) {
                            peopleConfirmed = true
                        }
                    } else {
                        ExperiencePreviewView(viewModel: viewModel) {
                            onSave()
                            dismiss()
                        }
                    }
                case .nothingFound:
                    ContentUnavailableView {
                        Label("Nothing to Save", systemImage: "questionmark.bubble")
                    } description: {
                        Text("This note doesn't seem to describe an experience.")
                    } actions: {
                        Button("Edit Note") {
                            viewModel.phase = .input
                            dismiss()
                        }
                        Button("Discard", role: .destructive) {
                            viewModel.discard()
                            dismiss()
                        }
                    }
                case .error(let message):
                    ContentUnavailableView {
                        Label("Something Went Wrong", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        if viewModel.canSaveRaw {
                            Button("Save Entry Anyway") {
                                onSaveRaw()
                                dismiss()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        Button("Try Again") { Task { await viewModel.submit() } }
                        Button("Back") {
                            viewModel.phase = .input
                            dismiss()
                        }
                    }
                case .input, .extracting:
                    ProgressView("Understanding your note...")
                }
            }
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        viewModel.phase = .input
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct ExperienceMemoryCard: View {
    let experience: Experience
    let people: [Person]

    private var text: String {
        let raw = experience.rawText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? experience.summary : raw
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: experience.tone.symbol)
                    .foregroundStyle(experience.tone.tint)
                Text(experience.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(experience.timelineDate, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(text)
                .font(.custom("Caveat-Regular", size: 24))
                .lineSpacing(4)
                .foregroundStyle(Color(red: 0.20, green: 0.16, blue: 0.12))
                .lineLimit(4)

            if !experience.linkedPeople.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(experience.linkedPeople) { person in
                            NavigationLink {
                                PersonDetailView(person: person)
                            } label: {
                                Label(person.displayName(among: people), systemImage: "person.crop.circle")
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(.thinMaterial, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct EventMemoryCard: View {
    let event: Event

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(event.date.formatted(.dateTime.hour().minute()))
                    .font(.headline)
                Text(event.date.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 64)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.headline)
                    .lineLimit(1)
                if !event.location.isEmpty {
                    Label(event.location, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !event.notes.isEmpty {
                    Text(event.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}
