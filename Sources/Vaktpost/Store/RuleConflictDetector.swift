import Foundation
import Observation

/// Detects overlapping, redundant, or conflicting firewall rules.
///
/// Analyzes the rule set to find rules that:
/// - Have identical source, destination, port, and protocol (redundant)
/// - Overlap partially (e.g., one allows, one blocks the same traffic)
/// - Are shadowed by earlier rules
@MainActor
@Observable
final class RuleConflictDetector {
    
    struct Conflict: Identifiable {
        let id = UUID()
        let type: ConflictType
        let rule1: FirewallRule
        let rule2: FirewallRule
        let description: String
        
        enum ConflictType: String {
            case redundant = "redundant"
            case overlapping = "overlapping"
            case shadowed = "shadowed"
            case contradictory = "contradictory"
        }
    }
    
    private(set) var conflicts: [Conflict] = []
    
    func analyze(rules: [FirewallRule]) -> [Conflict] {
        var detectedConflicts: [Conflict] = []
        
        for i in 0..<rules.count {
            for j in (i+1)..<rules.count {
                let rule1 = rules[i]
                let rule2 = rules[j]
                
                // Check for redundant rules (identical)
                if areIdentical(rule1, rule2) {
                    detectedConflicts.append(Conflict(
                        type: .redundant,
                        rule1: rule1,
                        rule2: rule2,
                        description: "Rules are identical — one is redundant"
                    ))
                    continue
                }
                
                // Check for overlapping rules
                if areOverlapping(rule1, rule2) {
                    if rule1.type != rule2.type {
                        // Contradictory rules
                        detectedConflicts.append(Conflict(
                            type: .contradictory,
                            rule1: rule1,
                            rule2: rule2,
                            description: "Rules have overlapping traffic but different actions (pass vs block)"
                        ))
                    } else {
                        // Overlapping rules with same action
                        detectedConflicts.append(Conflict(
                            type: .overlapping,
                            rule1: rule1,
                            rule2: rule2,
                            description: "Rules overlap in traffic matching but are not identical"
                        ))
                    }
                }
                
                // Check for shadowed rules
                if isShadowedBy(rule1, rule2) {
                    detectedConflicts.append(Conflict(
                        type: .shadowed,
                        rule1: rule1,
                        rule2: rule2,
                        description: "Rule 1 is completely shadowed by Rule 2 (earlier rule matches all its traffic)"
                    ))
                }
            }
        }
        
        conflicts = detectedConflicts
        return detectedConflicts
    }
    
    private func areIdentical(_ rule1: FirewallRule, _ rule2: FirewallRule) -> Bool {
        rule1.source == rule2.source &&
        rule1.destination == rule2.destination &&
        rule1.destinationSide.port == rule2.destinationSide.port &&
        rule1.proto == rule2.proto &&
        rule1.type == rule2.type
    }
    
    private func areOverlapping(_ rule1: FirewallRule, _ rule2: FirewallRule) -> Bool {
        // Check if source addresses overlap
        let sourcesOverlap = addressesOverlap(rule1.source, rule2.source)
        guard sourcesOverlap else { return false }
        
        // Check if destination addresses overlap
        let destinationsOverlap = addressesOverlap(rule1.destination, rule2.destination)
        guard destinationsOverlap else { return false }
        
        // Check if ports overlap (or either is "any")
        let portsOverlap = rule1.destinationSide.port == "any" || rule2.destinationSide.port == "any" ||
                           rule1.destinationSide.port == rule2.destinationSide.port
        guard portsOverlap else { return false }
        
        // Check if protocols overlap (or either is "any")
        let protocolsOverlap = rule1.proto == "any" || rule2.proto == "any" ||
                              rule1.proto == rule2.proto
        return protocolsOverlap
    }
    
    private func addressesOverlap(_ addr1: String, _ addr2: String) -> Bool {
        // "any" overlaps with everything
        if addr1 == "any" || addr2 == "any" { return true }
        
        // Exact match
        if addr1 == addr2 { return true }
        
        // Space-separated lists - check for any common addresses
        let addrs1 = addr1.split(separator: " ").map { String($0) }
        let addrs2 = addr2.split(separator: " ").map { String($0) }
        
        return !Set(addrs1).isDisjoint(with: Set(addrs2))
    }
    
    private func isShadowedBy(_ rule: FirewallRule, _ shadowingRule: FirewallRule) -> Bool {
        // A rule is shadowed if an earlier rule matches all its traffic
        // Check if shadowing rule's source is "any" or contains rule's source
        let sourceShadowed = shadowingRule.source == "any" || addressesContain(shadowingRule.source, rule.source)
        guard sourceShadowed else { return false }
        
        // Check if shadowing rule's destination is "any" or contains rule's destination
        let destShadowed = shadowingRule.destination == "any" || addressesContain(shadowingRule.destination, rule.destination)
        guard destShadowed else { return false }
        
        // Check if shadowing rule's port is "any" or matches rule's port
        let portShadowed = shadowingRule.destinationSide.port == "any" || shadowingRule.destinationSide.port == rule.destinationSide.port
        guard portShadowed else { return false }
        
        // Check if shadowing rule's protocol is "any" or matches rule's protocol
        let protocolShadowed = shadowingRule.proto == "any" || shadowingRule.proto == rule.proto
        return protocolShadowed
    }
    
    private func addressesContain(_ container: String, _ contained: String) -> Bool {
        if container == "any" { return true }
        if container == contained { return true }
        
        // Check if any address in container matches any address in contained
        let addrs1 = container.split(separator: " ").map { String($0) }
        let addrs2 = contained.split(separator: " ").map { String($0) }
        
        return !Set(addrs1).isDisjoint(with: Set(addrs2))
    }
    
    func reset() {
        conflicts.removeAll()
    }
}
