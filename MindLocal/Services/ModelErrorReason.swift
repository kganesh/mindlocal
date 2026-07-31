import Foundation

/// Maps a FoundationModels error to a plain-language reason, without hard-coding
/// `LanguageModelSession.GenerationError`'s case names (matched on error text
/// instead, since those cases aren't guaranteed stable across OS versions).
/// Shared by every on-device generation call site so a refusal/context-window/
/// decoding failure reads the same way everywhere instead of a single generic
/// "couldn't do X" that discards the real cause.
enum ModelErrorReason {
    static func describe(_ error: Error) -> String {
        let detail = String(describing: error).lowercased()
        if detail.contains("refus") || detail.contains("guardrail")
            || detail.contains("sensitive") || detail.contains("safety") {
            return "Apple's on-device safety filter flagged this and wouldn't process it."
        } else if detail.contains("exceededcontextwindow") || detail.contains("context window") {
            return "There's too much on-device context to process at once."
        } else if detail.contains("decod") || detail.contains("parse") {
            return "The model's response couldn't be read cleanly."
        } else {
            return "Something went wrong on-device."
        }
    }

    /// `describe(_:)` plus the raw error in DEBUG builds, so device testing
    /// reveals the exact underlying case without shipping it to users.
    static func debugAnnotated(_ error: Error) -> String {
        let base = describe(error)
        #if DEBUG
        return "\(base)\n\n[\(error)]"
        #else
        return base
        #endif
    }
}
