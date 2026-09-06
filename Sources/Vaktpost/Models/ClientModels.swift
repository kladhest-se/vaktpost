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
    var seenInARP: Bool
    var seenInLease: Bool
    var online: Bool?

    var name: String {
        if let d = descr, !d.isEmpty { return d }
        if let h = hostname, !h.isEmpty, h != "—" { return h }
        return ip
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
        return leaseState?.isEmpty == false ? leaseState! : "not seen"
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
        statics: [StaticMapping]
    ) -> [NetworkClient] {
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
                isStatic: true, seenInARP: false, seenInLease: false, online: nil
            )
        }

        for l in leases {
            let k = key(mac: l.mac, ip: l.ip)
            if var existing = byKey[k] {
                existing.seenInLease = true
                if existing.ip.isEmpty || existing.ip == "—" { existing.ip = l.ip }
                existing.hostname = existing.hostname ?? l.hostname
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
                    isStatic: l.isStatic, seenInARP: false, seenInLease: true,
                    online: l.online
                )
            }
        }

        for a in arp {
            let k = key(mac: a.mac, ip: a.ip)
            if var existing = byKey[k] {
                existing.seenInARP = true
                if existing.ip.isEmpty || existing.ip == "—" { existing.ip = a.ip }
                existing.hostname = existing.hostname ?? a.hostname
                existing.interfaceName = existing.interfaceName ?? a.interfaceName
                byKey[k] = existing
            } else {
                byKey[k] = NetworkClient(
                    id: k, mac: a.mac, ip: a.ip,
                    hostname: a.hostname, descr: nil,
                    interfaceName: a.interfaceName,
                    leaseState: nil, leaseEnds: nil,
                    isStatic: false, seenInARP: true, seenInLease: false, online: nil
                )
            }
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
