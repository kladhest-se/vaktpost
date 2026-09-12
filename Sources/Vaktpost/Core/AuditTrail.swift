import CryptoKit
import Foundation
import Observation
import Security

/// The result of reading the affected state back after pfSense accepted a write.
enum AuditVerification: String, Codable, Sendable {
    case pending
    case verified
    case readBack = "read_back"
    case mismatch
    case unavailable
    case outcomeUnknown = "outcome_unknown"
}

/// High-level categories of firewall writes.
enum AuditAction: String, Codable, Sendable {
    case addRule = "add_rule"
    case editRule = "edit_rule"
    case deleteRule = "delete_rule"
    case reorderRules = "reorder_rules"
    case addAlias = "add_alias"
    case editAlias = "edit_alias"
    case deleteAlias = "delete_alias"
    case addPortForward = "add_port_forward"
    case editPortForward = "edit_port_forward"
    case deletePortForward = "delete_port_forward"
    case restartService = "restart_service"
    case reloadFirewall = "reload_firewall"
    case flushStates = "flush_states"
    case backupConfig = "backup_config"
    case restoreConfig = "restore_config"
    case quickBlock = "quick_block"
    case other = "other"
}

enum AuditTrailError: LocalizedError {
    case keyUnavailable(OSStatus)
    case malformedCiphertext
    case persistenceFailed(String)

    var errorDescription: String? {
        switch self {
        case .keyUnavailable(let status):
            return "The protected audit key is unavailable (Keychain status \(status))."
        case .malformedCiphertext:
            return "The protected audit file could not be opened."
        case .persistenceFailed(let detail):
            return "The audit record could not be saved: \(detail)"
        }
    }
}

/// Durable, encrypted, per-firewall records of every administrative attempt.
///
/// A pending entry is committed before transport begins. Completion updates
/// that same entry with response and verification state. A write is refused if
/// the pending record cannot be persisted, so successful firewall changes can
/// never outrun their audit record.
@MainActor
@Observable
final class AuditTrail {

    struct Entry: Identifiable, Codable, Sendable {
        let id: UUID
        let firewallID: UUID
        let timestamp: Date
        let action: AuditAction
        let summary: String
        let target: String?
        let preview: String
        let beforeHash: String?
        var afterHash: String?
        var responseStatus: String
        var verification: AuditVerification
        var verificationDetail: String?
        var completedAt: Date?
    }

    private(set) var entries: [Entry] = []
    private(set) var persistenceError: String?
    private(set) var activeFirewallID: UUID?
    private(set) var retentionLimit: Int

    private let storageDirectory: URL
    private let injectedKeyData: Data?
    private let defaults: UserDefaults
    private static let retentionKey = "audit.retentionLimit"
    static let retentionOptions = [100, 500, 1_000]

    init(storageDirectory: URL? = nil,
         encryptionKeyData: Data? = nil,
         defaults: UserDefaults = .standard) {
        self.storageDirectory = storageDirectory ?? Self.defaultStorageDirectory
        self.injectedKeyData = encryptionKeyData
        self.defaults = defaults
        let savedLimit = defaults.integer(forKey: Self.retentionKey)
        retentionLimit = Self.retentionOptions.contains(savedLimit) ? savedLimit : 500
    }

    /// Switch the visible trail without mixing records from two firewalls.
    func bind(to firewallID: UUID?) {
        activeFirewallID = firewallID
        persistenceError = nil
        guard let firewallID else {
            entries = []
            return
        }
        do {
            entries = try load(for: firewallID)
        } catch {
            entries = []
            persistenceError = error.localizedDescription
        }
    }

    /// Persist a pending entry before a network mutation starts.
    @discardableResult
    func begin(id: UUID,
               firewallID: UUID,
               action: AuditAction,
               summary: String,
               target: String?,
               preview: String,
               beforeHash: String?) throws -> Entry {
        var records = try records(for: firewallID)
        let entry = Entry(
            id: id,
            firewallID: firewallID,
            timestamp: Date(),
            action: action,
            summary: summary,
            target: target,
            preview: preview,
            beforeHash: beforeHash,
            afterHash: nil,
            responseStatus: "pending",
            verification: .pending,
            verificationDetail: nil,
            completedAt: nil
        )
        records.append(entry)
        if records.count > retentionLimit {
            records.removeFirst(records.count - retentionLimit)
        }
        try persist(records, for: firewallID)
        if activeFirewallID == firewallID { entries = records }
        return entry
    }

    /// Finish the operation identified by `id`, retaining the pending record
    /// if persistence fails so the incomplete attempt remains visible.
    func finish(id: UUID,
                firewallID: UUID,
                responseStatus: String,
                verification: AuditVerification,
                detail: String?,
                afterHash: String?) throws {
        var records = try records(for: firewallID)
        guard let index = records.firstIndex(where: { $0.id == id }) else {
            throw AuditTrailError.persistenceFailed("the pending operation was not found")
        }
        records[index].responseStatus = responseStatus
        records[index].verification = verification
        records[index].verificationDetail = detail
        records[index].afterHash = afterHash
        records[index].completedAt = Date()
        try persist(records, for: firewallID)
        if activeFirewallID == firewallID { entries = records }
    }

    func entriesSince(_ date: Date) -> [Entry] {
        entries.filter { $0.timestamp >= date }
    }

    func setRetentionLimit(_ limit: Int) throws {
        guard Self.retentionOptions.contains(limit) else { return }
        retentionLimit = limit
        defaults.set(limit, forKey: Self.retentionKey)
        guard let activeFirewallID, entries.count > limit else { return }
        entries.removeFirst(entries.count - limit)
        try persist(entries, for: activeFirewallID)
    }

    /// A shareable record that omits firewall names, targets, previews and
    /// verification details. Full records remain encrypted on this device.
    func redactedExport() -> String {
        let formatter = ISO8601DateFormatter()
        let header = "timestamp\toperation_id\taction\tresponse\tverification\tbefore_hash\tafter_hash"
        let rows = entries.map { entry in
            [
                formatter.string(from: entry.timestamp),
                entry.id.uuidString.lowercased(),
                entry.action.rawValue,
                entry.responseStatus,
                entry.verification.rawValue,
                entry.beforeHash ?? "",
                entry.afterHash ?? ""
            ].joined(separator: "\t")
        }
        return ([header] + rows).joined(separator: "\n")
    }

    /// Clears the active firewall's records only.
    func clear() throws {
        guard let activeFirewallID else { return }
        try persist([], for: activeFirewallID)
        entries = []
    }

    /// Removes local audit data when its firewall profile is removed.
    func delete(for firewallID: UUID) {
        try? FileManager.default.removeItem(at: fileURL(for: firewallID))
        if activeFirewallID == firewallID {
            activeFirewallID = nil
            entries = []
        }
    }

    static func hash(_ value: String?) -> String? {
        guard let value else { return nil }
        return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Storage

    private static var defaultStorageDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("vaktpost/audit", isDirectory: true)
    }

    private func fileURL(for firewallID: UUID) -> URL {
        storageDirectory.appendingPathComponent("\(firewallID.uuidString.lowercased()).audit")
    }

    private func records(for firewallID: UUID) throws -> [Entry] {
        if activeFirewallID == firewallID, persistenceError == nil { return entries }
        return try load(for: firewallID)
    }

    private func load(for firewallID: UUID) throws -> [Entry] {
        let url = fileURL(for: firewallID)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let sealed = try Data(contentsOf: url)
            guard let box = try? AES.GCM.SealedBox(combined: sealed) else {
                throw AuditTrailError.malformedCiphertext
            }
            let plaintext = try AES.GCM.open(box, using: try encryptionKey())
            return try JSONDecoder().decode([Entry].self, from: plaintext)
        } catch let error as AuditTrailError {
            throw error
        } catch {
            throw AuditTrailError.persistenceFailed(error.localizedDescription)
        }
    }

    private func persist(_ records: [Entry], for firewallID: UUID) throws {
        do {
            try FileManager.default.createDirectory(
                at: storageDirectory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
            let plaintext = try JSONEncoder().encode(records)
            let sealed = try AES.GCM.seal(plaintext, using: try encryptionKey())
            guard let combined = sealed.combined else { throw AuditTrailError.malformedCiphertext }
            try combined.write(to: fileURL(for: firewallID), options: [.atomic, .completeFileProtection])
            persistenceError = nil
        } catch let error as AuditTrailError {
            persistenceError = error.localizedDescription
            throw error
        } catch {
            let wrapped = AuditTrailError.persistenceFailed(error.localizedDescription)
            persistenceError = wrapped.localizedDescription
            throw wrapped
        }
    }

    private func encryptionKey() throws -> SymmetricKey {
        if let injectedKeyData { return SymmetricKey(data: injectedKeyData) }
        return SymmetricKey(data: try AuditKeychain.keyData())
    }
}

private enum AuditKeychain {
    private static let service = "se.kladhest.vaktpost.audit-key"
    private static let account = "local-audit-v1"

    static func keyData() throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let readStatus = SecItemCopyMatching(query as CFDictionary, &item)
        if readStatus == errSecSuccess, let data = item as? Data { return data }
        guard readStatus == errSecItemNotFound else {
            throw AuditTrailError.keyUnavailable(readStatus)
        }

        var bytes = Data(count: 32)
        let randomStatus = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, 32, buffer.baseAddress!)
        }
        guard randomStatus == errSecSuccess else {
            throw AuditTrailError.keyUnavailable(randomStatus)
        }
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: bytes,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        if addStatus == errSecSuccess { return bytes }
        if addStatus == errSecDuplicateItem { return try keyData() }
        throw AuditTrailError.keyUnavailable(addStatus)
    }
}
