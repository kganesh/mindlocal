import Foundation
import AVFoundation

/// A text-to-speech backend.
///
/// The seam sits here rather than at `SpeechSpeaker` deliberately: the views
/// hold `SpeechSpeaker` as an `@Observable` and read `isSpeaking` to drive
/// their play/stop buttons, and observation tracking doesn't reliably survive
/// being boxed in an `any Protocol`. Keeping `SpeechSpeaker` concrete and
/// swapping what's *inside* it means no view changes at all.
///
/// Engines receive pre-chunked text (see `SpeechChunker`) and report when the
/// last chunk has finished playing.
@MainActor
protocol SpeechSynthesizing: AnyObject {
    /// Speaks the chunks in order. `onFinish` fires once, after the final chunk
    /// finishes — not after each one — and not at all if `stop()` intervenes.
    func speak(_ chunks: [String], onFinish: @escaping () -> Void)
    func stop()
}

/// `AVSpeechSynthesizer` backend — the built-in engine, always available.
///
/// Chunking is a no-op advantage here since `AVSpeechSynthesizer` already
/// queues utterances and streams them without a gap; the chunks are enqueued
/// as-is so the two engines stay interchangeable.
@MainActor
final class SystemSpeechEngine: NSObject, SpeechSynthesizing {

    /// Shared for the same reason Kokoro is: `@State private var speaker =
    /// SpeechSpeaker()` re-evaluates its initialiser on every View struct
    /// creation, and one synthesiser also gives coherent stop semantics.
    static let shared = SystemSpeechEngine()

    private let synthesizer = AVSpeechSynthesizer()
    private var pendingChunks = 0
    private var onFinish: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ chunks: [String], onFinish: @escaping () -> Void) {
        guard !chunks.isEmpty else { return onFinish() }
        stop()

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio,
                                                         options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        self.onFinish = onFinish
        pendingChunks = chunks.count

        let voice = Self.bestVoice()
        for chunk in chunks {
            let utterance = AVSpeechUtterance(string: chunk)
            utterance.voice = voice
            synthesizer.speak(utterance)
        }
    }

    func stop() {
        // Drop the callback before cancelling: `didCancel` fires per queued
        // utterance, and a stop is not a finish.
        onFinish = nil
        pendingChunks = 0
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }

    private func chunkEnded() {
        guard pendingChunks > 0 else { return }
        pendingChunks -= 1
        guard pendingChunks == 0 else { return }
        let finish = onFinish
        onFinish = nil
        finish?()
    }

    /// The user's chosen voice if set, otherwise the highest-quality installed
    /// voice for their language (premium > enhanced > default).
    static func bestVoice() -> AVSpeechSynthesisVoice? {
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

extension SystemSpeechEngine: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.chunkEnded() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.chunkEnded() }
    }
}
