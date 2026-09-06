import Foundation
import CryptoKit

/// pfSense ships a self-signed webConfigurator certificate by default, so a
/// plain URLSession will refuse the connection. Rather than blanket-disabling
/// validation, the preferred path is pinning: the user records the leaf
/// certificate's SHA-256 once and every later connection must present that
/// exact certificate. `allowUntrustedTLS` without a pin is offered as a
/// last resort and is surfaced as a warning in Settings.
final class TrustEvaluator: NSObject, URLSessionDelegate, @unchecked Sendable {

    private let lock = NSLock()
    private var _profile: ServerProfile
    private var _lastSeenFingerprint: String?

    init(profile: ServerProfile) {
        self._profile = profile
    }

    var profile: ServerProfile {
        get { lock.lock(); defer { lock.unlock() }; return _profile }
        set { lock.lock(); _profile = newValue; lock.unlock() }
    }

    /// Recorded on each handshake so Settings can offer "pin this certificate".
    private(set) var lastSeenFingerprint: String? {
        get { lock.lock(); defer { lock.unlock() }; return _lastSeenFingerprint }
        set { lock.lock(); _lastSeenFingerprint = newValue; lock.unlock() }
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

        let profile = self.profile
        let leafFingerprint = Self.fingerprint(of: trust)
        lastSeenFingerprint = leafFingerprint

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

        completionHandler(.performDefaultHandling, nil)
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
}
