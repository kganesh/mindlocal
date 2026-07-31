import SwiftUI
import SwiftData

/// Single capture flow: describe what happened (voice or text); the AI extracts
/// the experience plus any decisions mentioned, then an editable review to save.
struct CaptureView: View {
    @State private var viewModel = CaptureViewModel()
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @Query private var people: [Person]
    @Query private var relationships: [PersonRelationship]
    @Query private var events: [Event]
    @State private var peopleConfirmed = false
    @State private var pickingLocation = false
    @State private var locationProvider = CurrentLocationProvider()
    @FocusState private var editorFocused: Bool


    /// Mentions that need a "who is this?" question: role references, bare kinship
    /// terms ("my sister"), and same-name ambiguity. Clear new names, already-known
    /// aliases, and graph-resolved relatives ("mom" with a parent edge) auto-resolve.
    private var peopleToConfirm: [String] {
        guard let draft = viewModel.experienceDraft else { return [] }
        return PersonResolver.mentionsNeedingConfirmation(draft.people, people: people, relationships: relationships)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.phase {
                case .input:
                    inputView
                case .extracting:
                    ProgressView("Understanding your note…")
                case .preview:
                    if viewModel.experienceDraft != nil {
                        if !peopleConfirmed && !peopleToConfirm.isEmpty {
                            PeopleConfirmView(mentions: peopleToConfirm, assignments: $viewModel.peopleAssignments) {
                                peopleConfirmed = true
                            }
                        } else {
                            ExperiencePreviewView(viewModel: viewModel, onSave: save)
                        }
                    }
                case .nothingFound:
                    nothingFoundView
                case .error(let message):
                    errorView(message)
                }
            }
            .navigationTitle("New Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { viewModel.discard(); dismiss() }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { viewModel.persistWorkInProgress() }
            }
            .sheet(isPresented: $pickingLocation) {
                LocationPickerView { name, lat, lon in
                    viewModel.location = name
                    viewModel.latitude = lat
                    viewModel.longitude = lon
                }
            }
        }
    }

    private var inputView: some View {
        VStack(spacing: 24) {
            DatePicker("Date & time", selection: $viewModel.occurredAt, displayedComponents: [.date, .hourAndMinute])
                .padding(.horizontal, 4)

            HStack {
                Button {
                    pickingLocation = true
                } label: {
                    Label(viewModel.location.isEmpty ? "Add location" : viewModel.location,
                          systemImage: "mappin.circle")
                        .lineLimit(1)
                }
                Spacer()
                if !viewModel.location.isEmpty {
                    Button {
                        viewModel.location = ""
                        viewModel.latitude = nil
                        viewModel.longitude = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Clear location")
                }
            }
            .padding(.horizontal, 4)

            TextEditor(text: $viewModel.typedText)
                .frame(minHeight: 140)
                .padding(8)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
                .focused($editorFocused)
                .overlay(alignment: .topLeading) {
                    if viewModel.typedText.isEmpty && !viewModel.speech.isRecording {
                        Text("What happened? Speak or type freely — mention any decisions you made.")
                            .foregroundStyle(.secondary)
                            .padding(16)
                            .allowsHitTesting(false)
                    }
                }
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button {
                            editorFocused = false
                        } label: {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                        }
                        .accessibilityLabel("Done")
                    }
                }
                .onChange(of: viewModel.speech.transcript) { _, newValue in
                    if viewModel.speech.isRecording { viewModel.typedText = newValue }
                }

            HStack {
                Spacer()
                Text("\(wordCount) / \(wordLimit) words")
                    .font(.caption)
                    .foregroundStyle(wordCount > wordLimit ? .red : .secondary)
            }

            micButton

            Button("Continue") {
                Task { await viewModel.submit() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isInputEmpty || wordCount > wordLimit)

            if wordCount > wordLimit {
                Text("Keep it under \(wordLimit) words — trim a little to continue.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .task { await prefillLocationIfAuthorized() }
    }

    /// If the user already shares location, fill the new entry's place from their
    /// current location — silently, and only when they haven't set one. Never
    /// prompts; the manual "Add location" button covers the un-granted case.
    private func prefillLocationIfAuthorized() async {
        guard viewModel.location.isEmpty, locationProvider.isAuthorized else { return }
        guard let location = await locationProvider.currentLocation() else { return }
        guard viewModel.location.isEmpty else { return }   // user picked one meanwhile
        viewModel.location = await locationProvider.placeName(for: location)
        viewModel.latitude = location.coordinate.latitude
        viewModel.longitude = location.coordinate.longitude
    }

    private let wordLimit = 500

    private var wordCount: Int {
        viewModel.typedText.split(whereSeparator: \.isWhitespace).count
    }

    private var isInputEmpty: Bool {
        viewModel.typedText.isEmpty && viewModel.speech.transcript.isEmpty
    }

    private var micButton: some View {
        Button {
            if viewModel.speech.isRecording {
                viewModel.speech.stopRecording()
                viewModel.typedText = viewModel.speech.transcript
            } else {
                Task {
                    if await viewModel.speech.requestAuthorization() {
                        try? await viewModel.speech.startRecording()
                    }
                }
            }
        } label: {
            Image(systemName: viewModel.speech.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(viewModel.speech.isRecording ? .red : .accentColor)
        }
        .accessibilityLabel(viewModel.speech.isRecording ? "Stop recording" : "Start recording")
    }

    private var nothingFoundView: some View {
        ContentUnavailableView {
            Label("Nothing to Save", systemImage: "questionmark.bubble")
        } description: {
            Text("This note doesn't seem to describe an experience.")
        } actions: {
            Button("Edit Note") { viewModel.phase = .input }
            Button("Discard", role: .destructive) { viewModel.discard(); dismiss() }
        }
    }

    private func errorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Something Went Wrong", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            if viewModel.canSaveRaw {
                Button("Save Entry Anyway") { saveRaw() }
                    .buttonStyle(.borderedProminent)
            }
            Button("Try Again") { Task { await viewModel.submit() } }
            Button("Back") { viewModel.phase = .input }
        }
    }

    /// Saves the note as a plain diary entry when AI extraction failed.
    private func saveRaw() {
        let experience = viewModel.finalizeRawEntry()
        modelContext.insert(experience)
        EmbeddingService.embed(experience)
        MemoryGraphStore.rebuildAndPersist(in: modelContext)
        Task { await HealthService.shared.enrich(experience) }
        dismiss()
    }

    private func save() {
        // Capture the confirm-step answers before finalizeEntry() resets them.
        let assignments = viewModel.peopleAssignments
        let personOccupations = viewModel.experienceDraft?.personOccupations ?? []
        if let experience = viewModel.finalizeEntry() {
            modelContext.insert(experience)
            PersonResolver.linkPeople(to: experience, assignments: assignments, personOccupations: personOccupations, in: modelContext)
            EmbeddingService.embed(experience)
            MemoryGraphStore.rebuildAndPersist(in: modelContext)
            Task { await HealthService.shared.enrich(experience) }
            Task { await refreshReminderNotifications(for: experience) }
        }
        dismiss()
    }

    /// New reminders can affect an event already scheduled with that person, so
    /// their notification (if any) needs to reflect the current open list.
    private func refreshReminderNotifications(for experience: Experience) async {
        let peopleWithReminders = Set(experience.reminders.compactMap(\.person?.id))
        for person in experience.linkedPeople where peopleWithReminders.contains(person.id) {
            await EventReminderNotificationService.rescheduleAll(for: person, events: events)
        }
    }
}
