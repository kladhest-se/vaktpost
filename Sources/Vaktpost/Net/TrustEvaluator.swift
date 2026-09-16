import Foundation
import CryptoKit
import UIKit
import os

private final class TrustState: Sendable {
    private struct Storage: Sendable {
        var profile: ServerProfile
        var fingerprint: String?
        var invalidated = false
    }
    private let lock: OSAllocatedUnfairLock<Storage>

    init(profile: ServerProfile) {
        lock = OSAllocatedUnfairLock(initialState: Storage(profile: profile))
    }

    func read() -> (profile: ServerProfile, fingerprint: String?, invalidated: Bool) {
        lock.withLock { ($0.profile, $0.fingerprint, $0.invalidated) }
    }

    func recordFingerprint(_ fingerprint: String?) {
        lock.withLock { $0.fingerprint = fingerprint }
    }

    func pin(_ fingerprint: String) {
        lock.withLock {
            $0.profile.pinnedFingerprint = fingerprint
            $0.profile.allowUntrustedTLS = false
        }
    }

    func invalidate() {
        lock.withLock { $0.invalidated = true }
    }
}

/// One evaluator belongs to one immutable server binding. Its prompt runs on
/// the main actor; its accepted pin is persisted before credentials are sent.
final class TrustEvaluator: NSObject, URLSessionTaskDelegate, Sendable {
    typealias PinHandler = @MainActor @Sendable (ServerProfile, String) -> Bool
    typealias ObservationHandler = @MainActor @Sendable (ServerProfile, CertificateObservation) -> Void

    private let state: TrustState
    private let owner = UUID()
    private let onPin: PinHandler
    private let onObserve: ObservationHandler?
    private let allowsTrustPrompt: Bool

    init(profile: ServerProfile, allowsTrustPrompt: Bool = true,
         onObserve: ObservationHandler? = nil,
         onPin: @escaping PinHandler) {
        state = TrustState(profile: profile)
        self.onPin = onPin
        self.onObserve = onObserve
        self.allowsTrustPrompt = allowsTrustPrompt
    }

    var lastSeenFingerprint: String? { state.read().fingerprint }

    func invalidate() {
        state.invalidate()
        Task { @MainActor in CertificatePrompt.cancel(owner: owner) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        if error != nil {
            Task { @MainActor in CertificatePrompt.cancel(owner: owner, taskID: task.taskIdentifier) }
        }
    }

    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        invalidate()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let completion = Once<(URLSession.AuthChallengeDisposition, URLCredential?)> {
            completionHandler($0.0, $0.1)
        }
        guard !state.read().invalidated else {
            completion.resolve((.cancelAuthenticationChallenge, nil))
            return
        }
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completion.resolve((.performDefaultHandling, nil))
            return
        }
        let fingerprint = Self.fingerprint(of: trust)
        state.recordFingerprint(fingerprint)
        let profile = state.read().profile
        if let observation = Self.observation(of: trust, fingerprint: fingerprint) {
            Task { @MainActor [onObserve] in onObserve?(profile, observation) }
        }
        let pin = profile.pinnedFingerprint.lowercased()
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: " ", with: "")
        if !pin.isEmpty {
            completion.resolve(fingerprint == pin
                ? (.useCredential, URLCredential(trust: trust))
                : (.cancelAuthenticationChallenge, nil))
            return
        }
        // Certificates already trusted by the system need no exception prompt.
        if SecTrustEvaluateWithError(trust, nil) {
            completion.resolve((.performDefaultHandling, nil))
            return
        }
        guard allowsTrustPrompt, let fingerprint else {
            completion.resolve((.cancelAuthenticationChallenge, nil))
            return
        }
        let subject = Self.subjectName(of: trust) ?? "Unknown certificate"
        let trustCredential = URLCredential(trust: trust)
        Task { @MainActor [self] in
            guard !state.read().invalidated, task.state != .canceling, task.state != .completed else {
                completion.resolve((.cancelAuthenticationChallenge, nil))
                return
            }
            CertificatePrompt.show(owner: owner, taskID: task.taskIdentifier, host: profile.host,
                                   subject: subject, fingerprint: fingerprint) { decision in
                guard !self.state.read().invalidated else {
                    completion.resolve((.cancelAuthenticationChallenge, nil))
                    return
                }
                switch decision {
                case .pin:
                    guard self.onPin(profile, fingerprint) else {
                        completion.resolve((.cancelAuthenticationChallenge, nil))
                        return
                    }
                    self.state.pin(fingerprint)
                    completion.resolve((.useCredential, trustCredential))
                case .cancel:
                    completion.resolve((.cancelAuthenticationChallenge, nil))
                }
            }
        }
    }

    enum PinningDecision: Sendable { case pin, cancel }

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
        return SecCertificateCopySubjectSummary(leaf as SecCertificate) as String?
    }

    static func observation(of trust: SecTrust, fingerprint: String?) -> CertificateObservation? {
        let leaf: SecCertificate?
        if #available(iOS 15.0, *) {
            leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first
        } else {
            leaf = SecTrustGetCertificateAtIndex(trust, 0)
        }
        guard let leaf, let fingerprint else { return nil }

        let der = SecCertificateCopyData(leaf) as Data
        let metadata = DERCertificateMetadata.parse(der)

        return CertificateObservation(
            fingerprint: fingerprint,
            subject: subjectName(of: trust) ?? "Unknown certificate",
            issuer: metadata?.issuer,
            validFrom: metadata?.validFrom,
            validUntil: metadata?.validUntil,
            systemTrusted: SecTrustEvaluateWithError(trust, nil),
            observedAt: Date()
        )
    }
}

/// All controller access and terminal events are serialized by the main actor.
@MainActor
private enum CertificatePrompt {
    private struct Pending {
        let alert: UIAlertController
        let taskID: Int
        let completion: @MainActor (TrustEvaluator.PinningDecision) -> Void
    }
    private static var pending: [UUID: Pending] = [:]

    static func show(owner: UUID, taskID: Int, host: String, subject: String, fingerprint: String,
                     completion: @escaping @MainActor (TrustEvaluator.PinningDecision) -> Void) {
        guard pending[owner] == nil,
              let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            completion(.cancel)
            return
        }
        var presenter = root
        while let presented = presenter.presentedViewController { presenter = presented }
        guard presenter.viewIfLoaded?.window != nil,
              !presenter.isBeingDismissed, !presenter.isBeingPresented,
              !(presenter is UIAlertController) else {
            completion(.cancel)
            return
        }
        let alert = UIAlertController(
            title: "Trust certificate?",
            message: "Server: \(host)\nCertificate: \(subject)\nSHA-256: \(fingerprint)\n\nVerify this fingerprint with your firewall before trusting it.",
            preferredStyle: .alert)
        pending[owner] = Pending(alert: alert, taskID: taskID, completion: completion)
        for (title, style, decision) in [
            ("Cancel", UIAlertAction.Style.cancel, TrustEvaluator.PinningDecision.cancel),
            ("Pin & Trust", .default, .pin)
        ] {
            alert.addAction(UIAlertAction(title: title, style: style) { _ in
                finish(owner: owner, decision: decision)
            })
        }
        presenter.present(alert, animated: true) {
            if alert.presentingViewController == nil { cancel(owner: owner) }
        }
        // There is no short decision timer. If presentation was rejected,
        // resolve immediately; an actually displayed alert stays interactive.
        if alert.presentingViewController == nil { cancel(owner: owner) }
    }

    private static func finish(owner: UUID, decision: TrustEvaluator.PinningDecision) {
        guard let value = pending.removeValue(forKey: owner) else { return }
        value.completion(decision)
    }

    static func cancel(owner: UUID, taskID: Int? = nil) {
        guard let value = pending[owner], taskID == nil || value.taskID == taskID else { return }
        pending[owner] = nil
        value.alert.dismiss(animated: false)
        value.completion(.cancel)
    }
}
