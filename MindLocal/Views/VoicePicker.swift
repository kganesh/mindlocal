import SwiftUI
import AVFoundation

/// Apple's system voices. Reachable from Settings → Read-Aloud, as the fallback
/// the app uses when Kokoro is off.
struct VoicePicker: View {
    @AppStorage("selectedVoiceId") private var selectedVoiceId = ""
    @State private var speaker = SpeechSpeaker()

    private let sample = "This is how MindLocal will read your advice aloud."

    /// The installed voices for this language, in a list where no two rows look
    /// the same.
    ///
    /// Matching on the language alone takes in en-US, en-GB, en-AU, en-IE,
    /// en-IN and en-ZA, and Apple reuses names across regions — there is a
    /// Daniel in several of them. The same voice also ships at more than one
    /// quality. Both are real differences, so the fix is to show them rather
    /// than to hide rows: the region and the quality go on the row, and only
    /// genuine repeats of all three are dropped.
    ///
    /// Sorted with this device's own region first, since that is the one most
    /// people want, then by quality, then by name.
    private var voices: [AVSpeechSynthesisVoice] {
        let language = String((Locale.current.language.languageCode?.identifier ?? "en").prefix(2))
        let home = Locale.current.identifier.replacingOccurrences(of: "_", with: "-")

        var seen = Set<String>()
        let unique = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(language) }
            .filter { seen.insert("\($0.name)|\($0.language)|\($0.quality.rawValue)").inserted }

        return unique.sorted { a, b in
            let aHome = a.language == home, bHome = b.language == home
            if aHome != bHome { return aHome }
            if a.language != b.language { return a.language < b.language }
            if rank(a.quality) != rank(b.quality) { return rank(a.quality) > rank(b.quality) }
            return a.name < b.name
        }
    }

    /// "English (United Kingdom) · Enhanced" — what tells two rows with the
    /// same name apart.
    private func detail(for voice: AVSpeechSynthesisVoice) -> String {
        let locale = Locale.current.localizedString(forIdentifier: voice.language)
            ?? voice.language
        return "\(locale) · \(qualityLabel(voice.quality))"
    }

    var body: some View {
        List {
            Section {
                row(name: "Automatic (best installed)", detail: nil, isSelected: selectedVoiceId.isEmpty) {
                    selectedVoiceId = ""
                    speaker.speak(sample)
                }
                ForEach(voices, id: \.identifier) { voice in
                    row(name: voice.name, detail: detail(for: voice),
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

private func rank(_ quality: AVSpeechSynthesisVoiceQuality) -> Int {
    switch quality {
    case .premium: 3
    case .enhanced: 2
    default: 1
    }
}
