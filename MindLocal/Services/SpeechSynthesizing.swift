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

    /// Shared because `@State private var speaker =
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

        // `try?` on both of these is why the silence was invisible: a session
        // still held by the recogniser refuses the change, and nothing said so.
        // Surfaced in debug builds, so the next time it fails it is findable.
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            #if DEBUG
            print("Read-aloud could not take the audio session: \(error)")
            #endif
        }

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

        // Release the session only if this engine was actually holding it.
        // `stop` is called defensively all over the app — dismissing an answer,
        // leaving a screen, at the top of `speak` — and deactivating a session
        // it never claimed takes it away from whatever does hold it. With the
        // mic live that ends the recording mid-sentence, which looks from the
        // outside like dictation that stopped printing.
        guard synthesizer.isSpeaking else { return }
        synthesizer.stopSpeaking(at: .immediate)
        releaseSession()
    }

    private func chunkEnded() {
        guard pendingChunks > 0 else { return }
        pendingChunks -= 1
        guard pendingChunks == 0 else { return }
        releaseSession()
        let finish = onFinish
        onFinish = nil
        finish?()
    }

    /// Hands the audio session back once there is nothing left to say.
    ///
    /// Recording releases it; this is the other half. Without it a session was
    /// left active and configured for playback, and the next `startRecording`
    /// had to reconfigure a live session rather than claim a free one. That
    /// shows up only where speaking and listening alternate, which is the
    /// nightly check-in: it reads a question aloud before every answer, and the
    /// words came back slower there than anywhere else in the app.
    private func releaseSession() {
        do {
            try AVAudioSession.sharedInstance()
                .setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            #if DEBUG
            print("Read-aloud could not release the audio session: \(error)")
            #endif
        }
    }

    /// The voice this app prefers when nobody has chosen one.
    ///
    /// Resolved by name rather than identifier, because the identifier differs
    /// by quality tier and region — and Nicky is a downloaded voice, so on a
    /// device that has never fetched her there is nothing to resolve. That is
    /// the case the fallback below exists for.
    static let preferredVoiceName = "Nicky"

    /// The user's chosen voice, or `defaultVoice()` when they have not chosen.
    static func bestVoice() -> AVSpeechSynthesisVoice? {
        if let id = UserDefaults.standard.string(forKey: "selectedVoiceId"), !id.isEmpty,
           let chosen = AVSpeechSynthesisVoice(identifier: id) {
            return chosen
        }
        return defaultVoice()
    }

    /// What the app picks for someone who has never chosen: the preferred voice
    /// at the best quality installed, otherwise the highest-quality installed
    /// voice for their language (premium > enhanced > default).
    ///
    /// Separate from `bestVoice` so the picker can name the voice behind
    /// "Automatic" without having to disturb a stored preference to find out.
    static func defaultVoice() -> AVSpeechSynthesisVoice? {
        let prefix = String((Locale.current.language.languageCode?.identifier ?? "en").prefix(2))
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(prefix) }
        func rank(_ quality: AVSpeechSynthesisVoiceQuality) -> Int {
            switch quality {
            case .premium: 3
            case .enhanced: 2
            default: 1
            }
        }
        let preferred = voices
            .filter { $0.name.caseInsensitiveCompare(preferredVoiceName) == .orderedSame }
            .max { rank($0.quality) < rank($1.quality) }
        if let preferred { return preferred }

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
