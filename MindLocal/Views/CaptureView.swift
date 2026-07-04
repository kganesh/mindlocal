import SwiftUI
import SwiftData

struct CaptureView: View {
    @State private var viewModel = CaptureViewModel()
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.phase {
                case .input:
                    inputView
                case .extracting:
                    ProgressView("Understanding your note…")
                case .preview:
                    if viewModel.draft != nil {
                        DraftPreviewView(viewModel: viewModel, onSave: save)
                    }
                case .followUp(let question, let field):
                    FollowUpView(question: question, field: field, viewModel: viewModel)
                case .notADecision:
                    notADecisionView
                case .error(let message):
                    errorView(message)
                }
            }
            .navigationTitle("Capture")
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { viewModel.persistWorkInProgress() }
            }
        }
    }

    private var inputView: some View {
        VStack(spacing: 24) {
            TextEditor(text: $viewModel.typedText)
                .frame(minHeight: 120)
                .padding(8)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .topLeading) {
                    if viewModel.typedText.isEmpty && !viewModel.speech.isRecording {
                        Text("What did you decide? Speak or type freely…")
                            .foregroundStyle(.secondary)
                            .padding(16)
                            .allowsHitTesting(false)
                    }
                }
                // Stream the live transcript straight into the text field.
                .onChange(of: viewModel.speech.transcript) { _, newValue in
                    if viewModel.speech.isRecording { viewModel.typedText = newValue }
                }

            micButton

            Button("Continue") {
                Task { await viewModel.submit() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.typedText.isEmpty && viewModel.speech.transcript.isEmpty)
        }
        .padding()
    }

    private var micButton: some View {
        Button {
            if viewModel.speech.isRecording {
                viewModel.speech.stopRecording()
                viewModel.typedText = viewModel.speech.transcript
            } else {
                Task {
                    if await viewModel.speech.requestAuthorization() {
                        try? await viewModel.speech.startRecording()
                    }
                }
            }
        } label: {
            Image(systemName: viewModel.speech.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(viewModel.speech.isRecording ? .red : .accentColor)
        }
        .accessibilityLabel(viewModel.speech.isRecording ? "Stop recording" : "Start recording")
    }

    private var notADecisionView: some View {
        ContentUnavailableView {
            Label("No Decision Found", systemImage: "questionmark.bubble")
        } description: {
            Text("This note doesn't seem to contain a decision.")
        } actions: {
            Button("Edit Note") { viewModel.phase = .input }
            Button("Discard", role: .destructive) { viewModel.discard() }
        }
    }

    private func errorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Something Went Wrong", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") { Task { await viewModel.submit() } }
            Button("Back") { viewModel.phase = .input }
        }
    }

    private func save() {
        if let decision = viewModel.finalizeDecision() {
            modelContext.insert(decision)
        }
    }
}

struct FollowUpView: View {
    let question: String
    let field: String
    @Bindable var viewModel: CaptureViewModel
    @State private var answer = ""

    var body: some View {
        VStack(spacing: 20) {
            Text(question)
                .font(.title3.weight(.medium))
                .multilineTextAlignment(.center)

            TextField("Your answer", text: $answer, axis: .vertical)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Skip") { viewModel.skipFollowUp() }
                    .buttonStyle(.bordered)
                Button("Answer") {
                    Task { await viewModel.answerFollowUp(answer, field: field) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(answer.isEmpty)
            }
        }
        .padding()
    }
}
