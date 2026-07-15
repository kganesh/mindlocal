import SwiftUI
import SwiftData

/// Voice-first nightly check-in: the app asks a few questions aloud, listens,
/// and saves a structured journal entry. Presented as a sheet.
struct JournalConversationView: View {
    @State private var viewModel = JournalConversationViewModel()
    @State private var didSave = false
    @State private var peopleConfirmed = false
    @FocusState private var answerFocused: Bool
    @Query private var people: [Person]
    @Query private var relationships: [PersonRelationship]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Mentions from the built entry that still need a "who is this?" answer.
    private var peopleToConfirm: [String] {
        guard let experience = viewModel.builtExperience else { return [] }
        return PersonResolver.mentionsNeedingConfirmation(experience.people, people: people, relationships: relationships)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.phase {
                case .ready:
                    startView
                case .asking(let index):
                    conversationView(index)
                case .processing:
                    ProgressView("Making sense of your day…")
                case .saved:
                    if !peopleConfirmed && !peopleToConfirm.isEmpty {
                        PeopleConfirmView(mentions: peopleToConfirm, assignments: $viewModel.peopleAssignments) {
                            peopleConfirmed = true
                        }
                    } else {
                        savedView
                    }
                case .error(let message):
                    errorView(message)
                }
            }
            .navigationTitle("Nightly check-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { viewModel.cancel(); dismiss() }
                }
            }
        }
    }

    private var startView: some View {
        VStack(spacing: 24) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 64))
                .foregroundStyle(.indigo)
            Text("Let's capture your day")
                .font(.title2.weight(.semibold))
            Text("I'll ask a few questions. Type, paste, or talk — tap Next when you're done with each answer.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Start") { Task { await viewModel.start() } }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding()
    }

    private func conversationView(_ index: Int) -> some View {
        VStack(spacing: 20) {
            Text("Question \(index + 1) of \(viewModel.questions.count)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(viewModel.questions[index])
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)

            // Type, paste, or dictate — the mic streams into this field.
            TextEditor(text: $viewModel.currentAnswer)
                .frame(minHeight: 140, maxHeight: 240)
                .padding(8)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
                .focused($answerFocused)
                .overlay(alignment: .topLeading) {
                    if viewModel.currentAnswer.isEmpty {
                        Text(viewModel.speech.isRecording ? "Listening…" : "Type, paste, or tap the mic to speak")
                            .foregroundStyle(.secondary)
                            .padding(16)
                            .allowsHitTesting(false)
                    }
                }
                .onChange(of: viewModel.speech.transcript) { _, newValue in
                    if viewModel.speech.isRecording { viewModel.currentAnswer = newValue }
                }
                .onChange(of: answerFocused) { _, focused in
                    // Typing shouldn't fight dictation — stop the mic when the user edits.
                    if focused, viewModel.speech.isRecording { viewModel.stopRecording() }
                }

            Button {
                answerFocused = false
                Task { await viewModel.toggleMic() }
            } label: {
                Image(systemName: viewModel.speech.isRecording ? "waveform.circle.fill" : "mic.circle")
                    .font(.system(size: 44))
                    .foregroundStyle(viewModel.speech.isRecording ? .red : .accentColor)
                    .symbolEffect(.pulse, isActive: viewModel.speech.isRecording)
            }
            .accessibilityLabel(viewModel.speech.isRecording ? "Stop dictation" : "Dictate answer")

            HStack {
                Button("End now") { Task { await viewModel.endEarly() } }
                    .buttonStyle(.bordered)
                Spacer()
                Button(viewModel.isLastQuestion ? "Finish" : "Next") {
                    Task { await viewModel.advance() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button { answerFocused = false } label: {
                    Image(systemName: "checkmark").fontWeight(.semibold)
                }
                .accessibilityLabel("Done")
            }
        }
    }

    private var savedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("Saved your day")
                .font(.title2.weight(.semibold))
            Text("You can review or edit it in your Journal.")
                .foregroundStyle(.secondary)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding()
        .onAppear {
            if !didSave, let experience = viewModel.builtExperience {
                modelContext.insert(experience)
                experience.linkedPeople = PersonResolver.resolve(
                    experience.people,
                    assignments: viewModel.peopleAssignments,
                    in: modelContext
                )
                EmbeddingService.embed(experience)
                didSave = true
            }
        }
    }

    private func errorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't finish", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") { Task { await viewModel.start() } }
            Button("Close") { dismiss() }
        }
    }
}
