import SwiftUI

/// Editable structured preview before save (spec §4 — every field editable).
struct DraftPreviewView: View {
    @Bindable var viewModel: CaptureViewModel
    let onSave: () -> Void

    var body: some View {
        if viewModel.draft != nil {
            Form {
                Section("Decision") {
                    TextField("Title", text: binding(\.title))
                    TextField("What you decided", text: binding(\.statement), axis: .vertical)
                }
                Section("Context") {
                    TextField("Situation & constraints", text: binding(\.context), axis: .vertical)
                }
                Section("Options Considered") {
                    ForEach(viewModel.draft!.options.indices, id: \.self) { i in
                        VStack(alignment: .leading) {
                            TextField("Option", text: optionBinding(i, \.text))
                            TextField("Why rejected (optional)", text: optionBinding(i, \.rejectedBecause))
                                .font(.caption)
                        }
                    }
                    .onDelete { viewModel.draft?.options.remove(atOffsets: $0) }
                    Button("Add Option") {
                        viewModel.draft?.options.append(OptionDraft(text: "", rejectedBecause: ""))
                    }
                }
                Section("Rationale") {
                    TextField("Why this choice", text: binding(\.rationale), axis: .vertical)
                }
                Section("Classification") {
                    Picker("Domain", selection: binding(\.domain)) {
                        ForEach(Domain.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    Picker("Stakes", selection: binding(\.stakes)) {
                        ForEach(Stakes.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                }
                Section {
                    Button("Save Decision") { onSave() }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.borderedProminent)
                    Button("Discard", role: .destructive) { viewModel.discard() }
                        .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Review")
        }
    }

    private func binding(_ keyPath: WritableKeyPath<DecisionDraft, String>) -> Binding<String> {
        Binding(
            get: { viewModel.draft?[keyPath: keyPath] ?? "" },
            set: { viewModel.draft?[keyPath: keyPath] = $0 }
        )
    }

    private func optionBinding(_ index: Int, _ keyPath: WritableKeyPath<OptionDraft, String>) -> Binding<String> {
        Binding(
            get: {
                guard let opts = viewModel.draft?.options, opts.indices.contains(index) else { return "" }
                return opts[index][keyPath: keyPath]
            },
            set: {
                guard viewModel.draft?.options.indices.contains(index) == true else { return }
                viewModel.draft?.options[index][keyPath: keyPath] = $0
            }
        )
    }
}
