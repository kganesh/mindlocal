import Foundation

/// Chooses the text-to-speech backend.
///
/// Same contract as `SpeechEngine` on the transcription side: the preference
/// alone never selects Kokoro. The weights must also be present, so a download
/// the system evicts under storage pressure degrades to Apple's voice rather
/// than to silence.
enum VoiceEngine {

    /// Whether Kokoro is offered at all. Off until the read-aloud static is
    /// understood: a reply that breaks into noise partway through is not
    /// something to hand a tester, and Apple's voice has never done it.
    ///
    /// The getter below refuses the stored preference rather than clearing it,
    /// so anyone who had already chosen Kokoro falls back to Apple's voice now
    /// and gets their own choice back when this is turned on again.
    static let isOffered = false

    static let preferenceKey = "voice.useKokoro"

    static var useKokoro: Bool {
        get { isOffered && UserDefaults.standard.bool(forKey: preferenceKey) }
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
