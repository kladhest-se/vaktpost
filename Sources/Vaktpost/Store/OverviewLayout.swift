import Foundation
import Observation
import SwiftUI

/// Holds the overview-derived properties that DashboardStore computes each
/// refresh cycle.
///
/// Embedded as ``overviewLayout`` in ``DashboardStore`` so the rest of the
/// store can reach them via `store.overviewLayout.xxx`. Each property is a
/// computed value derived from the data the store already holds — no fetching,
/// just transformation.
@MainActor
@Observable
final class OverviewLayout {

    // MARK: Parent references (set by DashboardStore after init)

    /// Weak reference to the parent store's alert manager.
    weak var alertManager: AlertManager?

    /// Weak reference to the parent store's gateway manager.
    weak var gatewayManager: GatewayManager?

    // MARK: Data (populated via sync(from:))

    /// DHCP leases.
    var leases: [DHCPLease] = []

    /// ARP table entries.
    var arp: [ARPEntry] = []

    /// Static mappings.
    var staticMappings: [StaticMapping] = []

    /// DNS host overrides.
    var hostOverrides: [HostOverride] = []

    /// Firewall aliases.
    var aliases: [FirewallAliasEntry] = []

    /// Interface statistics.
    var interfaces: [InterfaceStat] = []

    /// Services status.
    var services: [ServiceStatus] = []

    /// Firewall log lines.
    var firewallLog: [LogLine] = []

    /// Firewall counts from the previous refresh cycle.
    var prevFirewallCounts: DashboardStore.FirewallCounts = DashboardStore.FirewallCounts()

    /// OpenVPN servers.
    var openvpnServers: [OpenVPNServerStatus] = []

    /// OpenVPN client connections.
    var openvpnClients: [OpenVPNServerStatus] = []

    /// IPsec SAs.
    var ipsecSAs: [IPsecSA] = []

    /// WireGuard tunnels.
    var wireguardTunnels: [WireGuardTunnel] = []

    /// WireGuard peers.
    var wireguardPeers: [WireGuardPeer] = []

    /// Certificate info.
    var certificates: [CertificateInfo] = []

    /// System notices.
    var notices: [SystemNotice] = []

    /// Filesystem status.
    var filesystems: [Filesystem] = []

    /// Dyndns entries.
    var dyndns: [DyndnsEntry] = []

    /// Fatal connection error message, or nil.
    var connectionError: String?

    // MARK: Derived properties

    /// All clients merged from DHCP leases, ARP entries, static mappings and
    /// DNS host overrides.
    var clients: [NetworkClient] {
        NetworkClient.merge(leases: leases, arp: arp, statics: staticMappings,
                            overrides: hostOverrides, aliases: aliases)
    }

    /// Number of interfaces that are up.
    var interfacesUp: Int { interfaces.filter(\.isUp).count }

    /// Best guess at the uplink: the interface a gateway monitors, else one
    /// literally named WAN, else the first that is up.
    var wanInterface: InterfaceStat? {
        if let named = interfaces.first(where: { $0.name.lowercased().contains("wan") }) { return named }
        return interfaces.first(where: \.isUp)
    }

    // MARK: Services

    /// Services that are enabled but not running.
    var servicesDown: [ServiceStatus] {
        services.filter { $0.enabled != false && !$0.running }
    }

    // MARK: Firewall log counters

    /// Count of block actions in the current firewall log.
    var blockedRecently: Int {
        firewallLog.filter { $0.action == "block" }.count
    }

    /// Count of reject actions in the current firewall log.
    var rejectedRecently: Int {
        firewallLog.filter { $0.action == "reject" }.count
    }

    /// Count of pass actions in the current firewall log.
    var passedRecently: Int {
        firewallLog.count - blockedRecently - rejectedRecently
    }

    /// Difference between current and previous block count, or nil when the
    /// previous count is zero.
    var blockedDelta: Int? {
        guard prevFirewallCounts.blocked > 0 else { return nil }
        return blockedRecently - prevFirewallCounts.blocked
    }

    /// Difference between current and previous reject count, or nil when the
    /// previous count is zero.
    var rejectedDelta: Int? {
        guard prevFirewallCounts.rejected > 0 else { return nil }
        return rejectedRecently - prevFirewallCounts.rejected
    }

    /// Difference between current and previous pass count, or nil when the
    /// previous count is zero.
    var passedDelta: Int? {
        guard prevFirewallCounts.passed > 0 else { return nil }
        return passedRecently - prevFirewallCounts.passed
    }

    // MARK: VPN health

    /// Whether any VPN servers/tunnels are configured.
    var hasVPN: Bool {
        !openvpnServers.isEmpty || !openvpnClients.isEmpty
            || !ipsecSAs.isEmpty || !wireguardTunnels.isEmpty
    }

    /// Overall VPN health: ok when something is active, warn when configured
    /// but nothing is up, info when nothing is configured.
    var vpnHealth: Health {
        let activeServers = openvpnServers.filter { $0.health == .ok || $0.health == .idle || !$0.connections.isEmpty }.count
        let activeClients = openvpnClients.filter { $0.health == .ok || $0.health == .idle || !$0.connections.isEmpty }.count
        let activeTunnels = wireguardTunnels.filter(\.isUp).count
        let activePeers = wireguardPeers.filter(\.hasLiveStatus).count
        let active = activeServers + activeClients + activeTunnels + ipsecSAs.count + activePeers
        if hasVPN && active == 0 { return .warn }
        if hasVPN && active > 0 { return .ok }
        return .info
    }

    // MARK: Top talkers

    /// Top talkers ranked by how many data sources mention each MAC.
    ///
    /// A device that appears in DHCP, ARP, and static mappings is likely
    /// important or active. Devices appearing in only one source are less
    /// likely to be in the user's immediate concern.
    var topTalkers: [TopTalker] {
        var counts: [String: (mac: String, ip: String, hostname: String?, sources: Int)] = [:]

        func record(_ mac: String, _ ip: String, hostname: String?, sourceCount: Int) {
            let key = ClientAddress.key(mac) ?? mac
            let existing = counts[key]
            if var entry = existing {
                entry.sources += sourceCount
                counts[key] = entry
            } else {
                counts[key] = (mac: mac, ip: ip, hostname: hostname, sources: sourceCount)
            }
        }

        for lease in leases {
            record(lease.mac, lease.ip, hostname: lease.hostname, sourceCount: 1)
        }

        for entry in arp {
            record(entry.mac, entry.ip, hostname: entry.hostname, sourceCount: 1)
        }

        for mapping in staticMappings {
            record(mapping.mac, mapping.ip, hostname: mapping.hostname, sourceCount: 1)
        }

        for override in hostOverrides {
            if let mac = ClientAddress.key(override.ip)?.split(separator: ":").last.map(String.init) {
                record(mac, override.ip, hostname: override.fqdn, sourceCount: 1)
            }
        }

        return counts.values
            .sorted { $0.sources > $1.sources || ($0.sources == $1.sources && $0.ip < $1.ip) }
            .prefix(8)
            .map { TopTalker(mac: $0.mac, ip: $0.ip, hostname: $0.hostname, sourceCount: $0.sources) }
    }

    // MARK: Health aggregation

    /// The overall health derived from all data sources.
    ///
    /// - `.bad` when there is a connection error or a bad alert.
    /// - `.warn` when there is a warning alert.
    /// - `.idle` when no interfaces or gateways have been loaded yet.
    /// - `.ok` otherwise.
    var overallHealth: Health {
        if connectionError != nil { return .bad }
        if alertManager?.alerts.contains(where: { $0.severity == .bad }) ?? false { return .bad }
        if alertManager?.alerts.contains(where: { $0.severity == .warn }) ?? false { return .warn }
        if interfaces.isEmpty && gatewayManager?.gateways.isEmpty ?? true { return .idle }
        return .ok
    }

    /// A one-line summary for the Overview header.
    var headline: String {
        let count = alertManager?.criticalAlertCount ?? 0
        switch overallHealth {
        case .ok: return "All monitored paths healthy"
        case .warn: return "Degraded — \(count) item\(count == 1 ? "" : "s") need attention"
        case .bad: return "Attention required"
        case .idle, .info: return "Waiting for data"
        }
    }

    // MARK: Additional derived lists

    /// Dyndns entries whose last-pushed address no longer matches the address
    /// on the interface they watch.
    var staleDyndns: [DyndnsEntry] {
        dyndns.filter { entry in
            guard entry.enabled, let cached = entry.cachedAddress, !cached.isEmpty else { return false }
            guard let ifName = entry.interfaceName,
                  let iface = interfaces.first(where: {
                      $0.device == ifName || $0.name.lowercased() == ifName.lowercased()
                  }),
                  let current = iface.ipv4, !current.isEmpty
            else { return false }
            return cached != current
        }
    }

    /// System notices from the firewall (all of them — the alert builder
    /// filters which ones become VaktpostAlerts).
    var criticalNotices: [SystemNotice] { notices }

    /// Filesystems that are near or past capacity.
    var fullFilesystems: [Filesystem] {
        filesystems.filter { $0.health == .warn || $0.health == .bad }
    }

    // MARK: Sync from DashboardStore

    /// Copies the relevant data from ``DashboardStore`` into this manager's
    /// storage so the computed properties above work correctly.
    ///
    /// Called at the end of ``DashboardStore/refresh()``.
    func sync(from store: DashboardStore) {
        leases = store.leases
        arp = store.arp
        staticMappings = store.staticMappings
        hostOverrides = store.hostOverrides
        aliases = store.aliases
        interfaces = store.interfaces
        services = store.services
        firewallLog = store.firewallLog
        prevFirewallCounts = store.prevFirewallCounts
        openvpnServers = store.openvpnServers
        openvpnClients = store.openvpnClients
        ipsecSAs = store.ipsecSAs
        wireguardTunnels = store.wireguardTunnels
        wireguardPeers = store.wireguardPeers
        certificates = store.certificates
        notices = store.notices
        filesystems = store.filesystems
        dyndns = store.dyndns
        connectionError = store.connectionError
    }
}
