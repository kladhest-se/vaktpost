import Foundation

enum OverviewSection: String, CaseIterable, Identifiable {
    case alerts, status, interfaces, system, gateways, services, firewall, vpnServers, vpnClients, clients, dnsbl

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .alerts: return "Alerts"
        case .status: return "Status"
        case .interfaces: return "Interfaces"
        case .system: return "System"
        case .gateways: return "Gateways"
        case .services: return "Services"
        case .firewall: return "Firewall"
        case .vpnServers: return "VPN servers"
        case .vpnClients: return "VPN clients"
        case .clients: return "Clients"
        case .dnsbl: return "DNSBL"
        }
    }

    /// What a stored section name from an older build turns into.
    ///
    /// The layout is persisted as raw values, and an unknown one is silently
    /// dropped. Splitting `vpn` in two without this would have deleted the VPN
    /// section from the dashboard of everybody who had it — and put its
    /// replacements in the hidden list, where they would have to be found and
    /// re-added by hand.
    static func replacing(_ rawValue: String) -> [OverviewSection]? {
        switch rawValue {
        case "vpn": return [.vpnServers, .vpnClients]
        default: return nil
        }
    }

    /// Rewrite a stored layout so it contains no names this build replaces.
    ///
    /// Expanding `vpn` at read time was half a migration, and half a migration
    /// is a bug. The stored array kept the old name, so hiding VPN servers
    /// removed `vpnServers` — which was never in storage — and left `vpn`
    /// behind. The next load expanded it again, and both VPN sections
    /// reappeared the moment anything else was added.
    ///
    /// Returns nil when there is nothing to change, so the common case writes
    /// nothing.
    ///
    /// Names this build does not recognise are kept rather than dropped. They
    /// cannot be displayed, but they belong to whoever stored them — a build
    /// that knows about them should still find them after this one has run.
    static func migrate(storedNames: [String]) -> [String]? {
        var out: [String] = []
        var seen = Set<String>()
        var changed = false

        for raw in storedNames {
            if let replacements = replacing(raw) {
                changed = true
                for section in replacements where seen.insert(section.rawValue).inserted {
                    out.append(section.rawValue)
                }
            } else if seen.insert(raw).inserted {
                out.append(raw)
            } else {
                changed = true
            }
        }

        return changed ? out : nil
    }

    var symbol: String {
        switch self {
        case .alerts: return "bell.badge"
        case .status: return "checkmark.shield"
        case .interfaces: return "network"
        case .system: return "cpu"
        case .gateways: return "routing.compose"
        case .services: return "power"
        case .firewall: return "lock.shield"
        case .vpnServers: return "lock.shield"
        case .vpnClients: return "arrow.up.forward.app"
        case .clients: return "person.2"
        case .dnsbl: return "shield.lefthalf.filled"
        }
    }
}
