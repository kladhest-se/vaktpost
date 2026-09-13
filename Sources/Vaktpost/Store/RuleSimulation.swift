import Foundation

/// What a rule would have done to traffic the firewall actually logged.
///
/// This replaces `RuleSimulationEngine`, which was unreachable except from its
/// own `#Preview` and would have been worse than useless if it had been
/// reachable. Its headline number was
/// `max(matchedAddresses.count + matchedPorts.count, 1)`:
///
///   - it added a count of *addresses* to a count of *ports*, which are not
///     the same unit and cannot be summed into anything;
///   - it matched an address appearing as either source *or* destination, so a
///     rule from A to B counted every host that was A or B, never checking
///     that traffic went from one to the other;
///   - and the `max(…, 1)` meant it could never report zero. A rule affecting
///     nothing claimed one match.
///
/// That number was shown beside a "risk level" derived from it, immediately
/// before a firewall write. A plausible figure that quantifies nothing is more
/// dangerous than no figure, because somebody believes it.
///
/// What is here instead evaluates the rule against logged packets — each of
/// which has a source, a destination, ports, a protocol and an interface — and
/// counts the ones it would have matched. Every number it reports is a count
/// of log lines, and the screen says so.
enum RuleSimulation {

    /// Whether a filter-log sample is trustworthy enough to evaluate.
    ///
    /// A failed refresh does not erase the store's last good log. That is useful
    /// for browsing, but dangerous here: silently evaluating the retained array
    /// makes old data look current. A recent retained sample is allowed only as
    /// explicitly labelled cached data; an old one produces no result.
    enum SampleStatus: Equatable {
        case fresh(fetchedAt: Date)
        case cached(fetchedAt: Date, error: String)
        case stale(fetchedAt: Date, error: String?)
        case unavailable(error: String?)

        var allowsSimulation: Bool {
            switch self {
            case .fresh, .cached: return true
            case .stale, .unavailable: return false
            }
        }
    }

    struct Result {
        /// Log lines this rule would have matched.
        let matched: Int
        /// Lines that carried enough detail to judge.
        let considered: Int
        /// Lines skipped because they had no parsed filter fields.
        let unparsed: Int
        /// What the firewall did with the matching traffic at the time.
        let passedAtTheTime: Int
        let blockedAtTheTime: Int
        /// The busiest sources among matches, for recognising what this is.
        let sources: [String]

        var matchesNothing: Bool { matched == 0 }

        /// Traffic this rule would newly block that is getting through today.
        ///
        /// The number worth looking at before saving a block rule, and the one
        /// the old engine could not have produced.
        var wouldNewlyBlock: Int { passedAtTheTime }

        /// Traffic this rule would newly allow that is being blocked today.
        var wouldNewlyPass: Int { blockedAtTheTime }
    }

    /// Classifies the log independently from the view so the freshness policy
    /// can be exercised with fixed clocks in tests.
    static func sampleStatus(freshness: SectionFreshness?,
                             error: String?,
                             now: Date,
                             refreshInterval: TimeInterval) -> SampleStatus {
        let failure = error ?? freshness?.failure
        guard let fetchedAt = freshness?.lastSuccess else {
            return .unavailable(error: failure)
        }

        let age = max(0, now.timeIntervalSince(fetchedAt))
        let freshLimit = max(60, refreshInterval * 2)
        if let failure {
            // A brief outage should not throw away a sample fetched moments
            // ago, but ten refresh intervals is the hard ceiling for presenting
            // historical traffic as relevant to a pending firewall change.
            let cachedLimit = max(300, refreshInterval * 10)
            return age <= cachedLimit
                ? .cached(fetchedAt: fetchedAt, error: failure)
                : .stale(fetchedAt: fetchedAt, error: failure)
        }
        return age <= freshLimit
            ? .fresh(fetchedAt: fetchedAt)
            : .stale(fetchedAt: fetchedAt, error: nil)
    }

    /// Evaluate a rule against a window of filter log lines.
    ///
    /// Matching is literal, exactly as `RulePlacement` is: `any` matches
    /// everything, and otherwise both sides must be equal. No subnet
    /// arithmetic, no alias resolution. A rule naming an alias will match
    /// nothing here and the screen has to say that rather than let a zero read
    /// as "no traffic".
    static func run(_ rule: FirewallRule, against lines: [LogLine]) -> Result {
        var matched = 0
        var considered = 0
        var unparsed = 0
        var passed = 0
        var blocked = 0
        var sourceCounts: [String: Int] = [:]

        for line in lines {
            guard let fields = line.filterFields,
                  let source = fields.source, let destination = fields.destination else {
                unparsed += 1
                continue
            }
            considered += 1

            guard matches(rule, source: source, destination: destination,
                          sourcePort: fields.sourcePort, destinationPort: fields.destinationPort,
                          proto: fields.proto, interface: fields.interfaceName) else { continue }

            matched += 1
            sourceCounts[source, default: 0] += 1

            // What happened to it at the time, which is what makes the result
            // actionable: a block rule over traffic currently passing is a
            // change, over traffic already blocked it is housekeeping.
            switch (fields.action ?? line.action ?? "").lowercased() {
            case let action where action.hasPrefix("pass"): passed += 1
            case let action where action.hasPrefix("block"), let action where action.hasPrefix("reject"):
                blocked += 1
            default: break
            }
        }

        let sources = sourceCounts.sorted { $0.value > $1.value }.prefix(5).map(\.key)
        return Result(matched: matched, considered: considered, unparsed: unparsed,
                      passedAtTheTime: passed, blockedAtTheTime: blocked,
                      sources: Array(sources))
    }

    // MARK: Matching

    private static func matches(_ rule: FirewallRule,
                                source: String, destination: String,
                                sourcePort: String?, destinationPort: String?,
                                proto: String?, interface: String?) -> Bool {
        // Interface first: it rejects most lines and costs nothing. A logged
        // packet on another interface never reaches this rule.
        if let interface, !interface.isEmpty,
           !equal(interface, rule.interfaceName) { return false }

        return covers(rule.sourceSide.address, source)
            && covers(rule.destinationSide.address, destination)
            && covers(rule.sourceSide.port, sourcePort)
            && covers(rule.destinationSide.port, destinationPort)
            && covers(rule.proto, proto)
    }

    /// Does a rule field cover an observed value?
    private static func covers(_ field: String?, _ observed: String?) -> Bool {
        let wanted = normalised(field)
        if wanted == "any" { return true }
        return wanted == normalised(observed)
    }

    private static func equal(_ lhs: String?, _ rhs: String?) -> Bool {
        normalised(lhs) == normalised(rhs)
    }

    private static func normalised(_ value: String?) -> String {
        let text = (value ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        return text.isEmpty ? "any" : text
    }
}
