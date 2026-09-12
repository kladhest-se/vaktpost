import Foundation
import Observation

/// Tracks every write operation performed on a firewall for audit and rollback.
///
/// Each entry records what was done, when, and optionally a snapshot of the
/// state before the change so it can be reversed. The trail is kept in memory
/// only — on relaunch it is discarded — because persisting it would require
/// writing to disk and we want to avoid leaking firewall credentials or
/// configuration details.
@MainActor
@Observable
final class AuditTrail {

    struct Entry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let action: Action
        let summary: String
        let target: String?
        let before: String?
        let after: String?

        /// High-level categories of firewall writes.
        enum Action: String {
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
    }

    private(set) var entries: [Entry] = []

    /// How many entries to keep before evicting the oldest.
    private static let maxEntries = 200

    /// Log a write operation.
    ///
    /// - Parameters:
    ///   - action: The category of operation.
    ///   - summary: Human-readable description.
    ///   - target: What was affected (e.g. rule number, alias name).
    ///   - before: Snapshot of state before the change (JSON).
    ///   - after: Snapshot of state after the change (JSON).
    func log(action: Entry.Action,
             summary: String,
             target: String? = nil,
             before: String? = nil,
             after: String? = nil) {
        let entry = Entry(
            timestamp: Date(),
            action: action,
            summary: summary,
            target: target,
            before: before,
            after: after
        )
        entries.append(entry)
        if entries.count > Self.maxEntries {
            entries.removeFirst(entries.count - Self.maxEntries)
        }
    }

    /// Returns entries since the given date.
    func entriesSince(_ date: Date) -> [Entry] {
        entries.filter { $0.timestamp >= date }
    }

    /// Clears the trail.
    func clear() {
        entries.removeAll()
    }
}
