import Foundation

enum OverviewSection: String, CaseIterable, Identifiable {
    case status, interfaces, system, gateways, services, firewall, vpn, clients

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .status: return "Status"
        case .interfaces: return "Interfaces"
        case .system: return "System"
        case .gateways: return "Gateways"
        case .services: return "Services"
        case .firewall: return "Firewall"
        case .vpn: return "VPN"
        case .clients: return "Clients"
        }
    }

    var symbol: String {
        switch self {
        case .status: return "checkmark.shield"
        case .interfaces: return "network"
        case .system: return "cpu"
        case .gateways: return "routing.compose"
        case .services: return "power"
        case .firewall: return "lock.shield"
        case .vpn: return "lock.shield"
        case .clients: return "person.2"
        }
    }
}
