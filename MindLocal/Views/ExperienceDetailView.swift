import SwiftUI
import SwiftData

struct ExperienceDetailView: View {
    @Bindable var experience: Experience
    let extraction: ExtractionServicing
    @Query private var events: [Event]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var pickingLocation = false
    @State private var isReExtracting = false
    @State private var extractionError: String?
    @State private var edits = Edits()
    @State private var editsLoaded = false
    @State private var confirmingDiscard = false

    /// The fields this screen edits, held apart from the model.
    ///
    /// SwiftData autosaves, so a binding straight to `experience` commits every
    /// keystroke and leaves nothing to discard. Editing a copy is what makes
    /// Cancel mean anything. The actions below this — re-running extraction,
    /// the location picker, the reminder checkboxes — still commit immediately:
    /// each is a deliberate act with effects outside this entry, and offering to
    /// undo them here would be a promise this screen cannot keep.
    private struct Edits: Equatable {
        var title = ""
        var summary = ""
        var feelings = ""
        var factors = ""
        var response = ""
        var learning = ""
        var toneRaw = ""
        var kindRaw = ""
        var domainRaw = ""
        var occurredAt = Date.now
        var rawText = ""

        init() {}

        init(_ e: Experience) {
            title = e.title
            summary = e.summary
            feelings = e.feelings
            factors = e.factors
            response = e.response
            learning = e.learning
            toneRaw = e.toneRaw
            kindRaw = e.kindRaw
            domainRaw = e.domainRaw
            occurredAt = e.occurredAt ?? e.createdAt
            rawText = e.rawText ?? ""
        }

        func apply(to e: Experience) {
            e.title = title
            e.summary = summary
            e.feelings = feelings
            e.factors = factors
            e.response = response
            e.learning = learning
            e.toneRaw = toneRaw
            e.kindRaw = kindRaw
            e.domainRaw = domainRaw
            e.occurredAt = occurredAt
            e.rawText = rawText
        }
    }

    /// Nothing to save until the draft has been filled from the entry, or the
    /// empty initial draft reads as a screenful of deletions.
    private var isDirty: Bool { editsLoaded && edits != Edits(experience) }

    private var editsTone: ExperienceTone { ExperienceTone(rawValue: edits.toneRaw) ?? .mixed }

    init(experience: Experience, extraction: ExtractionServicing = ExtractionService()) {
        self.experience = experience
        self.extraction = extraction
    }

    var body: some View {
        Form {
            Section("Experience") {
                TextField("Title", text: $edits.title)
                TextField("What happened", text: $edits.summary, axis: .vertical)
                WordingEnhancer(text: $edits.summary)
            }
            Section("How it felt") {
                Picker("Tone", selection: $edits.toneRaw) {
                    ForEach(ExperienceTone.allCases) { tone in
                        Label(tone.label, systemImage: tone.symbol).tag(tone.rawValue)
                    }
                }
                TextField("Feelings", text: $edits.feelings, axis: .vertical)
                TextField("What made it that way", text: $edits.factors, axis: .vertical)
            }
            Section(editsTone == .pleasant ? "To repeat" : "To handle better") {
                TextField("What you did", text: $edits.response, axis: .vertical)
                TextField("Takeaway", text: $edits.learning, axis: .vertical)
            }
            if hasJournalDetails {
                Section("Details") {
                    detailRow("People", experience.people, systemImage: "person.2")
                    detailRow("Activities", experience.activities, systemImage: "figure.walk")
                    detailRow("Outcomes", experience.outcomes, systemImage: "arrow.right.circle")
                    detailRow("Hopes & wants", experience.hopes, systemImage: "sparkles")
                }
            }
            if !experience.decisions.isEmpty {
                Section("Decisions") {
                    ForEach(experience.decisions) { decision in
                        NavigationLink { DecisionDetailView(decision: decision) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(decision.title).font(.subheadline)
                                if !decision.statement.isEmpty {
                                    Text(decision.statement).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                        }
                    }
                }
            }
            if !experience.reminders.isEmpty {
                Section("Reminders") {
                    ForEach(experience.reminders) { reminder in
                        Button {
                            reminder.isDone ? reminder.markNotDone() : reminder.markDone()
                            if let person = reminder.person {
                                Task { await EventReminderNotificationService.rescheduleAll(for: person, events: events) }
                            }
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: reminder.isDone ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(reminder.isDone ? Color.accentColor : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(reminder.text)
                                        .strikethrough(reminder.isDone)
                                        .foregroundStyle(reminder.isDone ? .secondary : .primary)
                                    let withName = reminder.person?.fullDisplayName ?? reminder.personName
                                    if !withName.isEmpty {
                                        Text("with \(withName)").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !experience.conflicts.isEmpty {
                Section("Conflicts") {
                    ForEach(experience.conflicts) { conflict in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Label(conflictName(conflict),
                                      systemImage: "person.crop.circle.badge.exclamationmark")
                                    .font(.subheadline)
                                Spacer()
                                Label(conflict.resolution.label, systemImage: conflict.resolution.symbol)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .labelStyle(.titleAndIcon)
                            }
                            if !conflict.summary.isEmpty {
                                Text(conflict.summary).font(.callout)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if !conflict.feelings.isEmpty {
                                Text(conflict.feelings).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            Section("Classification") {
                Picker("Kind", selection: $edits.kindRaw) {
                    ForEach(ExperienceKind.allCases) { kind in
                        Label(kind.label, systemImage: kind.symbol).tag(kind.rawValue)
                    }
                }
                DatePicker("When it happened", selection: $edits.occurredAt)
                Picker("Domain", selection: $edits.domainRaw) {
                    ForEach(Domain.allCases) { Text($0.label).tag($0.rawValue) }
                }
            }
            Section("Location") {
                Button {
                    pickingLocation = true
                } label: {
                    Label(experience.location.isEmpty ? "Add location" : experience.location,
                          systemImage: "mappin.circle")
                        .foregroundStyle(experience.location.isEmpty ? Color.accentColor : .primary)
                }
                if let lat = experience.latitude, let lon = experience.longitude {
                    LocationMapPreview(latitude: lat, longitude: lon, name: experience.location)
                        .listRowInsets(EdgeInsets())
                    Button("Remove location", role: .destructive) {
                        experience.location = ""
                        experience.latitude = nil
                        experience.longitude = nil
                        MemoryGraphStore.rebuildAndPersist(in: modelContext)
                    }
                }
            }

            Section {
                TextEditor(text: $edits.rawText)
                    .font(.callout)
                    .frame(minHeight: 120)
                Button {
                    Task { await rerunExtraction() }
                } label: {
                    if isReExtracting {
                        HStack {
                            ProgressView()
                            Text("Re-running extraction…")
                        }
                    } else {
                        Label("Re-run AI Extraction", systemImage: "sparkles")
                    }
                }
                .disabled(isReExtracting || edits.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let extractionError {
                    Text(extractionError).font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("Original note")
            } footer: {
                Text("Fix a typo here, then re-run extraction to refresh the fields above from the corrected note. This replaces the previously extracted details, decisions, conflicts, and reminders.")
            }
        }
        .albumScreen()
        .navigationTitle(edits.title)
        .navigationBarTitleDisplayMode(.inline)
        // The back button would leave silently with the edits dropped, which is
        // the same trap as committing them silently. Both ways out are named.
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    if isDirty { confirmingDiscard = true } else { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save).disabled(!isDirty)
            }
        }
        .confirmationDialog("Discard your changes?", isPresented: $confirmingDiscard,
                            titleVisibility: .visible) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) { }
        }
        .task {
            guard !editsLoaded else { return }
            edits = Edits(experience)
            editsLoaded = true
        }
        .sheet(isPresented: $pickingLocation) {
            LocationPickerView { name, lat, lon in
                experience.location = name
                experience.latitude = lat
                experience.longitude = lon
                MemoryGraphStore.rebuildAndPersist(in: modelContext)
            }
        }
    }

    /// Writes the edits onto the entry and leaves.
    ///
    /// The embedding and the memory graph are built from this text, so an edit
    /// that only reached the row would leave the Ask tab answering from the old
    /// wording. Re-embedding is skipped when the prose did not change: a
    /// corrected date or domain moves nothing the embedding reads.
    private func save() {
        let textChanged = edits.summary != experience.summary
            || edits.title != experience.title
            || edits.rawText != (experience.rawText ?? "")
        edits.apply(to: experience)
        if textChanged { EmbeddingService.embed(experience) }
        MemoryGraphStore.rebuildAndPersist(in: modelContext)
        dismiss()
    }

    /// Who a conflict was with: the linked person's name, else the raw text, else
    /// a neutral fallback.
    private func conflictName(_ conflict: Conflict) -> String {
        if let name = conflict.withPerson?.fullDisplayName, !name.isEmpty { return name }
        return conflict.personName.isEmpty ? "Someone" : conflict.personName
    }

    /// Re-extracts from the (possibly just-edited) original note and overwrites
    /// the experience's AI-generated fields in place — the fix for a typo in the
    /// note otherwise never reaching the extracted summary/decisions/etc.
    private func rerunExtraction() async {
        let transcript = edits.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return }
        isReExtracting = true
        extractionError = nil
        defer { isReExtracting = false }
        do {
            // Nothing is committed until extraction has actually produced
            // something. It reads `transcript`, not the entry, so a failure
            // here leaves the entry untouched and Cancel still means discard.
            let draft = try await extraction.extractExperience(from: transcript)
            guard draft.isExperience else {
                extractionError = "The note no longer describes an experience — nothing to extract."
                return
            }
            // Order matters. The edits go on first because they carry the
            // corrected note, the date and the kind, which extraction does not
            // write; then extraction's own fields land over the wording it owns.
            edits.apply(to: experience)
            draft.apply(to: experience, in: modelContext)
            PersonResolver.linkPeople(
                to: experience, personOccupations: draft.personOccupations,
                personPreferences: draft.personPreferences, in: modelContext
            )
            EmbeddingService.embed(experience)
            MemoryGraphStore.rebuildAndPersist(in: modelContext)
            // Show what extraction produced, not what was on screen before it.
            edits = Edits(experience)
        } catch {
            extractionError = CaptureViewModel.friendlyMessage(for: error)
        }
    }

    private var hasJournalDetails: Bool {
        !(experience.people.isEmpty && experience.activities.isEmpty
          && experience.outcomes.isEmpty && experience.hopes.isEmpty)
    }

    @ViewBuilder
    private func detailRow(_ title: String, _ items: [String], systemImage: String) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(items.joined(separator: " · "))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 2)
        }
    }
}
