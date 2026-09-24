import Foundation

/// Presentation and investigation lookups kept separate from refresh state.
extension DashboardStore {
    /// What the firewall calls an interface.
    ///
    /// Clients, ARP entries and rules all identify their interface differently:
    /// `lagg0.100` is the device, `opt7` is pfSense's internal handle, and
    /// `VLAN_100` is what the administrator named it and what the
    /// webConfigurator shows everywhere. Only the last is worth putting on
    /// screen — the other two require a lookup table nobody carries in their
    /// head.
    ///
    /// Falls back to the raw value, so an interface the app has not seen is
    /// still identified rather than blank.
    /// What a rule's source or destination should read as.
    ///
    /// pfSense stores a system selector by its internal key: `lan`, `opt4`,
    /// `lanip`, `self`. The rule list showed those raw, so a rule read
    /// "from lan to opt4" while the tab above it, the rule's own Interface
    /// field, and the editor's pickers all said VLAN_100 — the same thing
    /// under three names, only one of which is in the webConfigurator.
    ///
    /// Only selectors are translated. An alias or a literal address is what
    /// somebody typed, and is left exactly as typed.
    func addressLabel(for side: FilterAddress) -> String {
        guard side.storageKind == .network else { return side.address }
        let raw = side.address
        let lowered = raw.lowercased()
        switch lowered {
        case "any": return "any"
        case "self": return "this firewall"
        case "pptp": return "PPTP clients"
        case "pppoe": return "PPPoE clients"
        case "l2tp": return "L2TP clients"
        default: break
        }
        // `lanip` is the interface's own address; `lan` is the subnets behind
        // it. The suffix is pfSense's, and the wording is the editor's.
        if lowered.hasSuffix("ip"), let name = interfaceName(forKey: String(raw.dropLast(2))) {
            return "\(name) address"
        }
        if let name = interfaceName(forKey: raw) {
            return "\(name) subnets"
        }
        return raw
    }

    /// The administrator's name for pfSense's internal interface key.
    private func interfaceName(forKey key: String) -> String? {
        let lowered = key.lowercased()
        guard !lowered.isEmpty else { return nil }
        return interfaces.first { $0.internalName?.lowercased() == lowered }?.name
    }

    func interfaceLabel(for raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }

        // A floating rule names every interface it applies to, comma
        // separated: `opt5,opt6,opt7,lan,opt10…`. Passed through whole it
        // matched nothing and printed the raw list, which is both unreadable
        // and the one place the names matter most.
        if raw.contains(",") {
            let parts = raw.split(separator: ",").map {
                interfaceLabel(for: String($0).trimmingCharacters(in: .whitespaces)) ?? String($0)
            }
            // Thirteen interfaces is the whole firewall; saying so is shorter
            // and truer than listing them.
            if parts.count >= interfaces.count, interfaces.count > 1 {
                return "all interfaces"
            }
            if parts.count > 3 {
                return "\(parts.prefix(2).joined(separator: ", ")) +\(parts.count - 2)"
            }
            return parts.joined(separator: ", ")
        }

        let lowered = raw.lowercased()
        for iface in interfaces {
            if iface.device.lowercased() == lowered { return iface.name }
            if iface.internalName?.lowercased() == lowered { return iface.name }
            if iface.name.lowercased() == lowered { return iface.name }
        }
        return raw
    }

    /// The client list's entry for an address, if it has one.
    ///
    /// A capture reports addresses; the client list is keyed by device. Most of
    /// the time the address the capture saw is the one the client list shows
    /// and a direct match is the answer.
    ///
    /// When it is not — a device holding several addresses, or one whose
    /// client-list entry came from a lease while the capture caught it on a
    /// second address — the ARP and DHCP tables know which MAC is behind the
    /// address, and the MAC is what identifies a device. Matching that way
    /// rather than giving up means a second address does not become a row that
    /// mysteriously will not open.
    ///
    /// Nil for anything the firewall does not recognise as a client, which on
    /// a WAN is most of what a capture returns.
    func client(matching address: String) -> NetworkClient? {
        guard let key = ClientAddress.key(address) else { return nil }

        if let direct = overviewLayout.clients.first(where: { ClientAddress.key($0.ip) == key }) {
            return direct
        }

        let mac = arp.first { ClientAddress.key($0.ip) == key }?.mac
            ?? leases.first { ClientAddress.key($0.ip) == key }?.mac
        guard let mac, !mac.isEmpty, mac != "—" else { return nil }
        return overviewLayout.clients.first { $0.mac == mac }
    }

    /// Load the tables the investigation screen searches.
    ///
    /// Several of them load only when their own screen is first opened, which
    /// made the search quietly incomplete: the answer to "which rules apply to
    /// this device" was "none" until somebody had happened to visit the
    /// Firewall screen first. A search screen that depends on where you have
    /// been is worse than one that takes a moment to open.
    ///
    /// Each loader already guards against repeating itself, so this is cheap
    /// on every open after the first. They run one after another rather than
    /// together because pfSense serialises `exec_php` against its own web UI
    /// anyway — starting three at once would not make them finish sooner, and
    /// would take the webConfigurator down with them if they did.
    ///
    /// DNSBL is not forced. It is the only one that reads a megabyte of log,
    /// and it declines by itself when pfBlockerNG is absent or its DNSBL
    /// component is off — which on most firewalls is always.
    func loadInvestigationData() async {
        await loadFirewallObjects()
        await loadDNSBLStats()
    }

    /// Interfaces reporting new errors since the last refresh.
    var interfacesWithRisingErrors: [InterfaceStat] {
        interfaceErrors.rising(among: interfaces)
    }

    /// How many contradictions the client tables currently hold.
    ///
    /// Only the ones that break traffic, so the badge on More means "something
    /// is wrong now" rather than "there is a list to read". A duplicate
    /// hostname is worth showing on the screen and is not worth a badge.
    var conflictCount: Int {
        ConflictDetector.find(arp: arp, leases: leases,
                              staticMappings: staticMappings,
                              hostOverrides: hostOverrides)
            .filter { $0.kind.severity == .bad }
            .count
    }

    /// Where an interface sits in the list the host-traffic sampler indexes.
    ///
    /// Matches the way `interfaceLabel` does — a device name, pfSense's
    /// internal handle, or the description — because the hint arrives from
    /// whichever table happened to know about the device. The ARP table spells
    /// it `lagg0.100`; a DHCP lease spells the same interface `lan`.
    ///
    /// Nil when nothing matches, and the caller has to handle that rather than
    /// fall back to a default. Sampling the wrong interface would attribute
    /// one network's traffic to a device on another, which is a more
    /// misleading answer than no answer.
    func interfaceSlot(for raw: String?) -> Int? {
        guard let raw, !raw.isEmpty, !raw.contains(",") else { return nil }
        let lowered = raw.lowercased()
        return interfaces.firstIndex { iface in
            iface.device.lowercased() == lowered
                || iface.internalName?.lowercased() == lowered
                || iface.name.lowercased() == lowered
        }
    }

    /// What an alias actually contains, with nested aliases flattened.
    ///
    /// A rule reading `alias_host_nas_hyperbackup → alias_port_hyper_backup`
    /// is precise and tells you nothing about what it permits without opening
    /// two other pages. Aliases can contain other aliases — that one holds
    /// four — so this recurses, with a depth limit because pfSense does not
    /// forbid a cycle and a stack overflow is a poor way to render a rule.
    ///
    /// Returns nil when the name is not an alias, so callers can tell "this is
    /// a literal address" from "this is an alias that resolved to nothing".
    func resolveAlias(_ name: String, depth: Int = 0) -> [String]? {
        guard depth < 4 else { return [] }
        guard let alias = aliases.first(where: { $0.name == name }) else { return nil }

        var out: [String] = []
        for member in alias.addresses {
            if let nested = resolveAlias(member, depth: depth + 1) {
                out.append(contentsOf: nested)
            } else {
                out.append(member)
            }
        }
        // Order preserved, duplicates dropped: two nested aliases often share
        // a host, and listing it twice reads as a mistake.
        var seen = Set<String>()
        return out.filter { seen.insert($0).inserted }
    }

    /// A rule field expanded for display, or nil if it is not an alias.
    ///
    /// Capped: an alias holding a subnet list runs to hundreds, and a rule row
    /// is not the place to print them. The count is kept honest.
    func expandedAlias(_ name: String, limit: Int = 6) -> String? {
        guard let members = resolveAlias(name), !members.isEmpty else { return nil }
        if members.count <= limit { return members.joined(separator: ", ") }
        let shown = members.prefix(limit).joined(separator: ", ")
        return "\(shown) +\(members.count - limit) more"
    }

    /// The best name the firewall has for an address, or nil.
    ///
    /// Shared by the Clients list and the ARP table so one device is not
    /// called two different things on two screens.
    func nameForAddress(_ ip: String) -> String? {
        if let client = overviewLayout.clients.first(where: { $0.ip == ip }), client.name != ip {
            return client.name
        }
        return nil
    }
}
