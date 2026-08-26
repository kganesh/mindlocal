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

    static func make() -> SpeechSynthesizing {
        #if canImport(KokoroSwift)
        if useKokoro, let modelFile = KokoroModelStore.shared.modelFile {
            // A corrupt or half-written model file throws here rather than at
            // the first spoken word; falling back is better than a dead button.
            if let engine = try? KokoroSpeechEngine(modelFile: modelFile) { return engine }
        }
        #endif
        return SystemSpeechEngine()
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
