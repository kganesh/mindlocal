import SwiftUI
import SwiftData

/// Voice-first nightly check-in: the app asks a few questions aloud, listens,
/// and saves a structured journal entry. Presented as a sheet.
struct JournalConversationView: View {
    @State private var viewModel = JournalConversationViewModel()
    @State private var didSave = false
    @State private var peopleConfirmed = false
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
            Text("I'll ask a few questions. Just talk — tap Next when you're done with each answer.")
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

            ScrollView {
                Text(viewModel.speech.transcript.isEmpty ? "Listening…" : viewModel.speech.transcript)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(viewModel.speech.transcript.isEmpty ? .secondary : .primary)
            }
            .frame(maxHeight: 220)

            Image(systemName: viewModel.speech.isRecording ? "waveform.circle.fill" : "mic.slash.circle")
                .font(.system(size: 44))
                .foregroundStyle(viewModel.speech.isRecording ? .red : .secondary)
                .symbolEffect(.pulse, isActive: viewModel.speech.isRecording)

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
