import Foundation

/// Everything this firewall knows about one address, gathered from the tables
/// the app has already fetched.
///
/// The data for this was always there and always scattered. Six screens each
/// had their own search box, so "what is 172.16.1.32 and what touches it"
/// meant visiting five of them and remembering what each said. Nothing here
/// asks the firewall anything new.
///
/// Written as a pure function over arrays rather than as a method on the
/// store, so the matching can be tested without a firewall, a store or a
/// simulator — and the matching is the part with all the mistakes in it.
enum Investigation {

    /// One thing that mentioned the query.
    struct Finding: Identifiable {
        enum Kind: String {
            case client, arp, lease, staticMapping, hostOverride
            case alias, rule, portForward, vpn, dnsbl

            var title: String {
                switch self {
                case .client: return "Client"
                case .arp: return "ARP table"
                case .lease: return "DHCP lease"
                case .staticMapping: return "Static mapping"
                case .hostOverride: return "DNS override"
                case .alias: return "Alias"
                case .rule: return "Firewall rule"
                case .portForward: return "Port forward"
                case .vpn: return "VPN"
                case .dnsbl: return "DNSBL"
                }
            }

            var symbol: String {
                switch self {
                case .client: return "desktopcomputer"
                case .arp: return "point.3.connected.trianglepath.dotted"
                case .lease: return "clock.arrow.circlepath"
                case .staticMapping: return "pin"
                case .hostOverride: return "character.cursor.ibeam"
                case .alias: return "list.bullet.rectangle"
                case .rule: return "lock.shield"
                case .portForward: return "arrow.turn.down.right"
                case .vpn: return "lock.shield"
                case .dnsbl: return "shield.lefthalf.filled"
                }
            }
        }

        let id: String
        let kind: Kind
        let title: String
        let detail: String?
        /// Why this matched, when that is not obvious from the title — an
        /// alias matched through its members, a rule matched through an alias
        /// it names. A result somebody cannot account for is one they have to
        /// go and check, which is the work this was meant to save.
        let via: String?
    }

    /// What a query is, decided once rather than guessed at per table.
    enum Subject: Equatable {
        case address(String)
        case mac(String)
        case text(String)

        var display: String {
            switch self {
            case let .address(value), let .mac(value), let .text(value): return value
            }
        }
    }

    /// Classify the query.
    ///
    /// An address is normalised so every comparison downstream is exact rather
    /// than textual — the ARP table and a firewall rule can spell one IPv6
    /// address differently, and a substring match on "10.0.0.1" also matches
    /// "10.0.0.100", which is the kind of wrong answer that is worse than none.
    static func subject(_ raw: String) -> Subject? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return nil }
        if ClientAddress.key(trimmed) != nil { return .address(trimmed) }
        if isMAC(trimmed) { return .mac(trimmed.lowercased()) }
        return .text(trimmed.lowercased())
    }

    static func isMAC(_ value: String) -> Bool {
        let parts = value.lowercased().split(separator: ":")
        guard parts.count == 6 else { return false }
        return parts.allSatisfy { $0.count == 2 && $0.allSatisfy(\.isHexDigit) }
    }

    /// Does this text refer to the subject?
    ///
    /// For an address, both sides are normalised and compared whole, with a
    /// CIDR host address treated as its address — a rule naming
    /// `10.253.21.10/32` is about that host. For a MAC or free text it is a
    /// case-insensitive containment, which is what somebody typing part of a
    /// hostname means.
    static func matches(_ subject: Subject, _ text: String?) -> Bool {
        guard let text, !text.isEmpty else { return false }
        switch subject {
        case let .address(value):
            guard let wanted = ClientAddress.key(value) else { return false }
            for token in tokens(in: text) where ClientAddress.key(token) == wanted {
                return true
            }
            return false
        case let .mac(value):
            return text.lowercased().contains(value)
        case let .text(value):
            return text.lowercased().contains(value)
        }
    }

    /// Split a field into the things that might be addresses.
    ///
    /// Firewall fields hold lists and ranges — "10.0.0.1 10.0.0.2", "port 443",
    /// "10.253.21.10/32" — so a whole-field comparison would miss almost
    /// everything a rule actually says.
    private static func tokens(in text: String) -> [String] {
        text.split(whereSeparator: { " ,;\t".contains($0) })
            .map { token -> String in
                // A single-host prefix is that host. Anything else keeps its
                // prefix and will simply not match, which is correct: this
                // does not claim to do subnet containment.
                if token.hasSuffix("/32") || token.hasSuffix("/128") {
                    return String(token.dropLast(token.hasSuffix("/32") ? 3 : 4))
                }
                return String(token)
            }
    }

    // MARK: Gathering

    /// Everything that mentions the subject, in the order a person reads it:
    /// what the thing is first, then what touches it.
    ///
    /// `aliasNames` is computed before the rules are walked, because a rule
    /// naming an alias is about every address in it. Without that step, the
    /// most interesting answer — which of my rules actually applies to this
    /// device — is the one the search misses.
    static func findings(for subject: Subject,
                         clients: [NetworkClient],
                         arp: [ARPEntry],
                         leases: [DHCPLease],
                         staticMappings: [StaticMapping],
                         hostOverrides: [HostOverride],
                         aliases: [FirewallAliasEntry],
                         rules: [FirewallRule],
                         portForwards: [PortForward],
                         openvpnServers: [OpenVPNServerStatus],
                         wireguardPeers: [WireGuardPeer],
                         dnsblClients: [DNSBLCount]) -> [Finding] {
        var out: [Finding] = []

        for client in clients where matches(subject, client.ip) || matches(subject, client.mac)
            || matches(subject, client.hostname) || matches(subject, client.descr) {
            out.append(Finding(id: "client-\(client.id)", kind: .client,
                               title: client.name,
                               detail: [client.ip, client.mac].joined(separator: " · "),
                               via: nil))
        }

        for entry in arp where matches(subject, entry.ip) || matches(subject, entry.mac)
            || matches(subject, entry.hostname) {
            out.append(Finding(id: "arp-\(entry.id)", kind: .arp,
                               title: entry.ip,
                               detail: [entry.mac, entry.interfaceName].compactMap { $0 }.joined(separator: " · "),
                               via: nil))
        }

        for lease in leases where matches(subject, lease.ip) || matches(subject, lease.mac)
            || matches(subject, lease.hostname) {
            out.append(Finding(id: "lease-\(lease.id)", kind: .lease,
                               title: lease.ip,
                               detail: [lease.hostname, lease.state].compactMap { $0 }.joined(separator: " · "),
                               via: nil))
        }

        for mapping in staticMappings where matches(subject, mapping.ip) || matches(subject, mapping.mac)
            || matches(subject, mapping.hostname) {
            out.append(Finding(id: "static-\(mapping.id)", kind: .staticMapping,
                               title: mapping.ip,
                               detail: mapping.hostname ?? mapping.descr,
                               via: nil))
        }

        for override in hostOverrides where matches(subject, override.ip)
            || matches(subject, "\(override.host).\(override.domain)") {
            out.append(Finding(id: "override-\(override.id)", kind: .hostOverride,
                               title: "\(override.host).\(override.domain)",
                               detail: override.ip, via: nil))
        }

        // Aliases first, and their names kept: a rule that names one is about
        // every address it holds.
        var aliasNames: Set<String> = []
        for alias in aliases {
            let byName = matches(subject, alias.name)
            let member = alias.addresses.first { matches(subject, $0) }
            guard byName || member != nil else { continue }
            aliasNames.insert(alias.name)
            out.append(Finding(id: "alias-\(alias.id)", kind: .alias,
                               title: alias.name,
                               detail: alias.descr ?? alias.type,
                               via: member.map { "contains \($0)" }))
        }

        for rule in rules {
            // `sourceSide.address`, not `source`. The latter is the display
            // string and appends ":443" when the rule has a port, which makes
            // an exact address comparison fail on exactly the rules most worth
            // finding.
            let direct = matches(subject, rule.sourceSide.address)
                || matches(subject, rule.destinationSide.address)
            let alias = aliasNames.first {
                rule.sourceSide.address.contains($0) || rule.destinationSide.address.contains($0)
            }
            guard direct || alias != nil else { continue }
            out.append(Finding(id: "rule-\(rule.id)", kind: .rule,
                               title: rule.descr.isEmpty ? "\(rule.type) \(rule.source) → \(rule.destination)" : rule.descr,
                               detail: "\(rule.interfaceName) · \(rule.type) · \(rule.source) → \(rule.destination)",
                               via: alias.map { "via alias \($0)" }
                                    ?? (rule.disabled ? "rule is disabled" : nil)))
        }

        for forward in portForwards {
            let direct = matches(subject, forward.target)
                || matches(subject, forward.destinationSide.address)
                || matches(subject, forward.sourceSide.address)
            let alias = aliasNames.first {
                forward.destinationSide.address.contains($0) || forward.target.contains($0)
            }
            guard direct || alias != nil else { continue }
            out.append(Finding(id: "nat-\(forward.id)", kind: .portForward,
                               title: forward.descr.isEmpty ? forward.target : forward.descr,
                               detail: "\(forward.interfaceName) · \(forward.destination) → \(forward.target)",
                               via: alias.map { "via alias \($0)" }
                                    ?? (forward.disabled ? "rule is disabled" : nil)))
        }

        for server in openvpnServers {
            for connection in server.connections where matches(subject, connection.virtualAddress)
                || matches(subject, connection.remoteHost) || matches(subject, connection.commonName) {
                out.append(Finding(id: "ovpn-\(server.id)-\(connection.id)", kind: .vpn,
                                   title: connection.commonName,
                                   detail: [connection.virtualAddress, connection.remoteHost]
                                       .compactMap { $0 }.joined(separator: " ← "),
                                   via: "connected to \(server.name)"))
            }
        }

        for peer in wireguardPeers {
            let byAddress = peer.allowedIPs.first { matches(subject, $0) }
            guard byAddress != nil || matches(subject, peer.endpoint)
                || matches(subject, peer.descr) else { continue }
            out.append(Finding(id: "wg-\(peer.id)", kind: .vpn,
                               title: peer.descr ?? peer.shortKey,
                               detail: peer.allowedIPs.joined(separator: ", "),
                               via: "peer on \(peer.tunnel) · \(peer.statusLabel)"))
        }

        for client in dnsblClients where matches(subject, client.name) {
            out.append(Finding(id: "dnsbl-\(client.id)", kind: .dnsbl,
                               title: "\(client.count) DNS requests blocked",
                               detail: client.name, via: nil))
        }

        return out
    }
}
