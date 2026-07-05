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
}
