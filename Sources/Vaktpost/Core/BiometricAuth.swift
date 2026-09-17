import Foundation
import LocalAuthentication
import SwiftUI
import os.log

private let biometricLog = OSLog(subsystem: "se.kladhest.vaktpost", category: "Biometric")

/// Keeps optional biometric protection from becoming a prerequisite for
/// configuring a firewall. The setting is deliberately effective only while
/// iOS can actually evaluate biometrics; this matches the app-lock boundary
/// and avoids locking credential maintenance on simulators and devices where
/// Face ID or Touch ID is not enrolled.
enum CredentialProtectionPolicy {
    static func requiresAuthorization(isEnabled: Bool, canUseBiometrics: Bool) -> Bool {
        isEnabled && canUseBiometrics
    }
}

@MainActor
enum BiometricAuth {
    private static let enabledKey = "biometricAuth.enabled"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    enum Outcome {
        case success
        /// The person failed or dismissed the prompt. Worth offering another
        /// go at.
        case failed(String)
        /// iOS took the prompt away for its own reasons — the app was
        /// backgrounded mid-prompt, or something else claimed the screen. Not
        /// a failed attempt, and telling somebody their face was rejected when
        /// it was never looked at is both wrong and alarming.
        case cancelled
        /// No biometry, or it is locked out after too many attempts.
        case unavailable(String)
    }

    /// A context for one evaluation, never reused.
    ///
    /// This was a `static let` shared by every call, and that is the bug
    /// behind a Face ID prompt that appears and vanishes without asking for
    /// anything. An `LAContext` holds the result of a successful evaluation:
    /// evaluate the same policy on the same context again and it returns
    /// success straight away, without prompting. The system sheet still
    /// flashes up for an instant as it is created and immediately torn down,
    /// which is exactly what it looked like — a lock screen that appeared,
    /// blinked, and let you in.
    ///
    /// Apple's guidance is a context per evaluation. A fresh one has no
    /// authentication to reuse, so every unlock is a real one.
    private static func freshContext() -> LAContext {
        let context = LAContext()
        // Belt and braces: even a fresh context will reuse a recent
        // device-level authentication if this is non-zero. Zero means every
        // call asks.
        context.touchIDAuthenticationAllowableReuseDuration = 0
        return context
    }

    static func canUseBiometrics() -> Bool {
        var error: NSError?
        let can = freshContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                                   error: &error)
        if !can {
            os_log(.debug, log: biometricLog, "Biometrics unavailable: %{public}@",
                   error?.localizedDescription ?? "unknown")
        }
        return can
    }

    /// Ask for a face, a fingerprint, or — when `allowPasscode` — the device
    /// passcode as a fallback.
    ///
    /// The passcode path is not decoration. Biometry locks out after five
    /// failed attempts and stays locked until a passcode unlock, so a lock
    /// screen offering only biometrics can lock somebody out of this app until
    /// they unlock the phone itself. The failure message already promised a
    /// passcode; now there is one.
    static func authenticate(reason: String, allowPasscode: Bool = false) async -> Outcome {
        let policy: LAPolicy = allowPasscode
            ? .deviceOwnerAuthentication
            : .deviceOwnerAuthenticationWithBiometrics
        let context = freshContext()

        var error: NSError?
        guard context.canEvaluatePolicy(policy, error: &error) else {
            let message = error?.localizedDescription ?? "Biometrics are not available."
            os_log(.debug, log: biometricLog, "Cannot evaluate: %{public}@", message)
            return .unavailable(message)
        }

        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(policy, localizedReason: reason) { success, error in
                if success {
                    os_log(.debug, log: biometricLog, "Authentication succeeded")
                    continuation.resume(returning: .success)
                    return
                }

                let code = (error as? LAError)?.code
                switch code {
                // The app was backgrounded while the sheet was up, or iOS took
                // it away. Not an attempt, and not something to report as one.
                case .systemCancel, .appCancel:
                    continuation.resume(returning: .cancelled)
                // Asked at a moment when nothing could have been presented —
                // the app was not frontmost, or the context was no longer
                // valid. Also not an attempt. These were landing in `default`
                // and being shown as "the operation couldn't be completed",
                // which reads as a failed face and is not one.
                case .invalidContext, .notInteractive:
                    continuation.resume(returning: .cancelled)
                case .biometryLockout:
                    continuation.resume(returning: .unavailable(
                        "Too many failed attempts. Unlock with your passcode."))
                case .biometryNotAvailable, .biometryNotEnrolled, .passcodeNotSet:
                    continuation.resume(returning: .unavailable(
                        error?.localizedDescription ?? "Biometrics are not available."))
                default:
                    os_log(.debug, log: biometricLog, "Authentication failed: %{public}@",
                           error?.localizedDescription ?? "unknown")
                    continuation.resume(returning: .failed(
                        error?.localizedDescription ?? "Authentication failed."))
                }
            }
        }
    }
}

/// The screen shown over everything until the person proves who they are.
///
/// Also used, with `requiresAuthentication` false, as a plain cover while the
/// app is merely inactive — a notification pulled down, the control centre
/// opened, the app switcher invoked. In that state it hides the dashboard
/// without asking for anything, which is what the app-switcher snapshot needs.
struct BiometricLockView: View {
    @Environment(\.themeManager) private var theme: ThemeManager

    /// False while this is only obscuring the screen.
    var requiresAuthentication: Bool = true
    var onAuthenticated: () -> Void

    @Environment(\.scenePhase) private var scenePhase

    @State private var state = AuthState.idle
    @State private var message: String?
    @State private var isAuthenticating = false

    /// Whether a prompt has already been raised since the app last came to the
    /// foreground.
    ///
    /// Presenting the system sheet makes the app inactive and dismissing it
    /// makes it active again, so "became active" fires more than once per
    /// unlock. Without this, finishing one prompt starts another.
    @State private var hasPrompted = false

    private enum AuthState {
        case idle
        case prompting
        case failed
        /// Biometry will not run — locked out, not enrolled. The only way past
        /// is the passcode.
        case needsPasscode
    }

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield")
                .scaledFont(64)
                .foregroundStyle(state == .failed ? theme.bad : theme.accentColor)
                .symbolEffect(.variableColor.iterative, isActive: state == .prompting)

            if requiresAuthentication {
                VStack(spacing: 8) {
                    Text("Authenticate to continue")
                        .scaledFont(18, weight: .semibold)
                        .foregroundStyle(theme.label)

                    Text(message ?? "Use Face ID or Touch ID to unlock Vaktpost.")
                        .scaledFont(13)
                        .foregroundStyle(message == nil ? theme.labelMuted : theme.bad)
                        .multilineTextAlignment(.center)
                }

                if state == .failed {
                    button("Try again") { await attempt(allowPasscode: false) }
                }
                if state == .failed || state == .needsPasscode {
                    button("Use passcode") { await attempt(allowPasscode: true) }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bg)
        .ignoresSafeArea()
        // Prompt when the app is frontmost, and not a moment before.
        //
        // This used to fire the instant the lock was required, which is
        // `.background` — the app is on its way out, nothing can be presented,
        // and `evaluatePolicy` fails immediately with an error about the
        // request rather than about the person. By the time the app came back
        // the prompt had already failed, so the screen showed
        // "LocalAuthentication error 6" and waited to be tapped instead of
        // asking for a face.
        //
        // Face ID has to be asked for while the app is on screen. That is
        // `.active`, and only `.active`.
        .task { await promptIfNeeded() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await promptIfNeeded() }
            case .background:
                // A real backgrounding, so the next foreground is a new
                // unlock and should ask again.
                hasPrompted = false
            case .inactive:
                break
            @unknown default:
                break
            }
        }
        .onChange(of: requiresAuthentication) { _, required in
            // A cover that went up as a privacy screen and has become a lock
            // screen, while already frontmost.
            if required { Task { await promptIfNeeded() } }
        }
    }

    private func button(_ title: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Text(title)
                .scaledFont(15, weight: .medium)
                .foregroundStyle(theme.label)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(theme.cardRaised)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 32)
    }

    /// The conditions under which raising a prompt can actually work.
    private func promptIfNeeded() async {
        guard requiresAuthentication, scenePhase == .active, !hasPrompted else { return }
        hasPrompted = true
        await attempt(allowPasscode: false)
    }

    private func attempt(allowPasscode: Bool) async {
        // Re-entrancy guard. Two evaluations at once produce two system
        // sheets, and the second one tearing down the first is another way to
        // get a prompt that flashes and disappears.
        guard !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        state = .prompting
        message = nil

        switch await BiometricAuth.authenticate(reason: "Unlock Vaktpost",
                                                allowPasscode: allowPasscode) {
        case .success:
            onAuthenticated()
        case .cancelled:
            // iOS took the sheet away, or it was asked for at a moment when
            // nothing could be presented. Say nothing and stay locked.
            //
            // `hasPrompted` is cleared so returning to the foreground asks
            // again rather than leaving a lock screen that never prompts.
            state = .idle
            message = nil
            hasPrompted = false
        case let .failed(text):
            state = .failed
            message = text
        case let .unavailable(text):
            state = .needsPasscode
            message = text
        }
    }
}
