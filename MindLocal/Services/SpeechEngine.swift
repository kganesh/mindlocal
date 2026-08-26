import Foundation

/// Chooses the speech backend.
///
/// Apple's on-device `SpeechTranscriber` is the default and the fallback — it
/// ships with the app, needs no download, and gives true word-by-word partials.
/// Whisper is opt-in from Settings and only becomes reachable once its weights
/// have actually been downloaded, so every path that can't produce a working
/// Whisper ends up back at `SpeechService` rather than at an error.
enum SpeechEngine {

    /// User's preference, set in Settings → Transcription. Survives relaunch.
    /// On its own it isn't enough to select Whisper — see `make()`.
    static let preferenceKey = "speech.useWhisper"

    static var useWhisper: Bool {
        get { UserDefaults.standard.bool(forKey: preferenceKey) }
        set { UserDefaults.standard.set(newValue, forKey: preferenceKey) }
    }

    /// True when Whisper is both wanted and usable right now.
    ///
    /// The two conditions are deliberately separate: the preference can stay on
    /// through a download the system later evicts under storage pressure, and
    /// the app should quietly transcribe with Apple's recogniser in the
    /// meantime rather than refuse to record.
    static var isWhisperActive: Bool {
        #if canImport(WhisperKit)
        return useWhisper && WhisperModelStore.shared.state == .ready
        #else
        return false
        #endif
    }

    static func make() -> SpeechServicing {
        #if canImport(WhisperKit)
        if useWhisper, let folder = WhisperModelStore.shared.modelFolder {
            return WhisperSpeechService(modelFolder: folder)
        }
        #endif
        return SpeechService()
    }

    /// One-line description for the Settings row.
    static var currentEngineName: String {
        isWhisperActive ? "Whisper (base.en)" : "Apple on-device"
    }
}
