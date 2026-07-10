import SwiftUI
import SwiftData

/// Editable structured preview of an extracted experience before save.
struct ExperiencePreviewView: View {
    @Bindable var viewModel: CaptureViewModel
    let onSave: () -> Void

    @Query(sort: \Person.name) private var people: [Person]
    @State private var namingRole: String?
    @State private var newName: String = ""

    /// Role/title mentions ("principal engineer", "my manager") that should be
    /// tied to a specific person.
    private var roleReferences: [String] {
        (viewModel.experienceDraft?.people ?? []).filter { PersonResolver.isRoleReference($0) }
    }

    var body: some View {
        if viewModel.experienceDraft != nil {
            Form {
                Section("Experience") {
                    TextField("Title", text: binding(\.title))
                    TextField("What happened", text: binding(\.summary), axis: .vertical)
                    WordingEnhancer(text: binding(\.summary))
                }
                Section("How it felt") {
                    Picker("Tone", selection: binding(\.tone)) {
                        ForEach(ExperienceTone.allCases) { tone in
                            Label(tone.label, systemImage: tone.symbol).tag(tone.rawValue)
                        }
                    }
                    TextField("Feelings", text: binding(\.feelings), axis: .vertical)
                    TextField("What made it that way", text: binding(\.factors), axis: .vertical)
                }
                Section("Response & Takeaway") {
                    TextField("What you did", text: binding(\.response), axis: .vertical)
                    TextField(toneIsPleasant ? "What to do again" : "What would help next time",
                              text: binding(\.learning), axis: .vertical)
                }
                if let decisions = viewModel.experienceDraft?.decisions, !decisions.isEmpty {
                    Section {
                        ForEach(decisions.indices, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 6) {
                                TextField("What you decided", text: decisionBinding(index, \.statement), axis: .vertical)
                                TextField("Why", text: decisionBinding(index, \.rationale), axis: .vertical)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                        .onDelete { viewModel.experienceDraft?.decisions.remove(atOffsets: $0) }
                    } header: {
                        Label("Decisions detected", systemImage: "checklist")
                    } footer: {
                        Text("Extracted from what you said. Edit, or swipe to remove any that aren't right.")
                    }
                }
                if let draft = viewModel.experienceDraft, draftHasDetails(draft) {
                    Section {
                        detectedRow("People", draft.people, systemImage: "person.2")
                        detectedRow("Activities", draft.activities, systemImage: "figure.walk")
                        detectedRow("Outcomes", draft.outcomes, systemImage: "arrow.right.circle")
                        detectedRow("Hopes & wants", draft.hopes, systemImage: "sparkles")
                    } header: {
                        Label("Detected", systemImage: "sparkles")
                    } footer: {
                        Text("Extracted from your entry.")
                    }
                }
                if !roleReferences.isEmpty {
                    Section {
                        ForEach(roleReferences, id: \.self) { role in
                            HStack {
                                Text(role)
                                Spacer()
                                Menu {
                                    ForEach(people) { person in
                                        Button(person.name) { viewModel.peopleAssignments[role] = person.name }
                                    }
                                    Button("New person…") { newName = ""; namingRole = role }
                                    if viewModel.peopleAssignments[role] != nil {
                                        Button("Clear", role: .destructive) { viewModel.peopleAssignments[role] = nil }
                                    }
                                } label: {
                                    Text(assignmentLabel(for: role))
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    } header: {
                        Label("Who's who?", systemImage: "person.fill.questionmark")
                    } footer: {
                        Text("You mentioned a role — tie it to a person, or leave it unidentified.")
                    }
                }
                Section("When") {
                    DatePicker("When it happened", selection: $viewModel.occurredAt)
                }
                Section("Classification") {
                    Picker("Domain", selection: binding(\.domain)) {
                        ForEach(Domain.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                }
                Section {
                    Button("Save Experience") { onSave() }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.borderedProminent)
                    Button("Discard", role: .destructive) { viewModel.discard() }
                        .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Review")
            .alert("Who is this?", isPresented: Binding(get: { namingRole != nil }, set: { if !$0 { namingRole = nil } })) {
                TextField("Name", text: $newName)
                Button("Add") {
                    if let role = namingRole, !newName.trimmingCharacters(in: .whitespaces).isEmpty {
                        viewModel.peopleAssignments[role] = newName
                    }
                    namingRole = nil
                }
                Button("Cancel", role: .cancel) { namingRole = nil }
            } message: {
                Text("Enter a name for “\(namingRole ?? "")”.")
            }
        }
    }

    private func assignmentLabel(for role: String) -> String {
        guard let name = viewModel.peopleAssignments[role] else { return "Identify" }
        return name.isEmpty ? "Identify" : name
    }

    private var toneIsPleasant: Bool {
        (viewModel.experienceDraft?.tone.lowercased() ?? "") == ExperienceTone.pleasant.rawValue
    }

    private func draftHasDetails(_ draft: ExperienceDraft) -> Bool {
        !(draft.people.isEmpty && draft.activities.isEmpty
          && draft.outcomes.isEmpty && draft.hopes.isEmpty)
    }

    @ViewBuilder
    private func detectedRow(_ title: String, _ items: [String], systemImage: String) -> some View {
        let cleaned = items.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if !cleaned.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(cleaned.joined(separator: " · "))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 2)
        }
    }

    private func binding(_ keyPath: WritableKeyPath<ExperienceDraft, String>) -> Binding<String> {
        Binding(
            get: { viewModel.experienceDraft?[keyPath: keyPath] ?? "" },
            set: { viewModel.experienceDraft?[keyPath: keyPath] = $0 }
        )
    }

    private func decisionBinding(_ index: Int, _ keyPath: WritableKeyPath<DecisionDraft, String>) -> Binding<String> {
        Binding(
            get: {
                guard let decisions = viewModel.experienceDraft?.decisions,
                      decisions.indices.contains(index) else { return "" }
                return decisions[index][keyPath: keyPath]
            },
            set: {
                guard viewModel.experienceDraft?.decisions.indices.contains(index) == true else { return }
                viewModel.experienceDraft?.decisions[index][keyPath: keyPath] = $0
            }
        )
    }
}
