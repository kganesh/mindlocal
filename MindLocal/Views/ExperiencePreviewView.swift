import SwiftUI
import SwiftData

/// Editable structured preview of an extracted experience before save.
struct ExperiencePreviewView: View {
    @Bindable var viewModel: CaptureViewModel
    let onSave: () -> Void
    @Query private var pastDecisions: [Decision]

    var body: some View {
        if viewModel.experienceDraft != nil {
            Form {
                Section("Experience") {
                    TextField("Title", text: binding(\.title))
                    TextField("What happened", text: binding(\.summary), axis: .vertical)
                    WordingEnhancer(text: binding(\.summary))
                }
                Section("How it felt") {
                    Picker("Tone", selection: toneBinding) {
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
                                historyPanel(for: decisions[index])
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
        }
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

    /// "Your history on this" — relevant past decisions (with outcomes) and a
    /// one-line pattern, shown right where you're deciding. Hidden when there's
    /// nothing relevant yet (graceful cold start).
    @ViewBuilder
    private func historyPanel(for draft: DecisionDraft) -> some View {
        let result = DecisionHistoryRetriever.history(
            domain: Domain(rawValue: draft.domain) ?? .other,
            prioritized: draft.valuesPrioritized,
            tradedOff: draft.valuesTradedOff,
            among: pastDecisions
        )
        if !result.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("Your history on this", systemImage: "clock.arrow.circlepath")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(result.matches) { match in
                    HStack(spacing: 8) {
                        Text(match.decision.title)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(match.decision.outcome?.result.label ?? "")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(outcomeTint(match.decision.outcome?.result))
                    }
                }
                if let pattern = result.pattern {
                    Text(pattern)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
            .padding(.top, 4)
        }
    }

    private func outcomeTint(_ result: OutcomeResult?) -> Color {
        switch result {
        case .workedOut: .green
        case .mixed:     .yellow
        case .regret:    .orange
        default:         .secondary
        }
    }

    /// Normalizes the model's tone (which may be capitalized or slightly off) to a
    /// valid case so the picker shows the selection instead of a blank "Tone".
    private var toneBinding: Binding<String> {
        Binding(
            get: {
                let raw = (viewModel.experienceDraft?.tone ?? "").lowercased()
                return ExperienceTone(rawValue: raw)?.rawValue ?? ExperienceTone.mixed.rawValue
            },
            set: { viewModel.experienceDraft?.tone = $0 }
        )
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
