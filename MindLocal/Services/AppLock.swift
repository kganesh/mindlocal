import Foundation
import LocalAuthentication
import SwiftUI

/// Keeps the journal behind Face ID.
///
/// Off by default. Someone who turns it on is saying this phone is sometimes in
/// other hands, and everything below follows from taking that literally.
///
/// Authentication is `deviceOwnerAuthentication`, not the biometrics-only
/// variant, so the device passcode is always a way through. A journal locked
/// behind a face that a cut lip or a new pair of glasses can defeat, with no
/// second route, is a way to lose years of writing. Apple's own prompt handles
/// the fallback; we only have to ask for the right policy.
@MainActor
@Observable
final class AppLock {

    static let shared = AppLock()

    static let preferenceKey = "lock.requireBiometrics"

    /// Whether the user asked for this. Read through the same defaults the
    /// Settings toggle writes.
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.preferenceKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.preferenceKey)
            // Turning it on should not demand a face immediately; the person
            // is holding the phone and has just proved it by tapping. Turning
            // it off unlocks, or the switch would appear not to work.
            isLocked = false
        }
    }

    /// Whether the journal is hidden right now.
    private(set) var isLocked = false

    /// Set while the system prompt is up, so a scene change behind it does not
    /// start a second one. Two overlapping prompts is how this ends with an
    /// app nobody can open.
    private var isAuthenticating = false

    private init() {
        isLocked = isEnabled
    }

    /// What the device actually offers, for naming the setting honestly. A
    /// phone with no biometrics can still use this through the passcode, so the
    /// feature is offered either way.
    static var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        switch context.biometryType {
        case .faceID:  return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default:       return "Passcode"
        }
    }

    /// Called when the app comes back from the background.
    func lockIfNeeded() {
        guard isEnabled, !isAuthenticating else { return }
        isLocked = true
    }

    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        do {
            let passed = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock your journal."
            )
            if passed { isLocked = false }
        } catch {
            // Cancelled, or failed. The lock screen stays with its own button,
            // so there is always a way to try again. Nothing is logged: which
            // authentication failed and when is itself worth not recording.
        }
    }
}
