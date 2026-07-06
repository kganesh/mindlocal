import SwiftUI
import AVFoundation

/// Pick the read-aloud voice. Tapping a voice previews it. Higher-quality voices
/// are downloaded in iOS Settings.
struct VoiceSettingsView: View {
    @AppStorage("selectedVoiceId") private var selectedVoiceId = ""
    @Environment(\.dismiss) private var dismiss
    @State private var speaker = SpeechSpeaker()

    private var voices: [AVSpeechSynthesisVoice] {
        let prefix = String((Locale.current.language.languageCode?.identifier ?? "en").prefix(2))
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(prefix) }
            .sorted { rank($0.quality) != rank($1.quality) ? rank($0.quality) > rank($1.quality) : $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
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
            .navigationTitle("Voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { speaker.stop(); dismiss() }
                }
            }
            .onDisappear { speaker.stop() }
        }
    }

    private let sample = "This is how MindLocal will read your advice aloud."

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

private func rank(_ quality: AVSpeechSynthesisVoiceQuality) -> Int {
    switch quality {
    case .premium: 3
    case .enhanced: 2
    default: 1
    }
}
