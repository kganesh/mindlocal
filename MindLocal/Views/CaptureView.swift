import SwiftUI
import SwiftData

/// Single capture flow: describe what happened (voice or text); the AI extracts
/// the experience plus any decisions mentioned, then an editable review to save.
struct CaptureView: View {
    @State private var viewModel = CaptureViewModel()
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.phase {
                case .input:
                    inputView
                case .extracting:
                    ProgressView("Understanding your note…")
                case .preview:
                    if viewModel.experienceDraft != nil {
                        ExperiencePreviewView(viewModel: viewModel, onSave: save)
                    }
                case .nothingFound:
                    nothingFoundView
                case .error(let message):
                    errorView(message)
                }
            }
            .navigationTitle("New Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { viewModel.discard(); dismiss() }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { viewModel.persistWorkInProgress() }
            }
        }
    }

    private var inputView: some View {
        VStack(spacing: 24) {
            DatePicker("Date & time", selection: $viewModel.occurredAt, displayedComponents: [.date, .hourAndMinute])
                .padding(.horizontal, 4)

            TextEditor(text: $viewModel.typedText)
                .frame(minHeight: 140)
                .padding(8)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .topLeading) {
                    if viewModel.typedText.isEmpty && !viewModel.speech.isRecording {
                        Text("What happened? Speak or type freely — mention any decisions you made.")
                            .foregroundStyle(.secondary)
                            .padding(16)
                            .allowsHitTesting(false)
                    }
                }
                .onChange(of: viewModel.speech.transcript) { _, newValue in
                    if viewModel.speech.isRecording { viewModel.typedText = newValue }
                }

            HStack {
                Spacer()
                Text("\(wordCount) / \(wordLimit) words")
                    .font(.caption)
                    .foregroundStyle(wordCount > wordLimit ? .red : .secondary)
            }

            micButton

            Button("Continue") {
                Task { await viewModel.submit() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isInputEmpty || wordCount > wordLimit)

            if wordCount > wordLimit {
                Text("Keep it under \(wordLimit) words — trim a little to continue.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding()
    }

    private let wordLimit = 500

    private var wordCount: Int {
        viewModel.typedText.split(whereSeparator: \.isWhitespace).count
    }

    private var isInputEmpty: Bool {
        viewModel.typedText.isEmpty && viewModel.speech.transcript.isEmpty
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

    private var nothingFoundView: some View {
        ContentUnavailableView {
            Label("Nothing to Save", systemImage: "questionmark.bubble")
        } description: {
            Text("This note doesn't seem to describe an experience.")
        } actions: {
            Button("Edit Note") { viewModel.phase = .input }
            Button("Discard", role: .destructive) { viewModel.discard(); dismiss() }
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
        if let experience = viewModel.finalizeEntry() {
            modelContext.insert(experience)
        }
        dismiss()
    }
}
