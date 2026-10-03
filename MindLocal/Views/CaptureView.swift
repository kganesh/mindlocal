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
            .albumScreen()
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
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                AlbumHeading(title: "A moment to keep.", subtitle: "Write a little, or say it out loud.")
                DatePicker("Date & time", selection: $viewModel.occurredAt, displayedComponents: [.date, .hourAndMinute])
                    .padding(.horizontal, 4)

                // The same quiet line Today uses: caption weight, secondary
                // ink, no tint and no chrome. It is context for the entry, not
                // an action competing with the writing below it.
                //
                // No clear button. Opening the picker is how a wrong location
                // gets corrected, and a destructive control does not need to
                // sit on a line this quiet.
                Button {
                    pickingLocation = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.and.ellipse")
                        Text(viewModel.location.isEmpty ? "Add location" : viewModel.location)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.caption)
                    .foregroundStyle(AlbumTheme.secondary)
                    .frame(minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(viewModel.location.isEmpty
                                    ? "Add location"
                                    : "Location: \(viewModel.location)")
                .padding(.horizontal, 4)

                // The same card as Today: the text and the two things you do
                // with it in one place, rather than the controls sitting in
                // their own rows underneath the box that holds the writing.
                VStack(alignment: .leading, spacing: 12) {
                    TextEditor(text: $viewModel.typedText)
                        .frame(minHeight: 200)
                        .font(.body)
                        .lineSpacing(6)
                        .scrollContentBackground(.hidden)
                        .foregroundStyle(AlbumTheme.ink)
                        .accessibilityLabel("Journal entry")
                        .focused($editorFocused)
                        .overlay(alignment: .topLeading) {
                            if viewModel.typedText.isEmpty && !viewModel.speech.isRecording {
                                Text("What would you like to remember?")
                                    .foregroundStyle(AlbumTheme.secondary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
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
                            if viewModel.speech.isTranscribing { viewModel.applyTranscript(newValue) }
                        }

                    // Clear sits at the far end, away from mic and send. It is
                    // the one destructive control here and it should not be a
                    // thumb's width from the one tapped most often.
                    HStack(alignment: .bottom, spacing: 12) {
                        if !viewModel.typedText.isEmpty { clearButton }
                        countLine
                        Spacer(minLength: 8)
                        // One or the other, never both. The mic stays while
                        // recording, because it is also the stop button.
                        if viewModel.typedText.isEmpty || viewModel.speech.isRecording {
                            micButton
                        } else {
                            reviewButton
                        }
                    }
                }
                .padding(20)
                .background(AlbumTheme.surface, in: RoundedRectangle(cornerRadius: 20))
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(AlbumTheme.rule, lineWidth: 1)
                }
                .animation(.snappy(duration: 0.15), value: viewModel.typedText.isEmpty)
                .animation(.snappy(duration: 0.15), value: viewModel.speech.isRecording)

                if wordCount > wordLimit {
                    Text("Keep it under \(wordLimit) words — trim a little to continue.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
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

    /// Shown only as the limit comes into view. It occupies the space Today
    /// gives its hint line, which is empty here the rest of the time.
    @ViewBuilder
    private var countLine: some View {
        if wordCount >= wordLimit - 50 {
            Text("\(wordCount) of \(wordLimit) words")
                .font(.caption)
                .foregroundStyle(wordCount > wordLimit ? .red : AlbumTheme.secondary)
        }
    }

    /// Start over. Clears the saved draft too, via `discard()` — a half-written
    /// entry that comes back on the next launch is not what "clear" means.
    private var clearButton: some View {
        Button {
            Task {
                // Stop dictation first. The transcript observer would otherwise
                // put the tail back into the field a moment after it is
                // emptied, and the field would refill on its own.
                await viewModel.speech.finishRecording()
                viewModel.discard()
                editorFocused = true
            }
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 20))
                .frame(width: 38, height: 38)
        }
        .buttonStyle(.plain)
        .foregroundStyle(AlbumTheme.Field.accessory)
        .accessibilityLabel("Clear entry")
        .transition(.opacity)
    }

    private var micButton: some View {
        Button {
            editorFocused = false
            if viewModel.speech.isRecording {
                // Stop and let go. Copying the transcript here reads it a
                // second before the tail of the speech lands, and the observer
                // above already keeps this field current through the tail.
                viewModel.speech.stopRecording()
            } else {
                Task {
                    if await viewModel.speech.requestAuthorization() {
                        viewModel.beginDictation()
                        try? await viewModel.speech.startRecording()
                    }
                }
            }
        } label: {
            Image(systemName: viewModel.speech.isRecording ? "stop.fill" : "mic")
                .font(.system(size: 19, weight: .semibold))
                .frame(width: 38, height: 38)
        }
        .buttonStyle(.plain)
        .foregroundStyle(viewModel.speech.isRecording ? .red : AlbumTheme.secondary)
        .accessibilityLabel(viewModel.speech.isRecording ? "Stop recording" : "Start recording")
    }

    /// Submit. No label, so "Review entry" survives as the accessibility name
    /// and the disabled capsule is what says there is nothing to send yet.
    private var reviewButton: some View {
        Button {
            editorFocused = false
            Task { await viewModel.submit() }
        } label: {
            Group {
                if viewModel.phase == .extracting {
                    ProgressView().tint(AlbumTheme.onAccent)
                } else {
                    Image(systemName: "arrow.up").font(.body.weight(.semibold))
                }
            }
            .frame(width: 54, height: 38)
            .foregroundStyle(canSubmit ? AlbumTheme.onAccent : AlbumTheme.Button.disabledLabel)
            .background(canSubmit ? AlbumTheme.accent : AlbumTheme.Button.disabledFill, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
        .accessibilityLabel(viewModel.phase == .extracting ? "Preparing…" : "Review entry")
    }

    private var canSubmit: Bool {
        !isInputEmpty && wordCount <= wordLimit && viewModel.phase != .extracting
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
        let personPreferences = viewModel.experienceDraft?.personPreferences ?? []
        if let experience = viewModel.finalizeEntry() {
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
