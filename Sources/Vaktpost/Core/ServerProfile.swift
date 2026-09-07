import Foundation
import Security
import os.log

private let keychainLog = OSLog(subsystem: "se.kladhest.vaktpost", category: "Keychain")

// MARK: - Profile

struct ServerProfile: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    /// Scheme + host + optional port, e.g. "https://fw01.example.se" or "https://10.0.0.1:8443"
    var baseURL: String = ""
    var label: String = ""
    /// Accept a certificate that does not chain to a trusted root. Weaker than
    /// pinning; see TrustEvaluator.
    var allowUntrustedTLS: Bool = false
    /// Lowercase hex SHA-256 of the leaf certificate's DER.
    var pinnedFingerprint: String = ""
    /// webConfigurator username. The account needs the "System - HA node sync"
    /// privilege, which is administrator-equivalent — see SECURITY.md.
    /// Empty rather than "admin".
    ///
    /// A pre-filled username is a suggestion, and the suggestion here was the
    /// account nobody should be using — the setup notes ask for a dedicated
    /// one, and the field should not argue with them.
    var username: String = ""
    var refreshSeconds: Int = 30
    var logLimit: Int = 100

    var isConfigured: Bool { URL(string: baseURL)?.host != nil }
    var host: String { URL(string: baseURL)?.host ?? baseURL }
    var displayName: String { label.isEmpty ? host : label }

    var hasCredentials: Bool { !username.isEmpty && Keychain.password(for: id) != nil }
    var isUsable: Bool { isConfigured && hasCredentials }

    /// Normalises a user-typed URL: adds https://, strips trailing slashes.
    mutating func normalize() {
        baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !baseURL.isEmpty, !baseURL.lowercased().hasPrefix("http") {
            baseURL = "https://" + baseURL
        }
        while baseURL.hasSuffix("/") { baseURL.removeLast() }
    }
}

// MARK: - Registry

/// Holds every configured firewall and which one is on screen.
@MainActor
final class ServerRegistry: ObservableObject {

    private static let listKey = "servers.list"
    private static let activeKey = "servers.active"

    @Published private(set) var servers: [ServerProfile] = []
    @Published private(set) var activeID: UUID?

    var active: ServerProfile? {
        guard let activeID else { return servers.first }
        return servers.first { $0.id == activeID } ?? servers.first
    }

    var hasUsableServer: Bool { active?.isUsable ?? false }

    /// Where profiles are stored.
    ///
    /// Injectable so tests can use an isolated suite. They previously wrote to
    /// `UserDefaults.standard`, which in a host-app test bundle *is* the app's
    /// own defaults on that simulator — so "the registry starts clean with no
    /// stored data" passed on a fresh simulator and failed on one where
    /// somebody had configured a firewall. A test that depends on the state of
    /// the machine running it is worse than no test.
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let d = defaults
        if let data = d.data(forKey: Self.listKey),
           let list = try? JSONDecoder().decode([ServerProfile].self, from: data) {
            servers = list
        } else if let data = d.data(forKey: "server.profile"),
                  var legacy = try? JSONDecoder().decode(ServerProfile.self, from: data),
                  legacy.isConfigured {
            // Migrate the single-server layout used before multi-firewall support.
            legacy.id = UUID()
            servers = [legacy]
            // A stored API key is deliberately not carried over. It is not a
            // password, and this build authenticates as a webConfigurator user
            // — reusing it would fail with a confusing 401 rather than asking
            // for what is now needed.
            Keychain.deleteLegacy()
            d.removeObject(forKey: "server.profile")
            persist()
        }
        if let raw = d.string(forKey: Self.activeKey), let uuid = UUID(uuidString: raw) {
            activeID = uuid
        }
        if activeID == nil { activeID = servers.first?.id }
    }

    // MARK: Mutation

    func upsert(_ profile: ServerProfile) {
        var p = profile
        p.normalize()
        if let idx = servers.firstIndex(where: { $0.id == p.id }) {
            servers[idx] = p
        } else {
            servers.append(p)
        }
        if activeID == nil { activeID = p.id }
        persist()
    }

    func remove(_ profile: ServerProfile) {
        Keychain.delete(for: profile.id)
        servers.removeAll { $0.id == profile.id }
        if activeID == profile.id { activeID = servers.first?.id }
        persist()
    }

    func setActive(_ profile: ServerProfile) {
        activeID = profile.id
        persist()
    }

    private func persist() {
        let d = defaults
        if let data = try? JSONEncoder().encode(servers) {
            d.set(data, forKey: Self.listKey)
        }
        if let activeID {
            d.set(activeID.uuidString, forKey: Self.activeKey)
        } else {
            d.removeObject(forKey: Self.activeKey)
        }
    }
}

// MARK: - Keychain

enum KeychainError: LocalizedError {
    case emptyKey
    case keychainError(OSStatus)

    var errorDescription: String? {
        switch self {
        case .emptyKey:
            return "API key cannot be empty."
        case .keychainError(let status):
            switch status {
            case -25293: // errSecUnlockedDeviceRequired
                return "Save failed: device is locked. Unlock and try again."
            case -25308: // errSecWriteProhibited
                return "Save failed: storage is not available."
            case -25299: // errSecUserCanceled
                return "Save cancelled."
            default:
                return "Save failed (keychain error \(status))."
            }
        }
    }
}

/// One keychain item per firewall, keyed by profile UUID. Accessible after
/// first unlock so a background refresh on a locked device still works.
/// One keychain item per firewall, holding a webConfigurator password.
///
/// This is a heavier secret than the API key it replaced. A key was scoped to
/// the REST API and revocable on its own; this password also opens the
/// webConfigurator and SSH, and cannot be revoked without changing it
/// everywhere it is used. The service name is new so an upgrade does not
/// silently reinterpret an old API key as a password.
enum Keychain {
    private static let service = "se.kladhest.vaktpost.password"

    /// Where the REST build kept its API keys.
    ///
    /// Named separately because the service string changed with the transport,
    /// and a rename alone would leave the old key in the keychain forever:
    /// `deleteLegacy()` would look under the new service, find nothing, and
    /// report success. A credential that outlives the build that used it is
    /// the kind of thing nobody notices until it turns up in a keychain dump.
    private static let legacyService = "se.kladhest.vaktpost.apikey"
    private static let legacyAccount = "default"

    static func setPassword(_ key: String, for id: UUID) -> Result<Void, KeychainError> {
        delete(for: id)
        guard !key.isEmpty, let data = key.data(using: .utf8) else {
            return .failure(.emptyKey)
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess || status == errSecDuplicateItem {
            return .success(())
        }
        os_log(.error, log: keychainLog, "SecItemAdd failed: %{public}d", status)
        return .failure(.keychainError(status))
    }

    static func password(for id: UUID) -> String? { read(account: id.uuidString) }

    static func delete(for id: UUID) { delete(account: id.uuidString) }

    static func legacyAPIKey() -> String? { read(account: legacyAccount, service: legacyService) }
    static func deleteLegacy() { delete(account: legacyAccount, service: legacyService) }

    // MARK: Internals

    private static func read(account: String, service: String = service) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func delete(account: String, service: String = service) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            os_log(.error, log: keychainLog, "SecItemDelete failed: %{public}d", status)
        }
    }
}
