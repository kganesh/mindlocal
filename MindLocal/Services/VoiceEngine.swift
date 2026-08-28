import Foundation

/// Chooses the text-to-speech backend.
///
/// Same contract as `SpeechEngine` on the transcription side: the preference
/// alone never selects Kokoro. The weights must also be present, so a download
/// the system evicts under storage pressure degrades to Apple's voice rather
/// than to silence.
enum VoiceEngine {

    static let preferenceKey = "voice.useKokoro"

    static var useKokoro: Bool {
        get { UserDefaults.standard.bool(forKey: preferenceKey) }
        set { UserDefaults.standard.set(newValue, forKey: preferenceKey) }
    }

    static var isKokoroActive: Bool {
        #if canImport(KokoroSwift)
        return useKokoro && KokoroModelStore.shared.state == .ready
        #else
        return false
        #endif
    }

    /// Must stay cheap. This runs from `SpeechSpeaker.init`, which SwiftUI
    /// re-evaluates every time a View struct holding one is created — so
    /// anything expensive here becomes a cost paid on every navigation.
    /// Both engines are shared instances that load lazily on first use.
    static func make() -> SpeechSynthesizing {
        #if canImport(KokoroSwift)
        if isKokoroActive { return KokoroSpeechEngine.shared }
        #endif
        return SystemSpeechEngine.shared
    }

    static var currentEngineName: String {
        #if canImport(KokoroSwift)
        if isKokoroActive {
            return "Kokoro (\(KokoroSpeechEngine.selectedVoice))"
        }
        #endif
        return "Apple built-in"
    }
}
