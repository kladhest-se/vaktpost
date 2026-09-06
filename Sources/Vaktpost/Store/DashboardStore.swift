import Foundation
import SwiftUI
import WidgetKit

/// Holds every dashboard section independently so one failing endpoint (an
/// uninstalled package, a privilege the key lacks) degrades that card rather
/// than the whole screen.
@MainActor
final class DashboardStore: ObservableObject {

    enum Section: String, CaseIterable {
        case system, version, interfaces, gateways, services, leases, arp, statics
        case firewallLog, systemLog, authLog, dhcpLog, openvpnLog, states
        case openvpn, ipsec, wireguard
        case rules, aliases, portForwards
        case carp, configHistory, certificates, packages, tables
    }

    // MARK: Dependencies

    let registry: ServerRegistry
    let throughput = ThroughputTracker()

    @Published private(set) var client: APIClient
    @Published private(set) var activeProfile: ServerProfile?

    // MARK: Data

    @Published var system: SystemStatus?
    @Published var version: SystemVersion?
    @Published var states: StateTableSize?
    @Published var interfaces: [InterfaceStat] = []
    @Published var gateways: [GatewayStatus] = []
    @Published var services: [ServiceStatus] = []
    @Published var leases: [DHCPLease] = []
    @Published var arp: [ARPEntry] = []
    @Published var staticMappings: [StaticMapping] = []
    @Published var firewallLog: [LogLine] = []
    @Published var systemLog: [LogLine] = []
    @Published var authLog: [LogLine] = []
    @Published var dhcpLog: [LogLine] = []
    @Published var openvpnLog: [LogLine] = []

    @Published var openvpnServers: [OpenVPNServerStatus] = []
    @Published var openvpnClients: [OpenVPNServerStatus] = []
    @Published var ipsecSAs: [IPsecSA] = []
    @Published var wireguardTunnels: [WireGuardTunnel] = []
    @Published var wireguardPeers: [WireGuardPeer] = []

    @Published var rules: [FirewallRule] = []
    @Published var aliases: [FirewallAliasEntry] = []
    @Published var portForwards: [PortForward] = []

    @Published var carp: CARPStatus?
    @Published var configHistory: [ConfigRevision] = []
    @Published var certificates: [CertificateInfo] = []
    @Published var packages: [PackageInfo] = []

    /// Loaded on demand rather than on the refresh timer — see `loadTables()`.
    @Published var tables: [FirewallTable] = []
    @Published var isLoadingTables = false

    @Published var alerts: [VaktpostAlert] = []

    // MARK: Status

    @Published var errors: [Section: String] = [:]
    @Published var isRefreshing = false
    @Published var lastRefresh: Date?
    /// Fatal connection error — shown full-screen rather than per card.
    @Published var connectionError: String?

    private var timer: Task<Void, Never>?
    /// Endpoints backed by optional packages are retried rarely once they 404,
    /// so a firewall without WireGuard doesn't pay for four dead calls a minute.
    private var missingEndpoints: Set<Section> = []
    private var refreshCount = 0

    init(registry: ServerRegistry) {
        self.registry = registry
        let profile = registry.active ?? ServerProfile()
        self.activeProfile = registry.active
        self.client = APIClient(profile: profile)
    }

    var isConfigured: Bool { activeProfile?.isUsable ?? false }
    var profile: ServerProfile { activeProfile ?? ServerProfile() }

    // MARK: Server switching

    func switchTo(_ profile: ServerProfile) async {
        registry.setActive(profile)
        await rebind()
    }

    func saved(_ profile: ServerProfile) async {
        registry.upsert(profile)
        if registry.active?.id == profile.id { await rebind() }
    }

    func removed(_ profile: ServerProfile) async {
        registry.remove(profile)
        await rebind()
    }

    /// Points the client at whatever the registry now considers active and
    /// clears everything that belonged to the previous firewall.
    func rebind() async {
        stopAutoRefresh()
        clearData()
        throughput.reset()
        missingEndpoints.removeAll()
        activeProfile = registry.active
        await client.update(profile: registry.active ?? ServerProfile())
        guard isConfigured else {
            publishSnapshot()
            return
        }
        await refresh()
        startAutoRefresh()
    }

    private func clearData() {
        system = nil; version = nil; states = nil; carp = nil
        interfaces = []; gateways = []; services = []
        leases = []; arp = []; staticMappings = []
        firewallLog = []; systemLog = []
        authLog = []; dhcpLog = []; openvpnLog = []
        openvpnServers = []; openvpnClients = []; ipsecSAs = []
        wireguardTunnels = []; wireguardPeers = []
        rules = []; aliases = []; portForwards = []
        configHistory = []; certificates = []; packages = []; tables = []
        alerts = []; errors = [:]; connectionError = nil; lastRefresh = nil
    }

    // MARK: Refresh

    func refresh() async {
        guard isConfigured else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        refreshCount += 1

        var freshErrors: [Section: String] = [:]
        var fatal: String?
        var succeeded = 0
        var succeededSections: Set<Section> = []

        /// Runs one section and records whether it worked.
        ///
        /// `@discardableResult` because most callers only care that it ran;
        /// the throughput tracker is the exception and needs to know.
        @discardableResult
        func run(_ section: Section, optional: Bool = false,
                 _ work: () async throws -> Void) async -> Bool {
            // Retry a known-missing optional endpoint every 20th cycle only.
            if optional, missingEndpoints.contains(section), refreshCount % 20 != 0 { return false }
            do {
                try await work()
                missingEndpoints.remove(section)
                succeeded += 1
                succeededSections.insert(section)
                return true
            } catch let err as APIError {
                switch err {
                case .cancelled:
                    // Superseded or backgrounded. Say nothing, change nothing.
                    break
                case .unauthorized, .noAPIKey, .tls, .notConfigured, .badURL:
                    fatal = err.localizedDescription
                case .notFound:
                    if optional { missingEndpoints.insert(section) }
                    freshErrors[section] = err.localizedDescription
                default:
                    freshErrors[section] = err.localizedDescription
                }
            } catch {
                freshErrors[section] = error.localizedDescription
            }
            return false
        }

        // Core status
        await run(.system) { self.system = try await self.client.systemStatus() }
        await run(.version) { self.version = try await self.client.systemVersion() }
        await run(.states) { self.states = try await self.client.stateTableSize() }
        let interfacesLoaded = await run(.interfaces) {
            self.interfaces = try await self.client.interfaces()
        }
        await run(.gateways) { self.gateways = try await self.client.gateways() }
        await run(.services) { self.services = try await self.client.services() }

        // Only sample when this cycle actually fetched counters.
        //
        // On a failed fetch `interfaces` keeps its previous contents, and
        // ingesting those again produces a delta of zero over the elapsed
        // interval — a confident "0 bit/s" on a link that was passing traffic
        // the whole time, plus a notch in the chart that never happened.
        if interfacesLoaded { throughput.ingest(interfaces) }

        // Clients
        await run(.leases) { self.leases = try await self.client.leases() }
        await run(.arp) { self.arp = try await self.client.arpTable() }
        await run(.statics, optional: true) { self.staticMappings = try await self.client.staticMappings() }

        // Logs
        await run(.firewallLog) {
            self.firewallLog = try await self.client.firewallLog(limit: self.profile.logLimit)
        }
        await run(.systemLog) {
            self.systemLog = try await self.client.systemLog(limit: self.profile.logLimit)
        }
        await run(.authLog) {
            self.authLog = try await self.client.authLog(limit: self.profile.logLimit)
        }
        await run(.dhcpLog, optional: true) {
            self.dhcpLog = try await self.client.dhcpLog(limit: self.profile.logLimit)
        }
        await run(.openvpnLog, optional: true) {
            self.openvpnLog = try await self.client.openvpnLog(limit: self.profile.logLimit)
        }

        // VPN — all optional; a firewall may have none of these configured.
        await run(.openvpn, optional: true) {
            self.openvpnServers = try await self.client.openvpnServers()
            self.openvpnClients = (try? await self.client.openvpnClients()) ?? []
        }
        await run(.ipsec, optional: true) { self.ipsecSAs = try await self.client.ipsecSAs() }
        await run(.wireguard, optional: true) {
            self.wireguardTunnels = try await self.client.wireguardTunnels()
            self.wireguardPeers = (try? await self.client.wireguardPeers()) ?? []
        }

        // Firewall objects
        await run(.rules) { self.rules = try await self.client.firewallRules() }
        await run(.aliases) { self.aliases = try await self.client.firewallAliases() }
        await run(.portForwards) { self.portForwards = try await self.client.portForwards() }

        // System detail
        await run(.carp, optional: true) { self.carp = try await self.client.carp() }
        await run(.configHistory, optional: true) {
            self.configHistory = try await self.client.configHistory()
        }
        await run(.certificates, optional: true) {
            self.certificates = try await self.client.certificates()
        }
        await run(.packages, optional: true) {
            self.packages = try await self.client.packages()
        }

        errors = freshErrors

        // A fatal error only counts when nothing at all got through.
        //
        // One unlucky request should not put "Cannot reach firewall" above a
        // screen full of data fetched seconds ago. A real problem — a rejected
        // key, a failed pin, an unreachable host — fails every section, so this
        // still catches it while a transient blip stays invisible.
        connectionError = succeeded == 0 ? fatal : nil
        lastRefresh = Date()
        alerts = VaktpostAlert.build(from: self)
        publishSnapshot()
    }

    /// Fetches the pf tables. Called when the System screen appears, not by
    /// the refresh timer: the payload is dominated by `bogons`, which is large,
    /// static, and of no interest to anybody looking at this app.
    func loadTables() async {
        guard isConfigured, !isLoadingTables else { return }
        isLoadingTables = true
        defer { isLoadingTables = false }
        do {
            tables = try await client.tables()
            errors[.tables] = nil
        } catch {
            errors[.tables] = error.localizedDescription
        }
    }

    var blockedHosts: [FirewallTable] {
        tables.filter { $0.isNotable && $0.entryCount > 0 }
    }

    var packagesNeedingUpdate: [PackageInfo] { packages.filter(\.updateAvailable) }

    // MARK: Auto refresh

    func startAutoRefresh() {
        timer?.cancel()
        let interval = max(10, profile.refreshSeconds)
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.refresh()
            }
        }
    }

    func stopAutoRefresh() {
        timer?.cancel()
        timer = nil
    }

    // MARK: Widget snapshot

    private func publishSnapshot() {
        var snap = SharedSnapshot()
        snap.serverLabel = profile.displayName
        snap.capturedAt = lastRefresh ?? Date()
        snap.headline = headline
        snap.level = level(from: overallHealth)
        snap.interfacesUp = interfacesUp
        snap.interfacesTotal = interfaces.count
        snap.alertCount = alerts.filter { $0.severity == .bad || $0.severity == .warn }.count
        snap.gateways = gateways.prefix(3).map {
            .init(name: $0.name, status: $0.status, delayMS: $0.delayMS,
                  lossPercent: $0.lossPercent, level: level(from: $0.health))
        }
        if let wan = wanInterface, let point = throughput.latest(for: wan.device) {
            snap.wanInBps = point.inBps
            snap.wanOutBps = point.outBps
        }
        SharedSnapshot.write(snap)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func level(from health: Health) -> SharedSnapshot.Level {
        switch health {
        case .ok: return .ok
        case .warn: return .warn
        case .bad: return .bad
        case .idle, .info: return .idle
        }
    }

    // MARK: Derived

    var clients: [NetworkClient] {
        NetworkClient.merge(leases: leases, arp: arp, statics: staticMappings)
    }

    var interfacesUp: Int { interfaces.filter(\.isUp).count }

    /// Best guess at the uplink: the interface a gateway monitors, else one
    /// literally named WAN, else the first that is up.
    var wanInterface: InterfaceStat? {
        if let named = interfaces.first(where: { $0.name.lowercased().contains("wan") }) { return named }
        return interfaces.first(where: \.isUp)
    }

    var servicesDown: [ServiceStatus] {
        services.filter { $0.enabled != false && !$0.running }
    }

    var blockedRecently: Int {
        firewallLog.filter { $0.action == "block" || $0.action == "reject" }.count
    }

    var criticalAlertCount: Int {
        alerts.filter { $0.severity == .bad || $0.severity == .warn }.count
    }

    var hasVPN: Bool {
        !openvpnServers.isEmpty || !openvpnClients.isEmpty
            || !ipsecSAs.isEmpty || !wireguardTunnels.isEmpty
    }

    var overallHealth: Health {
        if connectionError != nil { return .bad }
        if alerts.contains(where: { $0.severity == .bad }) { return .bad }
        if alerts.contains(where: { $0.severity == .warn }) { return .warn }
        if interfaces.isEmpty && gateways.isEmpty { return .idle }
        return .ok
    }

    var headline: String {
        switch overallHealth {
        case .ok: return "All monitored paths healthy"
        case .warn: return "Degraded — \(criticalAlertCount) item\(criticalAlertCount == 1 ? "" : "s") need attention"
        case .bad: return "Attention required"
        case .idle, .info: return "Waiting for data"
        }
    }

    func logLines(matching ip: String) -> [LogLine] {
        guard !ip.isEmpty else { return [] }
        return firewallLog.filter {
            ($0.source?.contains(ip) ?? false)
                || ($0.destination?.contains(ip) ?? false)
                || $0.text.contains(ip)
        }
    }
}
