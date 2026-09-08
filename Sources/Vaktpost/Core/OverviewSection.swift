import Foundation

enum OverviewSection: String, CaseIterable, Identifiable {
    case status, interfaces, system, gateways, services, firewall

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .status: return "Status"
        case .interfaces: return "Interfaces"
        case .system: return "System"
        case .gateways: return "Gateways"
        case .services: return "Services"
        case .firewall: return "Firewall"
        }
    }
}
