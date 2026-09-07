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
        case openvpn, openvpnClients, ipsec, wireguard, wireguardPeers
        case firewall, aliases, portForwards
        case carp, configHistory, certificates, packages, tables
    }

    // MARK: Dependencies

    let registry: ServerRegistry
    let throughput = ThroughputTracker()
    let vpnThroughput = ThroughputTrackerV2()
    let systemMetrics = MetricTracker<String, Double>()
    let gatewayMetrics = GatewayMetricTracker()
    let stateHistory = StateHistoryTracker()
    var prevFirewallCounts = FirewallCounts()

    struct FirewallCounts {
        var blocked: Int = 0
        var rejected: Int = 0
        var passed: Int = 0
    }

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

    /// Pre-computed index mapping IP prefixes to positions in `firewallLog`.
    /// Built during refresh so `logLines(matching:)` is O(k) instead of O(n).
    private var firewallLogIndex: [String: [Int]] = [:]

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
    @Published var blockedHosts: [FirewallTable] = []
    @Published var isLoadingTables = false

    /// Rules, aliases and port forwards are loaded lazily when the user
    /// first navigates to the Firewall screen, then refreshed on the timer.
    /// The payloads are large and most users never look, so pulling them
    /// every thirty seconds is wasted bandwidth.
    @Published var isLoadingFirewallObjects = false
    private var hasLoadedFirewallObjects = false

    @Published var alerts: [VaktpostAlert] = []

    // MARK: Status

    @Published var errors: [Section: String] = [:]
    @Published var isRefreshing = false
    @Published var lastRefresh: Date?
    /// Fatal connection error — shown full-screen rather than per card.
    @Published var connectionError: String?

    /// Theme selection name written to the widget snapshot.
    var themeName: String = "auto"

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
        vpnThroughput.reset()
        systemMetrics.reset()
        gatewayMetrics.reset()
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

    /// Closure that resets all data properties to their initial (empty) state.
    /// Automatically stays in sync because new properties are added here.
    private static let resetData: (DashboardStore) -> Void = { store in
        store.system = nil; store.version = nil; store.states = nil; store.carp = nil
        store.interfaces = []; store.gateways = []; store.services = []
        store.leases = []; store.arp = []; store.staticMappings = []
        store.firewallLog = []; store.systemLog = []; store.authLog = []; store.dhcpLog = []; store.openvpnLog = []
        store.openvpnServers = []; store.openvpnClients = []; store.ipsecSAs = []
        store.wireguardTunnels = []; store.wireguardPeers = []
        store.rules = []; store.aliases = []; store.portForwards = []
        store.configHistory = []; store.certificates = []; store.packages = []; store.tables = []
        store.isLoadingTables = false
        store.isLoadingFirewallObjects = false
        store.hasLoadedFirewallObjects = false
        store.alerts = []; store.errors = [:]; store.connectionError = nil; store.lastRefresh = nil
    }

    private func clearData() {
        Self.resetData(self)
        firewallLogIndex.removeAll()
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
        @discardableResult
        func run(_ section: Section, optional: Bool = false) async -> Bool {
            // Retry a known-missing optional endpoint every 20th cycle only.
            guard !optional || !missingEndpoints.contains(section) || refreshCount % 20 == 0 else { return false }
            do {
                try await fetchOne(section)
                missingEndpoints.remove(section)
                succeeded += 1
                succeededSections.insert(section)
                return true
            } catch let err as APIError {
                switch err {
                case .cancelled:
                    break
                case .unauthorized, .noAPIKey, .tls, .notConfigured, .badURL, .forbidden:
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
        await run(.system)
        await run(.version)
        await run(.states)
        if let current = states?.current {
            stateHistory.ingest(current: current)
        }
        let interfacesLoaded = await run(.interfaces)
        await run(.gateways)
        for gw in gateways {
            gatewayMetrics.ingest(
                key: gw.name,
                delayMS: gw.delayMS,
                lossPercent: gw.lossPercent
            )
        }
        await run(.services)

        // Only sample when this cycle actually fetched counters.
        if interfacesLoaded { throughput.ingest(interfaces) }
        if let sys = system {
            if let cpu = sys.cpuUsage { systemMetrics.ingest(key: "cpu", value: cpu) }
            if let mem = sys.memUsage { systemMetrics.ingest(key: "mem", value: mem) }
            if let disk = sys.diskUsage { systemMetrics.ingest(key: "disk", value: disk) }
            if let swap = sys.swapUsage { systemMetrics.ingest(key: "swap", value: swap) }
        }
        guard !Task.isCancelled else { isRefreshing = false; return }

        // Clients
        await run(.leases)
        await run(.arp)
        await run(.statics, optional: true)
        guard !Task.isCancelled else { isRefreshing = false; return }

        // Logs — save previous counts before refreshing.
        let savedCounts = FirewallCounts(
            blocked: self.blockedRecently,
            rejected: self.rejectedRecently,
            passed: self.firewallLog.count - self.blockedRecently - self.rejectedRecently
        )
        await run(.firewallLog)
        prevFirewallCounts = savedCounts
        await run(.systemLog)
        await run(.authLog)
        await run(.dhcpLog, optional: true)
        await run(.openvpnLog, optional: true)

        buildFirewallLogIndex()

        // VPN — all optional; a firewall may have none of these configured.
        await run(.openvpn, optional: true)
        await run(.openvpnClients, optional: true)
        await run(.ipsec, optional: true)
        await run(.wireguard, optional: true)
        await run(.wireguardPeers, optional: true)

        // Track VPN throughput from cumulative byte counters.
        for srv in openvpnServers {
            for conn in srv.connections {
                if let rx = conn.bytesReceived, let tx = conn.bytesSent {
                    vpnThroughput.ingest(key: "ovpn:\(srv.name)/\(conn.commonName)", inBytes: rx, outBytes: tx)
                }
            }
        }
        for cli in openvpnClients {
            for conn in cli.connections {
                if let rx = conn.bytesReceived, let tx = conn.bytesSent {
                    vpnThroughput.ingest(key: "ovpn-cli:\(cli.name)/\(conn.commonName)", inBytes: rx, outBytes: tx)
                }
            }
        }
        for peer in wireguardPeers {
            if let rx = peer.bytesReceived, let tx = peer.bytesSent {
                vpnThroughput.ingest(key: "wg:\(peer.publicKey)", inBytes: rx, outBytes: tx)
            }
        }

        guard !Task.isCancelled else { isRefreshing = false; return }

        // System detail
        await run(.carp, optional: true)
        await run(.configHistory, optional: true)
        await run(.certificates, optional: true)
        await run(.packages, optional: true)
        guard !Task.isCancelled else { isRefreshing = false; return }

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
            blockedHosts = tables.filter { $0.isNotable && $0.entryCount > 0 }
            errors[.tables] = nil
        } catch {
            errors[.tables] = error.localizedDescription
        }
    }

    /// Retries a single failed section. Used by the per-section retry button.
    func retrySection(_ section: Section) async {
        guard isConfigured else { return }
        await fetch(section)
        alerts = VaktpostAlert.build(from: self)
        publishSnapshot()
    }

    /// Fetches a single section from the API and updates the store.
    /// Called by `retrySection` and can be called directly for on-demand refresh.
    func fetch(_ section: Section) async {
        errors[section] = nil
        do {
            try await fetchOne(section)
        } catch {
            errors[section] = error.localizedDescription
        }
    }

    /// Core fetch logic for one section. Called by both `refresh()` and `fetch(section:)`.
    /// Throws the underlying API error so refresh() can classify it properly.
    private func fetchOne(_ section: Section) async throws {
        switch section {
        case .system:
            system = try await client.systemStatus()
        case .version:
            version = try await client.systemVersion()
        case .states:
            states = try await client.stateTableSize()
        case .interfaces:
            interfaces = try await client.interfaces()
        case .gateways:
            gateways = try await client.gateways()
        case .services:
            services = try await client.services()
        case .leases:
            leases = try await client.leases()
        case .arp:
            arp = try await client.arpTable()
        case .statics:
            staticMappings = try await client.staticMappings()
        case .firewallLog:
            firewallLog = try await client.firewallLog(limit: profile.logLimit)
        case .systemLog:
            systemLog = try await client.systemLog(limit: profile.logLimit)
        case .authLog:
            authLog = try await client.authLog(limit: profile.logLimit)
        case .dhcpLog:
            dhcpLog = try await client.dhcpLog(limit: profile.logLimit)
        case .openvpnLog:
            openvpnLog = try await client.openvpnLog(limit: profile.logLimit)
        case .openvpn:
            openvpnServers = try await client.openvpnServers()
        case .openvpnClients:
            openvpnClients = try await client.openvpnClients()
        case .ipsec:
            ipsecSAs = try await client.ipsecSAs()
        case .wireguard:
            wireguardTunnels = try await client.wireguardTunnels()
        case .wireguardPeers:
            wireguardPeers = try await client.wireguardPeers()
        case .firewall:
            await loadFirewallObjects()
        case .aliases:
            await loadFirewallObjects()
        case .portForwards:
            await loadFirewallObjects()
        case .carp:
            carp = try await client.carp()
        case .configHistory:
            configHistory = try await client.configHistory()
        case .certificates:
            certificates = try await client.certificates()
        case .packages:
            packages = try await client.packages()
        case .tables:
            await loadTables()
        }
    }

    /// Fetches firewall rules, NAT port forwards and aliases on first use.
    ///
    /// These payloads are large and relatively static. Most users never look
    /// at them, so pulling them every refresh cycle wastes bandwidth and keeps
    /// them in memory for the entire session.
    func loadFirewallObjects() async {
        guard isConfigured, !isLoadingFirewallObjects, !hasLoadedFirewallObjects else { return }
        isLoadingFirewallObjects = true
        hasLoadedFirewallObjects = true
        defer { isLoadingFirewallObjects = false }
        do {
            rules = try await client.firewallRules()
            errors[.firewall] = nil
        } catch {
            errors[.firewall] = error.localizedDescription
        }
        do {
            aliases = try await client.firewallAliases()
            errors[.aliases] = nil
        } catch {
            errors[.aliases] = error.localizedDescription
        }
        do {
            portForwards = try await client.portForwards()
            errors[.portForwards] = nil
        } catch {
            errors[.portForwards] = error.localizedDescription
        }
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
        snap.refreshSeconds = profile.refreshSeconds
        snap.themeName = themeName
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
        firewallLog.filter { $0.action == "block" }.count
    }

    var rejectedRecently: Int {
        firewallLog.filter { $0.action == "reject" }.count
    }

    var passedRecently: Int {
        firewallLog.count - blockedRecently - rejectedRecently
    }

    var blockedDelta: Int? {
        guard prevFirewallCounts.blocked > 0 else { return nil }
        return blockedRecently - prevFirewallCounts.blocked
    }

    var rejectedDelta: Int? {
        guard prevFirewallCounts.rejected > 0 else { return nil }
        return rejectedRecently - prevFirewallCounts.rejected
    }

    var passedDelta: Int? {
        guard prevFirewallCounts.passed > 0 else { return nil }
        return passedRecently - prevFirewallCounts.passed
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

        // Extract a 3-octet prefix from the IP for index lookup.
        let components = ip.split(separator: ".").prefix(3)
        let prefix = components.joined(separator: ".")

        // If the IP has at least 3 octets, use the index for fast lookup.
        if components.count == 3, let indices = firewallLogIndex[prefix] {
            // Gather unique lines from the index, preserving order.
            var seen = Set<Int>()
            var result: [LogLine] = []
            for idx in indices where seen.insert(idx).inserted {
                let line = firewallLog[idx]
                if line.source?.contains(ip) ?? false
                    || line.destination?.contains(ip) ?? false
                    || line.text.contains(ip) {
                    result.append(line)
                }
            }
            return result
        }

        // Fall back to linear scan for partial matches or incomplete IPs.
        return firewallLog.filter {
            ($0.source?.contains(ip) ?? false)
                || ($0.destination?.contains(ip) ?? false)
                || $0.text.contains(ip)
        }
    }

    /// Builds `firewallLogIndex` by scanning every log line once.
    private func buildFirewallLogIndex() {
        firewallLogIndex.removeAll()
        for (index, line) in firewallLog.enumerated() {
            if let src = line.source {
                let key = src.split(separator: ".").prefix(3).joined(separator: ".")
                firewallLogIndex[key, default: []].append(index)
            }
            if let dst = line.destination {
                let key = dst.split(separator: ".").prefix(3).joined(separator: ".")
                firewallLogIndex[key, default: []].append(index)
            }
        }
    }
}
