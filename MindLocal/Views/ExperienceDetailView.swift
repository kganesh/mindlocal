import SwiftUI
import SwiftData

struct ExperienceDetailView: View {
    @Bindable var experience: Experience
    let extraction: ExtractionServicing
    @Query private var events: [Event]
    @Environment(\.modelContext) private var modelContext
    @State private var pickingLocation = false
    @State private var isReExtracting = false
    @State private var extractionError: String?

    init(experience: Experience, extraction: ExtractionServicing = ExtractionService()) {
        self.experience = experience
        self.extraction = extraction
    }

    var body: some View {
        Form {
            Section("Experience") {
                TextField("Title", text: $experience.title)
                TextField("What happened", text: $experience.summary, axis: .vertical)
                WordingEnhancer(text: $experience.summary)
            }
            Section("How it felt") {
                Picker("Tone", selection: $experience.toneRaw) {
                    ForEach(ExperienceTone.allCases) { tone in
                        Label(tone.label, systemImage: tone.symbol).tag(tone.rawValue)
                    }
                }
                TextField("Feelings", text: $experience.feelings, axis: .vertical)
                TextField("What made it that way", text: $experience.factors, axis: .vertical)
            }
            Section(experience.tone == .pleasant ? "To repeat" : "To handle better") {
                TextField("What you did", text: $experience.response, axis: .vertical)
                TextField("Takeaway", text: $experience.learning, axis: .vertical)
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
                DatePicker(
                    "When it happened",
                    selection: Binding(
                        get: { experience.occurredAt ?? experience.createdAt },
                        set: { experience.occurredAt = $0 }
                    )
                )
                Picker("Domain", selection: $experience.domainRaw) {
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
                    }
                }
            }

            Section {
                TextEditor(text: rawTextBinding)
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
                .disabled(isReExtracting || rawTextBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let extractionError {
                    Text(extractionError).font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("Original note")
            } footer: {
                Text("Fix a typo here, then re-run extraction to refresh the fields above from the corrected note. This replaces the previously extracted details, decisions, conflicts, and reminders.")
            }
        }
        .navigationTitle(experience.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $pickingLocation) {
            LocationPickerView { name, lat, lon in
                experience.location = name
                experience.latitude = lat
                experience.longitude = lon
            }
        }
    }

    /// Who a conflict was with: the linked person's name, else the raw text, else
    /// a neutral fallback.
    private func conflictName(_ conflict: Conflict) -> String {
        if let name = conflict.withPerson?.fullDisplayName, !name.isEmpty { return name }
        return conflict.personName.isEmpty ? "Someone" : conflict.personName
    }

    private var rawTextBinding: Binding<String> {
        Binding(
            get: { experience.rawText ?? "" },
            set: { experience.rawText = $0 }
        )
    }

    /// Re-extracts from the (possibly just-edited) original note and overwrites
    /// the experience's AI-generated fields in place — the fix for a typo in the
    /// note otherwise never reaching the extracted summary/decisions/etc.
    private func rerunExtraction() async {
        let transcript = rawTextBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return }
        isReExtracting = true
        extractionError = nil
        defer { isReExtracting = false }
        do {
            let draft = try await extraction.extractExperience(from: transcript)
            guard draft.isExperience else {
                extractionError = "The note no longer describes an experience — nothing to extract."
                return
            }
            draft.apply(to: experience, in: modelContext)
            PersonResolver.linkPeople(to: experience, in: modelContext)
            EmbeddingService.embed(experience)
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
