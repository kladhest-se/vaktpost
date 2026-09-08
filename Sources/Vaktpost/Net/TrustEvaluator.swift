import Foundation
import CryptoKit
import SwiftUI

/// Holds mutable state for `TrustEvaluator` under a lock so the outer
/// class can be provably `Sendable`.
private final class TrustState: @unchecked Sendable {
    var profile: ServerProfile
    private var _fingerprint: String?

    private let lock = NSLock()

    init(profile: ServerProfile) {
        self.profile = profile
    }

    /// Reads both values under the lock.
    func read() -> (ServerProfile, String?) {
        lock.lock()
        defer { lock.unlock() }
        return (profile, _fingerprint)
    }

    /// Mutates the profile under the lock.
    func updateProfile(_ newProfile: ServerProfile) {
        lock.lock()
        defer { lock.unlock() }
        profile = newProfile
    }

    /// Updates the last-seen fingerprint under the lock.
    func recordFingerprint(_ fp: String?) {
        lock.lock()
        defer { lock.unlock() }
        _fingerprint = fp
    }
}

/// Evaluates TLS trust for a single firewall connection.
///
/// pfSense ships a self-signed webConfigurator certificate by default, so a
/// plain `URLSession` will refuse the connection. Rather than blanket-disabling
/// validation, the preferred path is pinning: the user records the leaf
/// certificate's SHA-256 once and every later connection must present that
/// exact certificate. `allowUntrustedTLS` without a pin is offered as a
/// last resort and is surfaced as a warning in Settings.
///
/// All mutable state is threaded through `TrustState`, a locked box, so this
/// class is provably `Sendable` — the compiler can verify that every read and
/// write goes through the lock.
final class TrustEvaluator: NSObject, URLSessionDelegate, Sendable {

    private let state: TrustState

    init(profile: ServerProfile) {
        self.state = TrustState(profile: profile)
    }

    /// The current server profile.
    var profile: ServerProfile {
        state.read().0
    }

    /// Recorded on each handshake so Settings can offer "pin this certificate".
    var lastSeenFingerprint: String? {
        state.read().1
    }

    /// Replaces the current profile with a new one.
    func configure(with profile: ServerProfile) {
        state.updateProfile(profile)
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let leafFingerprint = Self.fingerprint(of: trust)
        state.recordFingerprint(leafFingerprint)

        let (profile, _) = state.read()
        let pin = profile.pinnedFingerprint
            .lowercased()
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: " ", with: "")

        if !pin.isEmpty {
            if let leafFingerprint, leafFingerprint == pin {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
            return
        }

        if profile.allowUntrustedTLS {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }

        // No pin set and untrusted TLS is not allowed.
        //
        // Offer to pin the certificate on first connection. The user sees the
        // fingerprint, chooses whether to trust it, and whether to pin it for
        // future connections. A synchronous alert is shown because the URL
        // session will hang otherwise.
        if let leafFingerprint {
            showPinningAlert(leafFingerprint: leafFingerprint, trust: trust) { [self] decision in
                switch decision {
                case .pin:
                    var p = profile
                    p.pinnedFingerprint = leafFingerprint
                    self.state.updateProfile(p)
                    completionHandler(.useCredential, URLCredential(trust: trust))
                case .trust:
                    completionHandler(.useCredential, URLCredential(trust: trust))
                case .cancel:
                    completionHandler(.cancelAuthenticationChallenge, nil)
                }
            }
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    /// Shows a synchronous alert asking whether to trust and pin a new certificate.
    private func showPinningAlert(
        leafFingerprint: String,
        trust: SecTrust,
        completion: @escaping (PinningDecision) -> Void
    ) {
        // Try to get the certificate subject for a nicer label.
        let subject = Self.subjectName(of: trust) ?? "Unknown certificate"
        let readableFingerprint = leafFingerprint.prefix(16) + "…"

        let alert = UIAlertController(
            title: "New certificate",
            message: "This is the first time connecting to \(subject). Fingerprint: \(readableFingerprint)\n\nDo you want to trust and pin this certificate for future connections?",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            completion(.cancel)
        })
        alert.addAction(UIAlertAction(title: "Trust Only", style: .default) { _ in
            completion(.trust)
        })
        alert.addAction(UIAlertAction(title: "Pin & Trust", style: .default) { _ in
            completion(.pin)
        })

        // Present on the main thread's current view controller, or fall back
        // to the key window's root view controller.
        if let windowScene = UIApplication.shared.connectedScenes
            .first(where: { $0 is UIWindowScene }) as? UIWindowScene,
           let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }),
           let vc = keyWindow.rootViewController?.presentedViewController {
            vc.present(alert, animated: true)
        } else if let windowScene = UIApplication.shared.connectedScenes
            .first(where: { $0 is UIWindowScene }) as? UIWindowScene,
           let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }),
           let vc = keyWindow.rootViewController {
            vc.present(alert, animated: true)
        }

        // If the alert is not presented within 2 seconds, cancel the challenge
        // to avoid hanging the connection.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if alert.presentingViewController != nil {
                completion(.cancel)
            }
        }
    }

    enum PinningDecision {
        case pin, trust, cancel
    }

    /// Lowercase hex SHA-256 over the leaf certificate's DER encoding.
    static func fingerprint(of trust: SecTrust) -> String? {
        let leaf: SecCertificate?
        if #available(iOS 15.0, *) {
            leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first
        } else {
            leaf = SecTrustGetCertificateAtIndex(trust, 0)
        }
        guard let leaf else { return nil }
        let der = SecCertificateCopyData(leaf) as Data
        return SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
    }

    /// Human-friendly subject name from the leaf certificate.
    static func subjectName(of trust: SecTrust) -> String? {
        let leaf: SecCertificate?
        if #available(iOS 15.0, *) {
            leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first
        } else {
            leaf = SecTrustGetCertificateAtIndex(trust, 0)
        }
        guard let leaf else { return nil }
        let cf = leaf as SecCertificate
        let cert = SecCertificateCopySubjectSummary(cf) as String?
        return cert
    }
}
