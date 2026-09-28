import Foundation

/// Chooses the speech backend.
///
/// There is one: Apple's on-device `SpeechTranscriber`. It ships with the app,
/// needs no download, and gives true word-by-word partial results.
///
/// A Whisper `base.en` engine lived behind this seam and is gone from this
/// branch, along with the WhisperKit dependency it needed. It was already
/// withdrawn, and carrying the framework for a feature nobody could reach was
/// weight in every download. The code is on `kokoro-tts` if it is ever wanted
/// back; the seam stays because `SpeechServicing` still has two sides to it and
/// a second engine would slot in here.
enum SpeechEngine {

    static func make() -> SpeechServicing {
        SpeechService()
    }

    /// One-line description for the Settings row.
    static var currentEngineName: String { "Apple on-device" }
}
