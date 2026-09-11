import Foundation

/// Contradictions between tables the firewall already gave us.
///
/// Every one of these is computable from data the client refresh has already
/// fetched — ARP, DHCP leases, static mappings, DNS overrides — and every one
/// of them is a real misconfiguration that shows up as "the network is being
/// weird" long before anybody thinks to compare two tables by hand.
///
/// A pure function over arrays, so the detection can be tested without a
/// firewall. That matters more here than usual: the cost of a false positive
/// is somebody hunting a problem that does not exist, which is worse than not
/// having flagged it at all.
enum ConflictDetector {

    struct Conflict: Identifiable {
        enum Kind: String {
            /// Two MACs claim the same address. Classic duplicate-IP.
            case addressClaimedTwice
            /// ARP and the lease table disagree about who holds an address.
            case arpDisagreesWithLease
            /// Two static mappings hand the same address to different devices.
            case duplicateStaticAddress
            /// One device has two static mappings.
            case duplicateStaticMAC
            /// A static mapping's address is currently leased to someone else.
            case staticAddressLeasedElsewhere
            /// One name resolves to two different addresses.
            case overrideNameCollision
            /// Two devices answer to the same name.
            case duplicateHostname

            var title: String {
                switch self {
                case .addressClaimedTwice: return "Address claimed by two devices"
                case .arpDisagreesWithLease: return "ARP and lease disagree"
                case .duplicateStaticAddress: return "Two static mappings, one address"
                case .duplicateStaticMAC: return "One device, two static mappings"
                case .staticAddressLeasedElsewhere: return "Static address leased to another device"
                case .overrideNameCollision: return "One name, two addresses"
                case .duplicateHostname: return "Two devices, one name"
                }
            }

            /// Why it matters, in the terms somebody debugging would use.
            var consequence: String {
                switch self {
                case .addressClaimedTwice:
                    return "Traffic for this address will reach whichever device answered ARP most recently, and will move between them."
                case .arpDisagreesWithLease:
                    return "Usually a stale lease or a device with a hardcoded address. The firewall will route to what ARP says, not what the lease says."
                case .duplicateStaticAddress:
                    return "Whichever device asks for a lease second will be refused or handed the address anyway, depending on the DHCP server."
                case .duplicateStaticMAC:
                    return "Which address this device gets depends on which mapping the server reads first."
                case .staticAddressLeasedElsewhere:
                    return "The reservation cannot be honoured until that lease expires, and the reserved device will be given something else in the meantime."
                case .overrideNameCollision:
                    return "Resolution will pick one, and which one is not something this app can predict."
                case .duplicateHostname:
                    return "Anything resolving by name will reach one of them, arbitrarily."
                }
            }

            /// How alarming it is.
            ///
            /// Only the ones that break traffic now are `bad`. A duplicate
            /// hostname is untidy and frequently deliberate — two devices in a
            /// lease table both called `localhost` is not an incident — and
            /// grading it the same as a duplicate address would teach people
            /// to skim past both.
            var severity: Health {
                switch self {
                case .addressClaimedTwice, .arpDisagreesWithLease,
                     .staticAddressLeasedElsewhere, .duplicateStaticAddress:
                    return .bad
                case .duplicateStaticMAC, .overrideNameCollision:
                    return .warn
                case .duplicateHostname:
                    return .idle
                }
            }
        }

        let id: String
        let kind: Kind
        /// What the conflict is about — the address, or the name.
        let subject: String
        /// The contradicting sides, in the order they were found.
        let sides: [String]
    }

    /// Everything wrong with these tables, worst first.
    static func find(arp: [ARPEntry],
                     leases: [DHCPLease],
                     staticMappings: [StaticMapping],
                     hostOverrides: [HostOverride]) -> [Conflict] {
        var out: [Conflict] = []
        out += addressClaimedTwice(arp)
        out += arpDisagreesWithLease(arp: arp, leases: leases)
        out += staticConflicts(staticMappings: staticMappings, leases: leases)
        out += nameConflicts(hostOverrides: hostOverrides, leases: leases, staticMappings: staticMappings)

        let order: [Conflict.Kind] = [
            .addressClaimedTwice, .arpDisagreesWithLease, .staticAddressLeasedElsewhere,
            .duplicateStaticAddress, .duplicateStaticMAC, .overrideNameCollision,
            .duplicateHostname
        ]
        return out.sorted { lhs, rhs in
            let l = order.firstIndex(of: lhs.kind) ?? order.count
            let r = order.firstIndex(of: rhs.kind) ?? order.count
            if l != r { return l < r }
            return lhs.subject < rhs.subject
        }
    }

    // MARK: One address, two devices

    private static func addressClaimedTwice(_ arp: [ARPEntry]) -> [Conflict] {
        var byAddress: [String: Set<String>] = [:]
        for entry in arp {
            guard let key = ClientAddress.key(entry.ip) else { continue }
            let mac = normalise(entry.mac)
            guard !mac.isEmpty else { continue }
            byAddress[key, default: []].insert(mac)
        }
        return byAddress.compactMap { key, macs in
            guard macs.count > 1 else { return nil }
            let address = arp.first { ClientAddress.key($0.ip) == key }?.ip ?? key
            return Conflict(id: "dup-addr-\(key)", kind: .addressClaimedTwice,
                            subject: address, sides: macs.sorted())
        }
    }

    // MARK: ARP against the lease table

    private static func arpDisagreesWithLease(arp: [ARPEntry], leases: [DHCPLease]) -> [Conflict] {
        // Only active leases. An expired lease naming a different device is
        // the system working — the address was handed on — and flagging it
        // would fill the screen with history.
        var leaseByAddress: [String: DHCPLease] = [:]
        for lease in leases where lease.state.lowercased().contains("active") || lease.isStatic {
            guard let key = ClientAddress.key(lease.ip) else { continue }
            leaseByAddress[key] = lease
        }

        var out: [Conflict] = []
        for entry in arp {
            guard let key = ClientAddress.key(entry.ip), let lease = leaseByAddress[key] else { continue }
            let arpMAC = normalise(entry.mac)
            let leaseMAC = normalise(lease.mac)
            guard !arpMAC.isEmpty, !leaseMAC.isEmpty, arpMAC != leaseMAC else { continue }
            out.append(Conflict(id: "arp-lease-\(key)", kind: .arpDisagreesWithLease,
                                subject: entry.ip,
                                sides: ["ARP says \(arpMAC)", "lease says \(leaseMAC)"]))
        }
        return out
    }

    // MARK: Static mappings

    private static func staticConflicts(staticMappings: [StaticMapping],
                                        leases: [DHCPLease]) -> [Conflict] {
        var out: [Conflict] = []

        var byAddress: [String: [StaticMapping]] = [:]
        var byMAC: [String: [StaticMapping]] = [:]
        for mapping in staticMappings {
            if let key = ClientAddress.key(mapping.ip) {
                byAddress[key, default: []].append(mapping)
            }
            let mac = normalise(mapping.mac)
            if !mac.isEmpty { byMAC[mac, default: []].append(mapping) }
        }

        for (key, mappings) in byAddress {
            let macs = Set(mappings.map { normalise($0.mac) }).filter { !$0.isEmpty }
            guard macs.count > 1 else { continue }
            out.append(Conflict(id: "dup-static-addr-\(key)", kind: .duplicateStaticAddress,
                                subject: mappings[0].ip, sides: macs.sorted()))
        }

        for (mac, mappings) in byMAC {
            let addresses = Set(mappings.map(\.ip))
            guard addresses.count > 1 else { continue }
            out.append(Conflict(id: "dup-static-mac-\(mac)", kind: .duplicateStaticMAC,
                                subject: mac, sides: addresses.sorted()))
        }

        // A reservation for an address somebody else currently holds.
        var activeLeases: [String: DHCPLease] = [:]
        for lease in leases where lease.state.lowercased().contains("active") && !lease.isStatic {
            guard let key = ClientAddress.key(lease.ip) else { continue }
            activeLeases[key] = lease
        }
        for mapping in staticMappings {
            guard let key = ClientAddress.key(mapping.ip), let lease = activeLeases[key] else { continue }
            let reserved = normalise(mapping.mac)
            let holder = normalise(lease.mac)
            guard !reserved.isEmpty, !holder.isEmpty, reserved != holder else { continue }
            out.append(Conflict(id: "static-leased-\(key)", kind: .staticAddressLeasedElsewhere,
                                subject: mapping.ip,
                                sides: ["reserved for \(reserved)", "leased to \(holder)"]))
        }

        return out
    }

    // MARK: Names

    private static func nameConflicts(hostOverrides: [HostOverride],
                                      leases: [DHCPLease],
                                      staticMappings: [StaticMapping]) -> [Conflict] {
        var out: [Conflict] = []

        var overrideAddresses: [String: Set<String>] = [:]
        for override in hostOverrides {
            let fqdn = "\(override.host).\(override.domain)".lowercased()
            guard !override.ip.isEmpty else { continue }
            overrideAddresses[fqdn, default: []].insert(override.ip)
        }
        for (fqdn, addresses) in overrideAddresses where addresses.count > 1 {
            out.append(Conflict(id: "override-\(fqdn)", kind: .overrideNameCollision,
                                subject: fqdn, sides: addresses.sorted()))
        }

        // Hostnames claimed by more than one device, across leases and
        // reservations. Compared by MAC, not by address: one device that has
        // moved between addresses is not two devices.
        var macsByName: [String: Set<String>] = [:]
        for lease in leases {
            guard let name = lease.hostname?.lowercased(), !name.isEmpty else { continue }
            let mac = normalise(lease.mac)
            if !mac.isEmpty { macsByName[name, default: []].insert(mac) }
        }
        for mapping in staticMappings {
            guard let name = mapping.hostname?.lowercased(), !name.isEmpty else { continue }
            let mac = normalise(mapping.mac)
            if !mac.isEmpty { macsByName[name, default: []].insert(mac) }
        }
        for (name, macs) in macsByName where macs.count > 1 {
            out.append(Conflict(id: "dup-name-\(name)", kind: .duplicateHostname,
                                subject: name, sides: macs.sorted()))
        }

        return out
    }

    /// MACs are compared in one form, and an unknown one is not a device.
    ///
    /// Two reasons this is not just `lowercased()`. pfSense is inconsistent
    /// about case across tables, and comparing raw reports a device as being
    /// in conflict with itself. And `DHCPLease` substitutes an em dash for a
    /// missing MAC, so two leases with no MAC would otherwise read as two
    /// devices holding one address — a conflict invented out of two absences.
    private static func normalise(_ mac: String) -> String {
        let trimmed = mac.lowercased().trimmingCharacters(in: .whitespaces)
        return (trimmed == "—" || trimmed == "-") ? "" : trimmed
    }
}
