import Foundation
import Security

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
    var refreshSeconds: Int = 30
    var logLimit: Int = 100

    var isConfigured: Bool { URL(string: baseURL)?.host != nil }
    var host: String { URL(string: baseURL)?.host ?? baseURL }
    var displayName: String { label.isEmpty ? host : label }

    var hasKey: Bool { Keychain.apiKey(for: id) != nil }
    var isUsable: Bool { isConfigured && hasKey }

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

    init() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: Self.listKey),
           let list = try? JSONDecoder().decode([ServerProfile].self, from: data) {
            servers = list
        } else if let data = d.data(forKey: "server.profile"),
                  var legacy = try? JSONDecoder().decode(ServerProfile.self, from: data),
                  legacy.isConfigured {
            // Migrate the single-server layout used before multi-firewall support.
            legacy.id = UUID()
            servers = [legacy]
            if let key = Keychain.legacyAPIKey() {
                Keychain.setAPIKey(key, for: legacy.id)
                Keychain.deleteLegacy()
            }
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
        let d = UserDefaults.standard
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

/// One keychain item per firewall, keyed by profile UUID. Accessible after
/// first unlock so a background refresh on a locked device still works.
enum Keychain {
    private static let service = "se.kladhest.vaktpost.apikey"
    private static let legacyAccount = "default"

    static func setAPIKey(_ key: String, for id: UUID) {
        delete(for: id)
        guard !key.isEmpty, let data = key.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func apiKey(for id: UUID) -> String? { read(account: id.uuidString) }

    static func delete(for id: UUID) { delete(account: id.uuidString) }

    static func legacyAPIKey() -> String? { read(account: legacyAccount) }
    static func deleteLegacy() { delete(account: legacyAccount) }

    // MARK: Internals

    private static func read(account: String) -> String? {
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

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
