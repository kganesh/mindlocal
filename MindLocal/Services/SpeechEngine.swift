import Foundation

/// Chooses the speech backend.
///
/// Both implementations satisfy `SpeechServicing`, so this is the only place
/// that knows which one is live. Kept switchable at runtime rather than swapped
/// outright because the two have genuinely different characters — Apple's
/// `SpeechTranscriber` gives true word-by-word partials, Whisper gives better
/// punctuation and one model for every locale — and that trade is best judged
/// against real captures on real hardware, not in the abstract.
enum SpeechEngine {

    /// Set from the debug settings screen; survives relaunch.
    static let preferenceKey = "speech.useWhisper"

    static var useWhisper: Bool {
        get { UserDefaults.standard.bool(forKey: preferenceKey) }
        set { UserDefaults.standard.set(newValue, forKey: preferenceKey) }
    }

    /// Falls back to `SpeechService` when the WhisperKit package isn't linked,
    /// so a build without the dependency still records.
    static func make() -> SpeechServicing {
        #if canImport(WhisperKit)
        return useWhisper ? WhisperSpeechService() : SpeechService()
        #else
        return SpeechService()
        #endif
    }
}
