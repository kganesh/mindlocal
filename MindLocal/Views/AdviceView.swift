import SwiftUI
import SwiftData

/// Ask-AI tab: answers questions grounded in the user's saved decisions (spec §9).
struct AdviceView: View {
    @Query(sort: \Decision.createdAt, order: .reverse) private var decisions: [Decision]
    @Query(sort: \Experience.createdAt, order: .reverse) private var experiences: [Experience]
    @State private var viewModel = AdviceViewModel()
    @State private var speaker = SpeechSpeaker()
    @State private var showingVoiceSettings = false
    @FocusState private var isQuestionFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .bottom, spacing: 8) {
                        TextField("Ask about a decision or experience…", text: $viewModel.question, axis: .vertical)
                            .lineLimit(1...4)
                            .padding(12)
                            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
                            .focused($isQuestionFocused)

                        Button {
                            toggleMic()
                        } label: {
                            Image(systemName: viewModel.speech.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                                .font(.system(size: 34))
                                .foregroundStyle(viewModel.speech.isRecording ? .red : .accentColor)
                        }
                        .accessibilityLabel(viewModel.speech.isRecording ? "Stop recording" : "Ask by voice")
                    }
                    // Stream the spoken question into the field while recording.
                    .onChange(of: viewModel.speech.transcript) { _, newValue in
                        if viewModel.speech.isRecording { viewModel.question = newValue }
                    }

                    Button {
                        isQuestionFocused = false
                        let decisionSummaries = decisions.map(DecisionSummary.init)
                        let experienceSummaries = experiences.map(ExperienceSummary.init)
                        Task { await viewModel.ask(decisions: decisionSummaries, experiences: experienceSummaries) }
                    } label: {
                        Label("Ask", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canAsk)

                    content

                    Spacer(minLength: 0)

                    Text("Grounded in your \(decisions.count) decision\(decisions.count == 1 ? "" : "s") and \(experiences.count) experience\(experiences.count == 1 ? "" : "s"). Runs on-device.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Advise")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingVoiceSettings = true } label: {
                        Image(systemName: "waveform")
                    }
                    .accessibilityLabel("Read-aloud voice")
                }
            }
            .sheet(isPresented: $showingVoiceSettings) { VoiceSettingsView() }
            .onDisappear { speaker.stop() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .idle:
            if decisions.isEmpty && experiences.isEmpty {
                hint("Save a few decisions or experiences first — answers draw on your history.")
            } else {
                hint("Try: \"How do I usually handle money decisions?\" or \"What helps me have a good day?\"")
            }
        case .thinking:
            ProgressView("Thinking…")
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
        case .answer(let text):
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Answer", systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        speaker.toggle(text)
                    } label: {
                        Image(systemName: speaker.isSpeaking ? "stop.circle.fill" : "speaker.wave.2.fill")
                    }
                    .accessibilityLabel(speaker.isSpeaking ? "Stop reading" : "Read aloud")
                }
                Text(text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func toggleMic() {
        isQuestionFocused = false
        if viewModel.speech.isRecording {
            viewModel.speech.stopRecording()
            viewModel.question = viewModel.speech.transcript
        } else {
            Task {
                if await viewModel.speech.requestAuthorization() {
                    try? await viewModel.speech.startRecording()
                }
            }
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
