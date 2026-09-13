import Foundation

/// Where a rule sits, and what above it already catches its traffic.
///
/// This replaces `RuleConflictDetector`, which was referenced by nothing and
/// could not have been trusted if it had been. Three faults, any one of which
/// would have made it noise:
///
///   - It asked `isShadowedBy(rules[i], rules[j])` with `i < j` — whether the
///     *earlier* rule was shadowed by the *later* one. Shadowing runs the
///     other way. Every finding it produced pointed at the wrong rule.
///   - It never compared interfaces. On a firewall with fifteen of them, every
///     pair of `any → any` rules on unrelated interfaces reads as
///     contradictory, and the screen fills with pairs that can never interact.
///   - It ignored `disabled`. A rule that is not evaluated cannot shadow
///     anything.
///
/// What is here instead is deliberately smaller. It answers one question about
/// one rule — what precedes it on its own interface that would match the same
/// traffic first — and says nothing when it cannot prove the answer.
///
/// That restraint is the design. A warning shown immediately before a write is
/// read by somebody about to change a firewall, and one false alarm there
/// teaches them to dismiss the next one. Silence is cheap; a wrong warning at
/// that moment is not.
enum RulePlacement {

    struct Finding: Identifiable {
        enum Kind {
            /// An earlier rule matches everything this one would, so this rule
            /// is never reached.
            case shadowed
            /// An earlier rule matches everything this one would, and does the
            /// opposite. Worth separating: the traffic is being handled, just
            /// not the way this rule says.
            case contradicted
            /// Identical in every field this app can compare.
            case duplicate
        }

        var id: String { "\(kind)-\(otherPosition)" }
        let kind: Kind
        let other: FirewallRule
        /// 1-based position of the other rule among its interface's rules.
        let otherPosition: Int

        var headline: String {
            switch kind {
            case .shadowed: return "Never reached"
            case .contradicted: return "Already handled, the other way"
            case .duplicate: return "Identical to an earlier rule"
            }
        }

        func detail(action: String) -> String {
            switch kind {
            case .shadowed:
                return "Rule \(otherPosition) above already matches everything this one would, so this rule is never evaluated."
            case .contradicted:
                return "Rule \(otherPosition) above matches everything this one would and \(other.type)es it. This traffic is decided there, not here."
            case .duplicate:
                return "Rule \(otherPosition) above is identical in every field this app compares, and it \(other.type)es first."
            }
        }
    }

    struct Placement {
        /// 1-based position among the rules on this rule's interface, or nil
        /// when the rule is new and would be appended.
        let position: Int?
        /// How many rules that interface has, counting this one.
        let total: Int
        let findings: [Finding]

        var isNew: Bool { position == nil }
    }

    /// Analyse one rule against the ruleset it lives in.
    ///
    /// Only rules on the same interface, only those before it, only enabled
    /// ones. pfSense generates filter rules as `quick`, so the first match
    /// decides — which is what makes "what is above it" the whole question.
    static func analyse(_ rule: FirewallRule, in all: [FirewallRule]) -> Placement {
        let onInterface = all.filter { $0.interfaceName == rule.interfaceName }
        let index = onInterface.firstIndex { $0.id == rule.id }

        // A new rule is appended, so everything already there precedes it.
        let preceding = index.map { Array(onInterface[..<$0]) } ?? onInterface

        var findings: [Finding] = []
        for (offset, earlier) in preceding.enumerated() {
            guard !earlier.disabled else { continue }
            let position = offset + 1

            if identical(earlier, rule) {
                findings.append(Finding(kind: .duplicate, other: earlier, otherPosition: position))
                // One finding per rule. A duplicate is also a shadow, and
                // saying both about the same pair is padding.
                continue
            }
            if covers(earlier, rule) {
                findings.append(Finding(kind: earlier.type == rule.type ? .shadowed : .contradicted,
                                        other: earlier, otherPosition: position))
            }
        }

        return Placement(position: index.map { $0 + 1 },
                         total: index == nil ? onInterface.count + 1 : onInterface.count,
                         findings: findings)
    }

    // MARK: Matching

    private static func identical(_ lhs: FirewallRule, _ rhs: FirewallRule) -> Bool {
        lhs.type == rhs.type
            && normalised(lhs.sourceSide.address) == normalised(rhs.sourceSide.address)
            && normalised(lhs.destinationSide.address) == normalised(rhs.destinationSide.address)
            && normalised(lhs.sourceSide.port) == normalised(rhs.sourceSide.port)
            && normalised(lhs.destinationSide.port) == normalised(rhs.destinationSide.port)
            && normalised(lhs.proto) == normalised(rhs.proto)
            && (lhs.ipProtocol ?? "inet") == (rhs.ipProtocol ?? "inet")
    }

    /// Does `earlier` match everything `later` would?
    ///
    /// Conservative by construction: every dimension must be provably covered,
    /// and the only things this app can prove are "the earlier rule says any"
    /// and "both say the same thing". It does no subnet arithmetic and does
    /// not resolve aliases, so a `/24` above a host in it is *not* reported —
    /// that would be a guess, and a guess here is a false alarm in front of a
    /// write.
    private static func covers(_ earlier: FirewallRule, _ later: FirewallRule) -> Bool {
        guard (earlier.ipProtocol ?? "inet") == (later.ipProtocol ?? "inet")
                || (earlier.ipProtocol ?? "inet") == "inet46" else { return false }
        return dimensionCovers(earlier.proto, later.proto)
            && dimensionCovers(earlier.sourceSide.address, later.sourceSide.address)
            && dimensionCovers(earlier.sourceSide.port, later.sourceSide.port)
            && dimensionCovers(earlier.destinationSide.address, later.destinationSide.address)
            && dimensionCovers(earlier.destinationSide.port, later.destinationSide.port)
    }

    private static func dimensionCovers(_ earlier: String?, _ later: String?) -> Bool {
        let wide = normalised(earlier)
        let narrow = normalised(later)
        if wide == "any" { return true }
        return wide == narrow
    }

    /// Empty, nil and "any" are one thing, and case is not meaningful.
    private static func normalised(_ value: String?) -> String {
        let text = (value ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        return text.isEmpty ? "any" : text
    }
}
