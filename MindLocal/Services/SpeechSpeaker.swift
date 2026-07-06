import Foundation
import AVFoundation

/// On-device text-to-speech for reading advice aloud. Uses the highest-quality
/// installed voice for the user's language. Fully on-device — nothing leaves the
/// phone.
@MainActor
@Observable
final class SpeechSpeaker: NSObject {
    private let synthesizer = AVSpeechSynthesizer()
    private(set) var isSpeaking = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func toggle(_ text: String) {
        isSpeaking ? stop() : speak(text)
    }

    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = Self.bestVoice()
        synthesizer.speak(utterance)
        isSpeaking = true
    }

    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        isSpeaking = false
    }

    /// The user's chosen voice if set, otherwise the highest-quality installed
    /// voice for their language (premium > enhanced > default).
    private static func bestVoice() -> AVSpeechSynthesisVoice? {
        if let id = UserDefaults.standard.string(forKey: "selectedVoiceId"), !id.isEmpty,
           let chosen = AVSpeechSynthesisVoice(identifier: id) {
            return chosen
        }
        let prefix = String((Locale.current.language.languageCode?.identifier ?? "en").prefix(2))
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(prefix) }
        func rank(_ quality: AVSpeechSynthesisVoiceQuality) -> Int {
            switch quality {
            case .premium: 3
            case .enhanced: 2
            default: 1
            }
        }
        return voices.max { rank($0.quality) < rank($1.quality) }
            ?? AVSpeechSynthesisVoice(language: Locale.current.identifier)
    }
}

extension SpeechSpeaker: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}
