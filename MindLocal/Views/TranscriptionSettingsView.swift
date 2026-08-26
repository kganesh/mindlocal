import SwiftUI

/// Settings → Transcription. Lets the user opt into Whisper, which means
/// accepting a one-time model download.
///
/// The toggle deliberately doesn't take effect until the download succeeds:
/// flipping a switch that silently does nothing until some later moment is
/// worse than asking first and reporting what happened.
struct TranscriptionSettingsView: View {

    @State private var store = WhisperModelStore.shared
    @State private var useWhisper = SpeechEngine.useWhisper
    @State private var confirmingDownload = false
    @State private var confirmingRemoval = false

    var body: some View {
        List {
            Section {
                Toggle("Whisper transcription", isOn: whisperBinding)
                    .disabled(store.state == .unavailable || store.isDownloading)

                switch store.state {
                case .downloading(let progress):
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: progress)
                        Text("Downloading… \(Int(progress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                case .ready:
                    Button(role: .destructive) {
                        confirmingRemoval = true
                    } label: {
                        Label("Remove Download (\(WhisperModelStore.approximateSizeMB) MB)",
                              systemImage: "trash")
                    }
                case .failed(let reason):
                    Label(reason, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Try Again") { Task { await enableWhisper() } }
                case .unavailable:
                    Label("Not available in this build.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .notDownloaded:
                    EmptyView()
                }
            } header: {
                Text("Transcription")
            } footer: {
                Text(footerText)
            }

            Section {
                LabeledContent("In use", value: SpeechEngine.currentEngineName)
            } footer: {
                Text("Apple's transcription is built in and always available. It shows words as you say them; Whisper works in ~1-second passes instead, but punctuates better and handles every language with one model.")
            }
        }
        .navigationTitle("Transcription")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Download the Whisper model?", isPresented: $confirmingDownload) {
            Button("Download") { Task { await enableWhisper() } }
            Button("Not Now", role: .cancel) { useWhisper = false }
        } message: {
            Text("About \(WhisperModelStore.approximateSizeMB) MB, once. Only the model is downloaded — nothing you've written leaves the device, and transcription still runs entirely offline afterwards.")
        }
        .alert("Remove the downloaded model?", isPresented: $confirmingRemoval) {
            Button("Remove", role: .destructive) { removeWhisper() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Frees \(WhisperModelStore.approximateSizeMB) MB. MindLocal goes back to Apple's on-device transcription; you can download it again later.")
        }
    }

    // MARK: - Actions

    private var whisperBinding: Binding<Bool> {
        Binding(
            get: { useWhisper },
            set: { wanted in
                useWhisper = wanted
                guard wanted else {
                    SpeechEngine.useWhisper = false
                    return
                }
                // Already on disk from a previous enable — no need to ask again.
                if store.state == .ready {
                    SpeechEngine.useWhisper = true
                } else {
                    confirmingDownload = true
                }
            }
        )
    }

    private func enableWhisper() async {
        await store.download()
        let succeeded = store.state == .ready
        SpeechEngine.useWhisper = succeeded
        // Leave the switch reflecting reality rather than intent, so a failed
        // download doesn't look like a working setting.
        useWhisper = succeeded
    }

    private func removeWhisper() {
        store.removeDownload()
        SpeechEngine.useWhisper = false
        useWhisper = false
    }

    private var footerText: String {
        switch store.state {
        case .unavailable:
            "This build doesn't include the Whisper runtime."
        case .ready:
            "Whisper is downloaded and ready. Turning this off returns to Apple's on-device transcription without deleting the model."
        case .downloading:
            "Keep this screen open until the download finishes."
        default:
            "Turning this on downloads a \(WhisperModelStore.approximateSizeMB) MB model once. Until then — and any time the download is missing — MindLocal uses Apple's built-in on-device transcription."
        }
    }
}
