import SwiftUI

/// Editable structured preview of an extracted experience before save.
struct ExperiencePreviewView: View {
    @Bindable var viewModel: CaptureViewModel
    let onSave: () -> Void

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
