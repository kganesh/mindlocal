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
    @State private var showingSettings = false
    @State private var peopleConfirmed = false
    @FocusState private var editorFocused: Bool

    private var todayEntries: [Experience] {
        experiences
            .filter { Calendar.current.isDateInToday($0.timelineDate) }
            .sorted { $0.timelineDate > $1.timelineDate }
    }

    private var todayDailyLogs: [Experience] {
        todayEntries.filter { $0.kind == .dailyLog }
    }

    private var todayExperiences: [Experience] {
        todayEntries.filter { $0.kind == .experience }
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
                VStack(spacing: 28) {
                    header
                    diaryPage
                    todayMemoryStack
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
            .albumScreen()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("MindLocal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingTimeline = true } label: {
                        Image(systemName: "calendar")
                    }
                    .accessibilityLabel("Timeline")
                }
            }
            .sheet(item: $addSheet) { sheet in
                switch sheet {
                case .experience:
                    CaptureView()
                case .event:
                    EventFormView {
                        modelContext.insert($0)
                        MemoryGraphStore.rebuildAndPersist(in: modelContext)
                    }
                case .conversation:
                    JournalConversationView()
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
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
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    AlbumIconTile(symbol: "square.and.pencil")
                    Text("YOUR WORDS")
                        .font(.caption.weight(.medium))
                        .tracking(1.6)
                        .foregroundStyle(AlbumTheme.secondary)
                }

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $viewModel.typedText)
                        .font(.body)
                        .lineSpacing(7)
                        .foregroundStyle(AlbumTheme.ink)
                        .frame(minHeight: 200)
                        .scrollContentBackground(.hidden)
                        .focused($editorFocused)
                        .accessibilityLabel("Today's journal entry")
                        .onChange(of: viewModel.speech.transcript) { _, newValue in
                            if viewModel.speech.isRecording { viewModel.typedText = newValue }
                        }
                    if viewModel.typedText.isEmpty && !viewModel.speech.isRecording {
                        Text("What would you like to remember?")
                            .font(.body)
                            .foregroundStyle(AlbumTheme.secondary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }

                if viewModel.speech.isRecording {
                    Label("Listening — take your time", systemImage: "waveform")
                        .font(.caption)
                        .foregroundStyle(AlbumTheme.accent)
                } else {
                    Text("A little is enough. Start wherever you are.")
                        .font(.caption)
                        .foregroundStyle(AlbumTheme.secondary)
                }
            }
            .padding(20)
            .background(AlbumTheme.surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(AlbumTheme.rule, lineWidth: 1)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    reviewButton
                    voiceButton
                }
                VStack(alignment: .leading, spacing: 12) {
                    reviewButton
                    voiceButton
                }
            }

            Label("Private on your device", systemImage: "lock")
                .font(.caption)
                .foregroundStyle(AlbumTheme.secondary)
                .frame(maxWidth: .infinity)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { editorFocused = false }
            }
        }
    }

    private var reviewButton: some View {
        Button {
            editorFocused = false
            applyPageLocationToDraft()
            Task { await viewModel.submit() }
        } label: {
            HStack(spacing: 8) {
                if viewModel.phase == .extracting { ProgressView().tint(AlbumTheme.secondary) }
                Text(saveButtonTitle)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(AlbumPrimaryButtonStyle())
        .disabled(!canSubmit)
    }

    private var voiceButton: some View {
        Button {
            Task { await toggleMic() }
        } label: {
            Label(viewModel.speech.isRecording ? "Stop" : "Speak",
                  systemImage: viewModel.speech.isRecording ? "stop.fill" : "mic")
                .font(.body)
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
                .background(AlbumTheme.wash, in: Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(viewModel.speech.isRecording ? .red : AlbumTheme.accent)
        .accessibilityLabel(viewModel.speech.isRecording ? "Stop dictation" : "Dictate journal entry")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                AlbumHeading(
                    eyebrow: Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()),
                    title: "The little things.",
                    subtitle: "A moment for yourself, in your own words."
                )
                addMenu
            }
            Button {
                pickingLocation = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: weatherSymbol)
                    Text(contextLine)
                        .fixedSize(horizontal: false, vertical: true)
                    if loadingWeather { ProgressView().controlSize(.mini) }
                }
                .font(.caption)
                .foregroundStyle(AlbumTheme.secondary)
                .frame(minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Location and weather: \(contextLine)")
        }
    }

    private var addMenu: some View {
        Menu {
            Button { addSheet = .experience } label: {
                Label("Experience Entry", systemImage: "square.and.pencil")
            }
            Button { addSheet = .event } label: {
                Label("Event", systemImage: "calendar.badge.plus")
            }
            Button { showingAsk = true } label: {
                Label("Ask about your memories", systemImage: "bubble.left")
            }
            Button { addSheet = .conversation } label: {
                Label("Voice Check-In", systemImage: "moon.stars")
            }
        } label: {
            Image(systemName: "plus")
        }
        .modifier(PageIconButtonStyle(tint: AlbumTheme.accent))
        .accessibilityLabel("Add")
    }

    private var todayMemoryStack: some View {
        VStack(alignment: .leading, spacing: 12) {
            if todayEntries.isEmpty && todayEvents.isEmpty {
                EmptyTodayIndex()
            } else {
                HStack {
                    Text("Today’s moments")
                        .font(AlbumTheme.heading(.title2))
                    Spacer()
                    Text("\(todayEntries.count + todayEvents.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AlbumTheme.wash, in: Capsule())
                }
                .padding(.horizontal, 4)

                if !todayDailyLogs.isEmpty {
                    memorySection("Daily Log", systemImage: ExperienceKind.dailyLog.symbol, count: todayDailyLogs.count) {
                        ForEach(todayDailyLogs) { experience in
                            NavigationLink {
                                DiaryPageView(experience: experience)
                            } label: {
                                ExperienceMemoryCard(experience: experience, people: people)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !todayExperiences.isEmpty {
                    memorySection("Experiences", systemImage: ExperienceKind.experience.symbol, count: todayExperiences.count) {
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

    private var weatherSymbol: String {
        guard let weatherSummary else { return "mappin.and.ellipse" }
        let condition = weatherSummary.condition.lowercased()
        if condition.contains("rain") || condition.contains("drizzle") { return "cloud.rain" }
        if condition.contains("snow") { return "snowflake" }
        if condition.contains("cloud") { return "cloud" }
        if condition.contains("sun") || condition.contains("clear") { return "sun.max" }
        if condition.contains("wind") { return "wind" }
        return "cloud.sun"
    }

    private var canSubmit: Bool {
        !viewModel.typedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && viewModel.phase != .extracting
    }

    private var saveButtonTitle: String {
        viewModel.phase == .extracting ? "Preparing…" : "Review entry"
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
        if let experience = todayEntries.first(where: { $0.hasLocation }) {
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
        let personOccupations = viewModel.experienceDraft?.personOccupations ?? []
        let personPreferences = viewModel.experienceDraft?.personPreferences ?? []
        if let experience = viewModel.finalizeEntry() {
            experience.kind = .dailyLog
            modelContext.insert(experience)
            PersonResolver.linkPeople(
                to: experience, assignments: assignments, personOccupations: personOccupations,
                personPreferences: personPreferences, in: modelContext
            )
            EmbeddingService.embed(experience)
            MemoryGraphStore.rebuildAndPersist(in: modelContext)
            Task { await HealthService.shared.enrich(experience) }
            Task { await refreshReminderNotifications(for: experience) }
        }
        peopleConfirmed = false
    }

    private func saveRawEntry() {
        let experience = viewModel.finalizeRawEntry()
        experience.kind = .dailyLog
        modelContext.insert(experience)
        EmbeddingService.embed(experience)
        MemoryGraphStore.rebuildAndPersist(in: modelContext)
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
            .albumScreen()
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

private struct PageIconButtonStyle: ViewModifier {
    var tint: Color

    func body(content: Content) -> some View {
        content
            .font(.body.weight(.medium))
            .foregroundStyle(tint)
            .frame(width: 44, height: 44)
            .background(AlbumTheme.wash, in: Circle())
    }
}

private struct EmptyTodayIndex: View {
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            AlbumIconTile(symbol: "bookmark", tint: AlbumTheme.dateAccent)
            Text("Your moments will collect here, one entry at a time.")
                .font(.callout)
                .foregroundStyle(AlbumTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Outlined rather than filled: a filled box beside the real text field
        // reads as a second input. This is a note, not a control.
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AlbumTheme.rule, lineWidth: 1)
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
                    .font(AlbumTheme.heading(.title3))
                    .lineLimit(1)
                Spacer()
                Text(experience.timelineDate, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(text)
                .font(.body)
                .lineSpacing(4)
                .foregroundStyle(AlbumTheme.ink)
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
                                    .background(AlbumTheme.wash, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AlbumTheme.surface, in: RoundedRectangle(cornerRadius: 16))
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
        .background(AlbumTheme.surface, in: RoundedRectangle(cornerRadius: 16))
    }
}
