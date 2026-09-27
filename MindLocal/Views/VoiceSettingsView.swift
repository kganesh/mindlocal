import SwiftUI
import AVFoundation

/// The read-aloud voice list shown from Ask. Only Kokoro voices appear here:
/// Apple's system voices are a fallback the app picks on its own, not a choice
/// worth putting in front of someone mid-question, and the old list of 40-odd
/// "Bad News"/"Bubbles" novelty voices read as noise. When Kokoro is off or its
/// model isn't downloaded there is nothing to choose, so the screen says so and
/// offers no rows. The full Apple list still lives in Settings → Read-Aloud.
struct KokoroVoicePicker: View {
    @State private var voiceNames: [String] = []
    @State private var selectedVoice = KokoroVoicePicker.currentVoice
    @State private var speaker = SpeechSpeaker()

    private let sample = "This is how MindLocal will read your advice aloud."

    private static var currentVoice: String {
        #if canImport(KokoroSwift)
        return KokoroSpeechEngine.selectedVoice
        #else
        return ""
        #endif
    }

    var body: some View {
        List {
            if VoiceEngine.isKokoroActive, !voiceNames.isEmpty {
                Section {
                    ForEach(voiceNames, id: \.self) { name in
                        Button {
                            select(name)
                        } label: {
                            HStack {
                                Text(Self.label(for: name)).foregroundStyle(AlbumTheme.ink)
                                Spacer()
                                if name == selectedVoice {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Read-Aloud Voice")
                } footer: {
                    Text("Tap a voice to hear it.")
                }
            } else {
                Section {
                    Label("The Kokoro voice is off.", systemImage: "waveform.slash")
                        .foregroundStyle(AlbumTheme.secondary)
                } footer: {
                    Text("Turn it on in Settings → Read-Aloud to choose a voice. Until then MindLocal reads aloud with Apple's built-in voice.")
                }
            }
        }
        .albumScreen()
        .navigationTitle("Voice")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadVoiceNames() }
        .onDisappear { speaker.stop() }
    }

    private func select(_ name: String) {
        #if canImport(KokoroSwift)
        selectedVoice = name
        KokoroSpeechEngine.selectedVoice = name
        speaker.speak(sample)
        #endif
    }

    private func loadVoiceNames() async {
        #if canImport(KokoroSwift)
        guard VoiceEngine.isKokoroActive, voiceNames.isEmpty else { return }
        voiceNames = await KokoroSpeechEngine.shared.voiceNames()
        #endif
    }

    /// "af_heart" → "Heart (American)". The first letter is the accent, the
    /// second the speaker's gender; only the accent is worth surfacing.
    static func label(for name: String) -> String {
        let parts = name.split(separator: "_")
        guard parts.count == 2, let accent = parts[0].first else { return name }
        let display = parts[1].capitalized
        return "\(display) (\(accent == "a" ? "American" : "British"))"
    }
}

/// Apple's system voices. Reachable only from Settings → Read-Aloud, as the
/// fallback the app uses when Kokoro is off.
struct VoicePicker: View {
    @AppStorage("selectedVoiceId") private var selectedVoiceId = ""
    @State private var speaker = SpeechSpeaker()

    private let sample = "This is how MindLocal will read your advice aloud."

    private var voices: [AVSpeechSynthesisVoice] {
        let prefix = String((Locale.current.language.languageCode?.identifier ?? "en").prefix(2))
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(prefix) }
            .sorted { rank($0.quality) != rank($1.quality) ? rank($0.quality) > rank($1.quality) : $0.name < $1.name }
    }

    var body: some View {
        List {
            Section {
                row(name: "Automatic (best installed)", detail: nil, isSelected: selectedVoiceId.isEmpty) {
                    selectedVoiceId = ""
                    speaker.speak(sample)
                }
                ForEach(voices, id: \.identifier) { voice in
                    row(name: voice.name, detail: qualityLabel(voice.quality),
                        isSelected: voice.identifier == selectedVoiceId) {
                        selectedVoiceId = voice.identifier
                        speaker.speak(sample)
                    }
                }
            } header: {
                Text("Read-Aloud Voice")
            } footer: {
                Text("Tap a voice to preview it. Download Enhanced or Premium voices in Settings → Accessibility → Spoken Content → Voices; they'll appear here.")
            }
        }
        .navigationTitle("Apple Voices")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { speaker.stop() }
    }

    private func row(name: String, detail: String?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).foregroundStyle(.primary)
                    if let detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isSelected { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
        }
    }

    private func qualityLabel(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .premium: "Premium"
        case .enhanced: "Enhanced"
        default: "Standard"
        }
    }
}

/// Standalone sheet wrapper (quick access from Advise).
struct VoiceSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            KokoroVoicePicker()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
        }
    }
}

private func rank(_ quality: AVSpeechSynthesisVoiceQuality) -> Int {
    switch quality {
    case .premium: 3
    case .enhanced: 2
    default: 1
    }
}
