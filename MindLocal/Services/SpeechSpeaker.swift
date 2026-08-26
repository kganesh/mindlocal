import Foundation
import AVFoundation

/// On-device text-to-speech for reading advice aloud. Fully on-device — nothing
/// leaves the phone.
///
/// The public surface is unchanged from when this wrapped `AVSpeechSynthesizer`
/// directly; the synthesiser now sits behind `SpeechSynthesizing` so the engine
/// can be swapped without touching the four views that hold this type. Text is
/// chunked on the way in so a conversational reply starts playing before the
/// whole thing has been synthesised.
@MainActor
@Observable
final class SpeechSpeaker {

    private(set) var isSpeaking = false

    private let engine: SpeechSynthesizing
    private let chunker = SpeechChunker()

    /// Defaults to whichever engine is available and enabled. Injectable so
    /// tests can observe what was handed to the synthesiser.
    init(engine: SpeechSynthesizing? = nil) {
        self.engine = engine ?? SystemSpeechEngine()
    }

    func toggle(_ text: String) {
        isSpeaking ? stop() : speak(text)
    }

    func speak(_ text: String) {
        let chunks = chunker.chunks(from: text)
        guard !chunks.isEmpty else { return }

        engine.stop()
        isSpeaking = true
        engine.speak(chunks) { [weak self] in
            self?.isSpeaking = false
        }
    }

    func stop() {
        engine.stop()
        isSpeaking = false
    }
}
