import Foundation
import Observation

/// Simulates whether a proposed firewall rule would match existing traffic patterns.
///
/// Uses the current ARP table, DHCP leases, top talkers, and firewall log to
/// estimate how many existing flows would be affected by the rule.
@MainActor
@Observable
final class RuleSimulationEngine {
    
    struct SimulationResult {
        let estimatedMatches: Int
        let matchedAddresses: [String]
        let matchedPorts: [String]
        let riskLevel: RiskLevel
        let summary: String
        
        enum RiskLevel: String {
            case low = "low_risk"
            case medium = "medium_risk"
            case high = "high_risk"
        }
    }
    
    struct ProposedRule {
        var action: RuleAction
        var source: String
        var destination: String
        var destinationPort: String?
        var `protocol`: ProtocolType
        
        enum RuleAction: String, Codable {
            case pass, block, reject
        }
        
        enum ProtocolType: String, Codable {
            case tcp, udp, icmp, any
        }
    }
    
    private let arpTable: [ARPEntry]
    private let leases: [DHCPLease]
    private let staticMappings: [StaticMapping]
    private let topTalkers: [TopTalker]
    private let firewallLog: [LogLine]
    private let aliases: [FirewallAliasEntry]
    private let rules: [FirewallRule]
    
    init(
        arpTable: [ARPEntry] = [],
        leases: [DHCPLease] = [],
        staticMappings: [StaticMapping] = [],
        topTalkers: [TopTalker] = [],
        firewallLog: [LogLine] = [],
        aliases: [FirewallAliasEntry] = [],
        rules: [FirewallRule] = []
    ) {
        self.arpTable = arpTable
        self.leases = leases
        self.staticMappings = staticMappings
        self.topTalkers = topTalkers
        self.firewallLog = firewallLog
        self.aliases = aliases
        self.rules = rules
    }
    
    func simulate(rule: ProposedRule) -> SimulationResult {
        let matchedAddresses = matchAddresses(rule: rule)
        let matchedPorts = matchPorts(rule: rule)
        let totalMatches = matchedAddresses.count + matchedPorts.count
        
        let riskLevel = assessRisk(matches: totalMatches, rule: rule)
        
        let summary = generateSummary(matches: totalMatches, rule: rule, riskLevel: riskLevel)
        
        return SimulationResult(
            estimatedMatches: max(totalMatches, 1),
            matchedAddresses: matchedAddresses,
            matchedPorts: matchedPorts,
            riskLevel: riskLevel,
            summary: summary
        )
    }
    
    private func matchAddresses(rule: ProposedRule) -> [String] {
        var matched: [String] = []
        let sourceAddresses = resolveAddresses(rule.source)
        let destAddresses = resolveAddresses(rule.destination)
        
        // Check ARP table
        for arp in arpTable {
            if sourceAddresses.contains(arp.ip) || destAddresses.contains(arp.ip) {
                matched.append(arp.ip)
            }
        }
        
        // Check DHCP leases
        for lease in leases {
            if sourceAddresses.contains(lease.ip) || destAddresses.contains(lease.ip) {
                matched.append(lease.ip)
            }
        }
        
        // Check static mappings
        for mapping in staticMappings {
            if sourceAddresses.contains(mapping.ip) || destAddresses.contains(mapping.ip) {
                matched.append(mapping.ip)
            }
        }
        
        // Check top talkers
        for talker in topTalkers {
            if sourceAddresses.contains(talker.ip) || destAddresses.contains(talker.ip) {
                matched.append(talker.ip)
            }
        }
        
        // Check firewall log for recent traffic
        let recentLogLines = Array(firewallLog.prefix(100))
        for log in recentLogLines {
            let matchesSource = log.source.map(sourceAddresses.contains) ?? false
            let matchesDest = log.destination.map(destAddresses.contains) ?? false
            if matchesSource || matchesDest {
                if let source = log.source { matched.append(source) }
                if let destination = log.destination { matched.append(destination) }
            }
        }
        
        return Array(Set(matched))
    }
    
    private func matchPorts(rule: ProposedRule) -> [String] {
        guard let port = rule.destinationPort, port != "any" else { return [] }
        
        var matchedPorts: [String] = []
        
        // Check firewall log for recent traffic on this port
        let recentLogLines = Array(firewallLog.prefix(100))
        for log in recentLogLines {
            if log.filterFields?.destinationPort == port {
                matchedPorts.append(port)
                break
            }
        }
        
        return matchedPorts
    }
    
    private func resolveAddresses(_ address: String) -> [String] {
        var addresses: [String] = []
        
        // Split space-separated addresses
        let parts = address.split(separator: " ").map { String($0) }
        addresses.append(contentsOf: parts)
        
        // Check aliases
        for alias in aliases {
            if alias.name == address || parts.contains(alias.name) {
                addresses.append(contentsOf: alias.addresses)
            }
        }
        
        return addresses
    }
    
    private func assessRisk(matches: Int, rule: ProposedRule) -> SimulationResult.RiskLevel {
        if matches > 50 || rule.action == .block || rule.action == .reject {
            return .high
        } else if matches > 10 || rule.action == .pass {
            return .medium
        } else {
            return .low
        }
    }
    
    private func generateSummary(matches: Int, rule: ProposedRule, riskLevel: SimulationResult.RiskLevel) -> String {
        let actionText = rule.action.rawValue.uppercased()
        let riskText = riskLevel.rawValue.uppercased()
        
        if matches == 0 {
            return "\(actionText) rule for '\(rule.source)' -> '\(rule.destination)' would match 0 existing flows. \(riskText) risk."
        } else {
            return "\(actionText) rule for '\(rule.source)' -> '\(rule.destination)' would match \(matches) existing flows. \(riskText) risk."
        }
    }
}
