import Foundation

/// A single network client assembled from three separate pfSense views of the
/// same device: the DHCP lease, the ARP entry, and any static mapping.
///
/// pfSense exposes these as unrelated tables. Joining them on MAC (falling back
/// to IP when a MAC is missing) gives one identity per device, which is what
/// you actually think in terms of when someone asks "is the printer online".
struct NetworkClient: Identifiable {
    var id: String
    var mac: String
    var ip: String
    var hostname: String?
    var descr: String?
    var interfaceName: String?
    var leaseState: String?
    var leaseEnds: String?
    var isStatic: Bool
    /// Name from a DNS host override, if the firewall has one for this address.
    var overrideName: String?
    /// Name from a host-type firewall alias covering this address.
    var aliasName: String?
    var seenInARP: Bool
    var seenInLease: Bool
    var online: Bool?

    /// The best name available.
    ///
    /// DNS first, because that is what the device is actually called on the
    /// network and what will appear in every other tool. A firewall alias is a
    /// name a rule uses — `alias_host_srv001` is accurate but it is filing,
    /// not identity — so it now ranks below both DNS sources and is shown in
    /// full on the detail sheet rather than as the title.
    ///
    /// In order: a DNS host override, the hostname the device announced, a
    /// static mapping's description, a firewall alias, then the address.
    var name: String {
        if let o = overrideName, !o.isEmpty { return o }
        if let h = hostname, let cleaned = Self.usableHostname(h) { return cleaned }
        if let d = descr, !d.isEmpty { return d }
        // A firewall alias is deliberately not used as a title. It is the name
        // a rule refers to — accurate, and useless for recognising a device in
        // a list of ninety. An address at least says where the thing is. The
        // alias is on the detail sheet, where it is the thing you would search
        // a rule for.
        return ip
    }

    /// Where the displayed name came from, for the detail sheet.
    var nameSource: String {
        if overrideName?.isEmpty == false { return "DNS host override" }
        if let h = hostname, Self.usableHostname(h) != nil { return "announced hostname" }
        if descr?.isEmpty == false { return "static mapping" }
        return "no DNS name — showing address"
    }

    /// The names this device has, each labelled with where it came from.
    ///
    /// Shown together so nothing is lost by ranking one above the others — the
    /// alias is often the name you would search a rule for, even when the DNS
    /// name is the better title.
    var knownNames: [(source: String, value: String)] {
        var out: [(String, String)] = []
        if let o = overrideName, !o.isEmpty { out.append(("DNS name", o)) }
        if let h = hostname, let cleaned = Self.usableHostname(h) { out.append(("Hostname", cleaned)) }
        if let d = descr, !d.isEmpty { out.append(("Description", d)) }
        if let a = aliasName, !a.isEmpty { out.append(("Firewall alias", a)) }
        return out
    }

    /// Names drawn from host-type firewall aliases, indexed by address.
    ///
    /// Most people with a structured firewall have already named every device
    /// they care about here, so it is the richest naming source available and
    /// costs nothing extra — the aliases are fetched for the Firewall tab
    /// regardless.
    ///
    /// Only exact addresses count. An alias may hold a subnet, a range, or the
    /// names of other aliases (`alias_host_nas_hyperbackup` holds four alias
    /// names), and none of those identify one device.
    ///
    /// Where several aliases cover the same address, the one with the fewest
    /// members wins: an alias holding a single address is a name for that
    /// device, while one holding six is a group it happens to belong to.
    static func aliasNamesByIP(_ aliases: [FirewallAliasEntry]) -> [String: String] {
        var best: [String: (name: String, memberCount: Int)] = [:]

        for alias in aliases {
            // Port and URL aliases name no host.
            guard alias.type.isEmpty || alias.type.lowercased().hasPrefix("host")
                    || alias.type.lowercased() == "network" else { continue }

            let label = alias.descr ?? alias.name
            guard !label.isEmpty else { continue }

            for address in alias.addresses where isSingleAddress(address) {
                let candidate = (label, alias.addresses.count)
                if let existing = best[address], existing.memberCount <= candidate.1 { continue }
                best[address] = candidate
            }
        }
        return best.mapValues(\.name)
    }

    /// One host, not a subnet, a range, or a reference to another alias.
    static func isSingleAddress(_ value: String) -> Bool {
        if value.contains("-") { return false }                 // a range
        if value.hasPrefix("alias_") { return false }           // nested alias
        if let slash = value.firstIndex(of: "/") {              // a network
            return value[value.index(after: slash)...] == "32"
        }
        // Dotted quad or a colon-bearing v6 address; anything else is a name.
        return value.contains(":") || value.split(separator: ".").count == 4
    }

    /// `system_get_arp_table` writes a literal "?" when the reverse lookup
    /// fails, which on a LAN without internal DNS is most entries. Rendering it
    /// gave a client list of ninety-seven devices all called "?".
    static func usableHostname(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != "?", trimmed != "—" else { return nil }
        return trimmed
    }

    var health: Health {
        if online == true || seenInARP { return .ok }
        if isStatic { return .info }
        if leaseState?.contains("active") == true { return .ok }
        if leaseState?.contains("expired") == true { return .idle }
        return .idle
    }

    var presence: String {
        if seenInARP { return "in ARP" }
        if online == true { return "online" }
        if isStatic && !seenInLease { return "static, not seen" }
        if leaseState?.contains("expired") == true { return "lease expired" }
        return leaseState ?? "not seen"
    }

    var sourceSummary: String {
        var s: [String] = []
        if isStatic { s.append("static") }
        if seenInLease { s.append("lease") }
        if seenInARP { s.append("arp") }
        return s.joined(separator: " · ")
    }

    // MARK: Assembly

    static func merge(
        leases: [DHCPLease],
        arp: [ARPEntry],
        statics: [StaticMapping],
        overrides: [HostOverride] = [],
        aliases: [FirewallAliasEntry] = []
    ) -> [NetworkClient] {
        // Indexed by address: overrides are configured against an IP, not a MAC.
        var namesByIP: [String: String] = [:]
        for override in overrides where override.isUsable {
            // First wins, so the primary entry beats its own aliases.
            if namesByIP[override.ip] == nil { namesByIP[override.ip] = override.fqdn }
        }
        var byKey: [String: NetworkClient] = [:]

        func key(mac: String, ip: String) -> String {
            let m = mac.lowercased()
            return (m.isEmpty || m == "—") ? "ip:\(ip)" : "mac:\(m)"
        }

        for s in statics {
            let k = key(mac: s.mac, ip: s.ip)
            byKey[k] = NetworkClient(
                id: k, mac: s.mac, ip: s.ip,
                hostname: s.hostname, descr: s.descr,
                interfaceName: s.interfaceName,
                leaseState: nil, leaseEnds: nil,
                isStatic: true, overrideName: nil, aliasName: nil, seenInARP: false, seenInLease: false, online: nil
            )
        }

        for l in leases {
            let k = key(mac: l.mac, ip: l.ip)
            if var existing = byKey[k] {
                existing.seenInLease = true
                if existing.ip.isEmpty || existing.ip == "—" { existing.ip = l.ip }
                existing.hostname = existing.hostname ?? l.hostname.flatMap(Self.usableHostname)
                existing.interfaceName = existing.interfaceName ?? l.interfaceName
                existing.leaseState = l.state
                existing.leaseEnds = l.ends
                existing.online = l.online
                existing.isStatic = existing.isStatic || l.isStatic
                byKey[k] = existing
            } else {
                byKey[k] = NetworkClient(
                    id: k, mac: l.mac, ip: l.ip,
                    hostname: l.hostname, descr: nil,
                    interfaceName: l.interfaceName,
                    leaseState: l.state, leaseEnds: l.ends,
                    isStatic: l.isStatic, overrideName: nil, aliasName: nil, seenInARP: false, seenInLease: true,
                    online: l.online
                )
            }
        }

        for a in arp {
            let k = key(mac: a.mac, ip: a.ip)
            if var existing = byKey[k] {
                existing.seenInARP = true
                if existing.ip.isEmpty || existing.ip == "—" { existing.ip = a.ip }
                existing.hostname = existing.hostname ?? a.hostname.flatMap(Self.usableHostname)
                existing.interfaceName = existing.interfaceName ?? a.interfaceName
                byKey[k] = existing
            } else {
                byKey[k] = NetworkClient(
                    id: k, mac: a.mac, ip: a.ip,
                    hostname: a.hostname, descr: nil,
                    interfaceName: a.interfaceName,
                    leaseState: nil, leaseEnds: nil,
                    isStatic: false, overrideName: nil, aliasName: nil, seenInARP: true, seenInLease: false, online: nil
                )
            }
        }

        let aliasNames = aliasNamesByIP(aliases)
        for (key, var client) in byKey {
            client.overrideName = namesByIP[client.ip]
            client.aliasName = aliasNames[client.ip]
            byKey[key] = client
        }

        return byKey.values.sorted { lhs, rhs in
            if lhs.health == .ok && rhs.health != .ok { return true }
            if rhs.health == .ok && lhs.health != .ok { return false }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}

/// A configured DHCP static mapping (`services/dhcp_server/static_mappings`).
struct StaticMapping: Identifiable {
    var id: String { "\(mac)-\(ip)" }
    var mac: String
    var ip: String
    var hostname: String?
    var descr: String?
    var interfaceName: String?

    init(_ d: JSONDict) {
        mac = (d.string("mac", "mac_address") ?? "").lowercased()
        ip = d.string("ipaddr", "ip", "ip_address") ?? ""
        hostname = d.string("hostname")
        descr = d.string("descr", "description")
        interfaceName = d.string("parent_id", "interface", "if")
    }
}

/// A DNS host override — what the firewall itself calls an address.
struct HostOverride: Identifiable {
    var id: String { "\(ip)-\(host)-\(domain)" }
    var host: String
    var domain: String
    var ip: String
    var descr: String?
    var source: String?

    init(_ d: JSONDict) {
        host = d.string("host") ?? ""
        domain = d.string("domain") ?? ""
        ip = d.string("ip") ?? ""
        descr = d.string("descr", "description")
        source = d.string("source")
    }

    /// "nas001.example.se", or just the host where no domain is set.
    var fqdn: String {
        domain.isEmpty ? host : "\(host).\(domain)"
    }

    var isUsable: Bool { !ip.isEmpty && !host.isEmpty }
}
