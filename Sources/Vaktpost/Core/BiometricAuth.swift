import Foundation
import LocalAuthentication
import SwiftUI
import os.log

private let biometricLog = OSLog(subsystem: "se.kladhest.vaktpost", category: "Biometric")

@MainActor
enum BiometricAuth {
    private static let enabledKey = "biometricAuth.enabled"
    
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }
    
    private static let context = LAContext()
    
    static func canUseBiometrics() -> Bool {
        var error: NSError?
        let can = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        if !can {
            os_log(.debug, log: biometricLog, "Biometrics unavailable: %{public}@", error?.localizedDescription ?? "unknown")
        }
        return can
    }
    
    static func authenticate(reason: String, completion: @escaping (Bool) -> Void) {
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else {
            completion(false)
            return
        }
        
        context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: reason
        ) { success, error in
            if success {
                os_log(.debug, log: biometricLog, "Biometric authentication successful")
            } else {
                os_log(.debug, log: biometricLog, "Biometric authentication failed: %{public}@", error?.localizedDescription ?? "unknown")
            }
            completion(success)
        }
    }
}

struct BiometricLockView: View {
    @State private var authState = AuthState.prompting
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss
    
    var onAuthenticated: () -> Void
    
    private enum AuthState {
        case prompting
        case failed
        case usingPasscode
    }
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "faceid")
                .scaledFont(64)
                .foregroundStyle(authState == .failed ? .red : .accentColor)
                .symbolEffect(.variableColor.iterative, isActive: authState == .prompting)
            
            VStack(spacing: 8) {
                Text("Authenticate to continue")
                    .scaledFont(18, weight: .semibold)
                
                if let errorMessage {
                    Text(errorMessage)
                        .scaledFont(13)
                        .foregroundStyle(.red)
                } else {
                    Text("Use Face ID or Touch ID to unlock Vaktpost")
                        .scaledFont(13)
                        .foregroundStyle(.secondary)
                }
            }
            
            if authState == .failed {
                Button {
                    Task { await tryAuthenticate() }
                } label: {
                    Text("Try again")
                        .scaledFont(15, weight: .medium)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onAppear {
            Task { await tryAuthenticate() }
        }
    }
    
    private func tryAuthenticate() async {
        authState = .prompting
        errorMessage = nil
        
        await withCheckedContinuation { continuation in
            BiometricAuth.authenticate(reason: "Unlock Vaktpost") { success in
                if success {
                    onAuthenticated()
                    dismiss()
                } else {
                    authState = .failed
                    errorMessage = "Authentication failed. Try again or use your passcode."
                }
                continuation.resume()
            }
        }
    }
}
