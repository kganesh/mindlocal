import Foundation

/// Debug-only switch for the grounded Advise path. The key lives here rather
/// than as a string literal in both SettingsView and AdviceView so the two
/// can't drift apart.
enum AdviceGroundingSettings {
    static let enabledKey = "groundedAnswersEnabled"

    /// Off unless explicitly enabled, and always off in release — the grounded
    /// path costs extra schema tokens against a 4,096-token window and exists
    /// for evaluation, not for shipping.
    static var isEnabled: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: enabledKey)
        #else
        false
        #endif
    }
}
