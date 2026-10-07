import Foundation

/// Chooses the text-to-speech backend.
///
/// One backend now: Apple's on-device voice. The seam stays because the choice
/// of which engine speaks belongs somewhere, and `SpeechSpeaker` asks here
/// rather than naming an engine itself.
///
/// A second engine lived behind this until the read-aloud static was
/// understood — a reply that breaks into noise partway through is not something
/// to hand a tester. That code is on the `kokoro-tts` branch, along with the
/// packages it needed.
enum VoiceEngine {

    /// Must stay cheap. This runs from `SpeechSpeaker.init`, which SwiftUI
    /// re-evaluates every time a View struct holding one is created, so
    /// anything expensive here becomes a cost paid on every navigation. The
    /// engine is a shared instance that loads lazily on first use.
    static func make() -> SpeechSynthesizing { SystemSpeechEngine.shared }

    static var currentEngineName: String { "Apple built-in" }
}
