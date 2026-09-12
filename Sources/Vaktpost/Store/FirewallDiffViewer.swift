import Foundation
import Observation

/// Compares firewall configuration snapshots to detect changes.
///
/// Stores historical snapshots and provides diff reports showing added,
/// removed, or modified rules, aliases, port forwards, etc.
@MainActor
@Observable
final class FirewallDiffViewer {
    
    struct ConfigSnapshot: Identifiable, Codable, Hashable {
        /// Derived from the snapshot, not generated.
        ///
        /// This was `let id = UUID()`, which a decoder cannot overwrite — so
        /// every snapshot read back from disk got a new identity. Two decodes
        /// of one snapshot compared unequal, `ForEach` treated the same row as
        /// a different row after a relaunch, and any diff that matched
        /// snapshots by identity matched nothing.
        ///
        /// The timestamp and the counts are what a snapshot *is*, so they are
        /// what identifies it, and it round-trips for free.
        var id: String {
            "\(timestamp.timeIntervalSince1970)-\(ruleCount)-\(aliasCount)-\(portForwardCount)"
        }

        let timestamp: Date
        let ruleCount: Int
        let aliasCount: Int
        let portForwardCount: Int
        let ruleFingerprints: [String]
        let aliasFingerprints: [String]
        let portForwardFingerprints: [String]
        
        var description: String {
            "Snapshot from \(timestamp.formatted(date: .abbreviated, time: .shortened))"
        }
    }
    
    struct DiffResult: Identifiable {
        let id = UUID()
        let type: DiffType
        let before: ConfigSnapshot
        let after: ConfigSnapshot
        let addedRules: Int
        let removedRules: Int
        let addedAliases: Int
        let removedAliases: Int
        let addedPortForwards: Int
        let removedPortForwards: Int
        
        enum DiffType: String {
            case rules = "rules"
            case aliases = "aliases"
            case portForwards = "port_forwards"
            case full = "full"
        }
        
        var summary: String {
            var parts: [String] = []
            if addedRules > 0 { parts.append("+\(addedRules) rules") }
            if removedRules > 0 { parts.append("-\(removedRules) rules") }
            if addedAliases > 0 { parts.append("+\(addedAliases) aliases") }
            if removedAliases > 0 { parts.append("-\(removedAliases) aliases") }
            if addedPortForwards > 0 { parts.append("+\(addedPortForwards) port forwards") }
            if removedPortForwards > 0 { parts.append("-\(removedPortForwards) port forwards") }
            return parts.isEmpty ? "No changes detected" : parts.joined(separator: ", ")
        }
    }
    
    private(set) var snapshots: [ConfigSnapshot] = []
    private(set) var lastDiff: DiffResult?
    
    private let maxSnapshots = 20
    
    func snapshot(rules: [FirewallRule], aliases: [FirewallAliasEntry], portForwards: [PortForward]) {
        let ruleFingerprints = rules.map { fingerprint($0) }
        let aliasFingerprints = aliases.map { fingerprint($0) }
        let portForwardFingerprints = portForwards.map { fingerprint($0) }
        
        let snapshot = ConfigSnapshot(
            timestamp: Date(),
            ruleCount: rules.count,
            aliasCount: aliases.count,
            portForwardCount: portForwards.count,
            ruleFingerprints: ruleFingerprints,
            aliasFingerprints: aliasFingerprints,
            portForwardFingerprints: portForwardFingerprints
        )
        
        snapshots.append(snapshot)
        if snapshots.count > maxSnapshots {
            snapshots.removeFirst(snapshots.count - maxSnapshots)
        }
    }
    
    func compareLatest() -> DiffResult? {
        guard snapshots.count >= 2 else { return nil }
        
        let before = snapshots[snapshots.count - 2]
        let after = snapshots[snapshots.count - 1]
        
        let beforeRules = Set(before.ruleFingerprints)
        let afterRules = Set(after.ruleFingerprints)
        let beforeAliases = Set(before.aliasFingerprints)
        let afterAliases = Set(after.aliasFingerprints)
        let beforePFs = Set(before.portForwardFingerprints)
        let afterPFs = Set(after.portForwardFingerprints)
        
        return DiffResult(
            type: .full,
            before: before,
            after: after,
            addedRules: afterRules.subtracting(beforeRules).count,
            removedRules: beforeRules.subtracting(afterRules).count,
            addedAliases: afterAliases.subtracting(beforeAliases).count,
            removedAliases: beforeAliases.subtracting(afterAliases).count,
            addedPortForwards: afterPFs.subtracting(beforePFs).count,
            removedPortForwards: beforePFs.subtracting(afterPFs).count
        )
    }
    
    func compare(_ earlier: ConfigSnapshot, with later: ConfigSnapshot) -> DiffResult? {
        guard earlier.timestamp < later.timestamp else { return nil }
        
        return DiffResult(
            type: .full,
            before: earlier,
            after: later,
            addedRules: max(0, later.ruleCount - earlier.ruleCount),
            removedRules: max(0, earlier.ruleCount - later.ruleCount),
            addedAliases: max(0, later.aliasCount - earlier.aliasCount),
            removedAliases: max(0, earlier.aliasCount - later.aliasCount),
            addedPortForwards: max(0, later.portForwardCount - earlier.portForwardCount),
            removedPortForwards: max(0, earlier.portForwardCount - later.portForwardCount)
        )
    }
    
    func fingerprint(_ rule: FirewallRule) -> String {
        "\(rule.source)|\(rule.destination)|\(rule.destinationSide.port ?? "any")|\(rule.proto ?? "any")|\(rule.type)"
    }
    
    func fingerprint(_ entry: FirewallAliasEntry) -> String {
        "\(entry.name)|\(entry.addresses.joined(separator: ","))"
    }
    
    func fingerprint(_ pf: PortForward) -> String {
        "\(pf.interfaceName)|\(pf.proto ?? "any")|\(pf.sourceSide.text)|\(pf.localPort ?? "any")"
    }
    
    func reset() {
        snapshots.removeAll()
        lastDiff = nil
    }
}
