import Foundation

/// Whether what somebody typed can be sent to a firewall.
///
/// Nothing checked this before. The editors took free text for every address
/// and port and posted it to `write_config` — so `10.0.0.256`, a trailing
/// space, or an alias that does not exist all reached pfSense, and pfSense was
/// the first thing to find out. A rule that fails to load is a rule that is
/// not enforcing anything, and the app that sent it said "saved".
///
/// Pure and free of SwiftUI on purpose: this is the part with all the edge
/// cases in it, and it should be testable without a simulator.
enum FieldValidator {

    /// What a field is for, which decides what counts as valid in it.
    enum Kind {
        /// `any`, an address, a CIDR, an alias, or a range.
        case address
        /// A port, a range, an alias, or empty for any.
        case port
        /// A NAT target: one host or an alias. Never `any`, never empty.
        case target
    }

    struct Problem: Equatable {
        let field: String
        let message: String
    }

    // MARK: Pieces

    /// pfSense alias names: letters, digits and underscore, not starting with
    /// a digit. Checked against the aliases this firewall actually has, so a
    /// name that looks right but does not exist is still caught.
    static func isAliasName(_ text: String) -> Bool {
        guard let first = text.first, first.isLetter || first == "_" else { return false }
        return text.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    static func isIPv4(_ text: String) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            // Not `Int(part) != nil`: that accepts "+1", "-0" and leading
            // whitespace, all of which pfSense will take and then behave
            // unexpectedly about.
            guard !part.isEmpty, part.count <= 3, part.allSatisfy(\.isNumber),
                  let value = Int(part), value <= 255 else { return false }
            return true
        }
    }

    static func isIPv6(_ text: String) -> Bool {
        // Delegated rather than hand-rolled. `ClientAddress` already
        // normalises addresses for the whole app, and a second opinion about
        // what an address is would eventually disagree with the first.
        guard text.contains(":") else { return false }
        return ClientAddress.key(text) != nil
    }

    static func isAddress(_ text: String) -> Bool { isIPv4(text) || isIPv6(text) }

    /// A pfSense-owned address selector, not a user-defined alias.
    ///
    /// Filter rules store an interface subnet as its internal key (`wan`,
    /// `opt3`) and its current address as that key plus `ip` (`wanip`,
    /// `opt3ip`). The built-in client networks and `self` are stored the same
    /// way: as names which deliberately do not appear in `$config["aliases"]`.
    /// Accepting every alias-shaped word would hide typos, so only configured
    /// interface keys and pfSense's fixed selectors pass here.
    static func isSystemAddress(_ text: String, interfaces: Set<String>) -> Bool {
        let value = text.lowercased()
        if ["self", "pptp", "pppoe", "l2tp"].contains(value) { return true }
        return interfaces.contains { interface in
            let key = interface.lowercased()
            return value == key || value == "\(key)ip"
        }
    }

    /// An address with a prefix length that fits its family.
    static func isCIDR(_ text: String) -> Bool {
        let parts = text.split(separator: "/")
        guard parts.count == 2, let bits = Int(parts[1]), bits >= 0 else { return false }
        let host = String(parts[0])
        if isIPv4(host) { return bits <= 32 }
        if isIPv6(host) { return bits <= 128 }
        return false
    }

    static func isPortNumber(_ text: String) -> Bool {
        guard !text.isEmpty, text.allSatisfy(\.isNumber), let value = Int(text) else { return false }
        return value >= 1 && value <= 65_535
    }

    /// `8000-8100`. The order matters: pfSense accepts a reversed range and it
    /// matches nothing, which is the kind of rule somebody debugs for an hour.
    static func isPortRange(_ text: String) -> Bool {
        let parts = text.split(separator: "-")
        guard parts.count == 2,
              isPortNumber(String(parts[0])), isPortNumber(String(parts[1])),
              let low = Int(parts[0]), let high = Int(parts[1]) else { return false }
        return low <= high
    }

    private static func literalAddress(_ text: String) -> String {
        guard let first = text.split(separator: "/", maxSplits: 1).first else { return "" }
        return String(first)
    }

    private static func familyProblem(_ text: String, family: String,
                                      field: String) -> Problem? {
        let literal = literalAddress(text)
        if isIPv4(literal), family != "inet" {
            return Problem(field: field, message: "An IPv4 address requires the IPv4 rule version.")
        }
        if isIPv6(literal), family != "inet6" {
            return Problem(field: field, message: "An IPv6 address requires the IPv6 rule version.")
        }
        return nil
    }

    private static func storageProblem(_ text: String, storage: FilterAddress.StorageKind,
                                       field: String, interfaces: Set<String>) -> Problem? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased() == "any", storage != .any {
            return Problem(field: field, message: "Choose Any so pfSense stores the wildcard correctly.")
        }
        if isSystemAddress(value, interfaces: interfaces), storage != .network {
            return Problem(field: field,
                           message: "Choose this value from the system address list so pfSense stores it correctly.")
        }
        return nil
    }

    // MARK: Fields

    /// The problem with one field, or nil if there is none.
    ///
    /// `aliases` is the set this firewall has. An alias-shaped name that is not
    /// in it is rejected: it is the likeliest typo in the whole editor, it
    /// looks entirely correct, and the resulting rule silently matches nothing.
    static func problem(in raw: String, kind: Kind, field: String,
                        aliases: Set<String>, interfaces: Set<String> = []) -> Problem? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        switch kind {
        case .address:
            if text.isEmpty {
                return Problem(field: field, message: "Cannot be empty. Use \"any\" to match everything.")
            }
            if text.lowercased() == "any" { return nil }
            if isAddress(text) || isCIDR(text) { return nil }
            if isSystemAddress(text, interfaces: interfaces) { return nil }
            if isAliasName(text) {
                return aliases.contains(text) ? nil
                    : Problem(field: field, message: "No alias called \"\(text)\" on this firewall.")
            }
            return Problem(field: field, message: "Not an address, a network, or an alias.")

        case .port:
            // Empty means any, which is a normal thing to want.
            if text.isEmpty { return nil }
            if isPortNumber(text) || isPortRange(text) { return nil }
            if isAliasName(text) {
                return aliases.contains(text) ? nil
                    : Problem(field: field, message: "No alias called \"\(text)\" on this firewall.")
            }
            if text.contains("-") {
                return Problem(field: field, message: "A range must be low-high, both 1 to 65535.")
            }
            return Problem(field: field, message: "Not a port, a range, or an alias.")

        case .target:
            if text.isEmpty {
                return Problem(field: field, message: "A port forward needs somewhere to send traffic.")
            }
            if text.lowercased() == "any" {
                // Accepted by pfSense and almost never meant: it forwards to
                // whatever the packet was already addressed to.
                return Problem(field: field, message: "\"any\" is not a destination. Name a host or an alias.")
            }
            if isAddress(text) { return nil }
            if isAliasName(text) {
                return aliases.contains(text) ? nil
                    : Problem(field: field, message: "No alias called \"\(text)\" on this firewall.")
            }
            return Problem(field: field, message: "Not an address or an alias.")
        }
    }

    /// Quick Block deliberately accepts only a literal host or CIDR. An alias
    /// can change underneath a one-tap emergency block, while `any` or a
    /// pfSense system selector would make the rule far broader than the person
    /// confirmed.
    static func quickBlockProblem(in raw: String, field: String = "Address") -> Problem? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return Problem(field: field, message: "Enter an IPv4 or IPv6 address or network.")
        }
        if isAddress(text) || isCIDR(text) { return nil }
        return Problem(field: field,
                       message: "Quick Block needs a literal IPv4 or IPv6 address or CIDR network.")
    }

    // MARK: Whole forms

    static func problems(inRule form: RuleEditForm, aliases: Set<String>,
                         interfaces: Set<String> = []) -> [Problem] {
        var out: [Problem] = []
        out.append(contentsOf: [
            problem(in: form.sourceAddress, kind: .address, field: "Source address",
                    aliases: aliases, interfaces: interfaces),
            problem(in: form.sourcePort, kind: .port, field: "Source port", aliases: aliases),
            problem(in: form.destinationAddress, kind: .address, field: "Destination address",
                    aliases: aliases, interfaces: interfaces),
            problem(in: form.destinationPort, kind: .port, field: "Destination port", aliases: aliases)
        ].compactMap { $0 })
        out.append(contentsOf: [
            storageProblem(form.sourceAddress, storage: form.sourceStorageKind,
                           field: "Source address", interfaces: interfaces),
            storageProblem(form.destinationAddress, storage: form.destinationStorageKind,
                           field: "Destination address", interfaces: interfaces),
            familyProblem(form.sourceAddress, family: form.addressFamily, field: "Source address"),
            familyProblem(form.destinationAddress, family: form.addressFamily,
                          field: "Destination address")
        ].compactMap { $0 })

        // A port without a protocol that has ports is a rule pfSense will not
        // load. Catching it here beats catching it in the system log.
        let hasPorts = ["tcp", "udp", "tcp/udp"].contains(form.proto.lowercased())
        if !hasPorts, !form.sourcePort.isEmpty || !form.destinationPort.isEmpty {
            out.append(Problem(field: "Protocol",
                               message: "Ports need TCP or UDP. Clear the ports, or choose a protocol that has them."))
        }
        return out
    }

    static func problems(inForward form: PortForwardEditForm, aliases: Set<String>,
                         interfaces: Set<String> = []) -> [Problem] {
        var out: [Problem] = []
        out.append(contentsOf: [
            problem(in: form.sourceAddress, kind: .address, field: "Source address",
                    aliases: aliases, interfaces: interfaces),
            problem(in: form.destinationAddress, kind: .address, field: "Destination address",
                    aliases: aliases, interfaces: interfaces),
            problem(in: form.destinationPort, kind: .port, field: "Destination port", aliases: aliases),
            problem(in: form.targetAddress, kind: .target, field: "Target address", aliases: aliases),
            problem(in: form.localPort, kind: .port,
                    field: "Redirect target port", aliases: aliases)
        ].compactMap { $0 })
        out.append(contentsOf: [
            storageProblem(form.sourceAddress, storage: form.sourceStorageKind,
                           field: "Source address", interfaces: interfaces),
            storageProblem(form.destinationAddress, storage: form.destinationStorageKind,
                           field: "Destination address", interfaces: interfaces),
            familyProblem(form.sourceAddress, family: form.addressFamily, field: "Source address"),
            familyProblem(form.destinationAddress, family: form.addressFamily,
                          field: "Destination address"),
            familyProblem(form.targetAddress, family: form.addressFamily, field: "Target address")
        ].compactMap { $0 })

        let hasPorts = ["tcp", "udp", "tcp/udp"].contains(form.proto.lowercased())
        if !hasPorts, !form.destinationPort.isEmpty || !form.localPort.isEmpty {
            out.append(Problem(field: "Protocol",
                               message: "Ports need TCP or UDP. Clear the ports, or choose a protocol that has them."))
        }

        // A single local port behind a destination *range* is how pfSense
        // expresses "map the range onto a range starting here". A range behind
        // a range of a different size is not expressible and is silently
        // truncated.
        if isPortRange(form.destinationPort), isPortRange(form.localPort) {
            let outside = form.destinationPort.split(separator: "-").compactMap { Int($0) }
            let inside = form.localPort.split(separator: "-").compactMap { Int($0) }
            if outside.count == 2, inside.count == 2,
               (outside[1] - outside[0]) != (inside[1] - inside[0]) {
                out.append(Problem(field: "Redirect target port",
                                   message: "The ranges are different sizes, so the mapping is ambiguous."))
            }
        }
        return out
    }
}
