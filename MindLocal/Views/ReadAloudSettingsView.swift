import SwiftUI

/// Settings → Read-Aloud. Opting into the Kokoro voice means accepting a
/// one-time model download; the 28 voices themselves ship with the app, so the
/// picker below is browsable before anything is downloaded.
struct ReadAloudSettingsView: View {

    @State private var store = KokoroModelStore.shared
    @State private var useKokoro = VoiceEngine.useKokoro
    @State private var confirmingDownload = false
    @State private var confirmingRemoval = false
    @State private var selectedVoice = currentVoice
    @State private var voiceNames: [String] = []
    /// One shared speaker for previews. Rebuilding it per tap used to rebuild
    /// the whole engine; the engine is shared now and reads the selected voice
    /// at speak time, so one instance is enough.
    @State private var preview = SpeechSpeaker()

    private static var currentVoice: String {
        #if canImport(KokoroSwift)
        return KokoroSpeechEngine.selectedVoice
        #else
        return ""
        #endif
    }

    private let sample = "This is how MindLocal will read your reflections back to you."

    var body: some View {
        List {
            Section {
                Toggle("Kokoro voice", isOn: kokoroBinding)
                    .disabled(store.state == .unavailable || store.isDownloading)

                switch store.state {
                case .downloading(let progress):
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: progress)
                        Text("Downloading… \(Int(progress * 100))% of \(KokoroModelStore.approximateSizeMB) MB")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                case .ready:
                    Button(role: .destructive) { confirmingRemoval = true } label: {
                        Label("Remove Download (\(KokoroModelStore.approximateSizeMB) MB)",
                              systemImage: "trash")
                    }
                case .failed(let reason):
                    Label(reason, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Try Again") { Task { await enableKokoro() } }
                case .unavailable:
                    Label("Not available in this build.", systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                case .notDownloaded:
                    EmptyView()
                }
            } header: {
                Text("Read-Aloud Voice")
            } footer: {
                Text(footer)
            }

            #if canImport(KokoroSwift)
            if useKokoro, store.state == .ready, !voiceNames.isEmpty {
                Section("Voice") {
                    ForEach(voiceNames, id: \.self) { name in
                        Button {
                            selectedVoice = name
                            KokoroSpeechEngine.selectedVoice = name
                            preview.speak(sample)
                        } label: {
                            HStack {
                                Text(label(for: name)).foregroundStyle(.primary)
                                Spacer()
                                if name == selectedVoice {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }
            }
            #endif

            Section {
                NavigationLink("Apple Voices") { VoicePicker() }
            } footer: {
                Text("Used whenever the Kokoro voice is off or its model isn't downloaded.")
            }
        }
        .navigationTitle("Read-Aloud")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadVoiceNames() }
        .onDisappear { preview.stop() }
        .alert("Download the Kokoro voice model?", isPresented: $confirmingDownload) {
            Button("Download") { Task { await enableKokoro() } }
            Button("Not Now", role: .cancel) { useKokoro = false }
        } message: {
            Text("About \(KokoroModelStore.approximateSizeMB) MB, once. Only the model is downloaded — nothing you've written leaves the device, and speech is generated entirely offline afterwards.")
        }
        .alert("Remove the downloaded model?", isPresented: $confirmingRemoval) {
            Button("Remove", role: .destructive) { removeKokoro() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Frees \(KokoroModelStore.approximateSizeMB) MB and returns to Apple's built-in voice.")
        }
    }

    // MARK: - Actions

    private var kokoroBinding: Binding<Bool> {
        Binding(
            get: { useKokoro },
            set: { wanted in
                useKokoro = wanted
                guard wanted else { return VoiceEngine.useKokoro = false }
                if store.state == .ready {
                    VoiceEngine.useKokoro = true
                } else {
                    confirmingDownload = true
                }
            }
        )
    }

    /// Reads the bundled 14 MB voice archive once, off the view body.
    private func loadVoiceNames() async {
        #if canImport(KokoroSwift)
        guard voiceNames.isEmpty else { return }
        voiceNames = await KokoroSpeechEngine.shared.voiceNames()
        #endif
    }

    private func enableKokoro() async {
        await store.download()
        let succeeded = store.state == .ready
        VoiceEngine.useKokoro = succeeded
        useKokoro = succeeded
        if succeeded { await loadVoiceNames() }
    }

    private func removeKokoro() {
        #if canImport(KokoroSwift)
        KokoroSpeechEngine.shared.purge()
        #endif
        store.removeDownload()
        voiceNames = []
        VoiceEngine.useKokoro = false
        useKokoro = false
    }

    /// "af_heart" → "Heart (American)". The first letter is the accent, the
    /// second the speaker's gender; only the accent is worth surfacing.
    private func label(for name: String) -> String {
        let parts = name.split(separator: "_")
        guard parts.count == 2, let accent = parts[0].first else { return name }
        let display = parts[1].capitalized
        return "\(display) (\(accent == "a" ? "American" : "British"))"
    }

    private var footer: String {
        switch store.state {
        case .unavailable: "This build doesn't include the Kokoro runtime."
        case .ready: "Kokoro is downloaded and ready. Turning this off returns to Apple's voice without deleting the model."
        case .downloading: "Keep this screen open until the download finishes."
        default: "Turning this on downloads a \(KokoroModelStore.approximateSizeMB) MB model once. Until then, MindLocal uses Apple's built-in voice."
        }
    }
}
