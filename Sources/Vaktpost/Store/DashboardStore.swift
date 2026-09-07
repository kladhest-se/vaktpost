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
        case openvpn, openvpnClients, ipsec, wireguard
        case firewall, aliases, portForwards
        case carp, configHistory, certificates, packages, tables
        case notices, filesystems, dyndns, hostOverrides, haproxy, acme
    }

    // MARK: Dependencies

    let registry: ServerRegistry
    let throughput = ThroughputTracker()

    /// A separate, longer history for the interface detail screen, which polls
    /// far more often than the dashboard refreshes. Kept apart so a minute
    /// spent watching one interface does not flush the half-hour of history
    /// every other screen is drawing from.
    let liveThroughput = ThroughputTracker(capacity: 180)
    @Published var liveInterfaceKey: String?
    @Published var liveError: String?
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

    @Published private(set) var client: FirewallClient
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
    @Published var hostOverrides: [HostOverride] = []
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
    @Published var notices: [SystemNotice] = []
    @Published var filesystems: [Filesystem] = []
    @Published var dyndns: [DyndnsEntry] = []

    // HAProxy, loaded when its screen opens rather than on the timer: a
    // firewall running it has many backends, and none of it changes minute to
    // minute.
    @Published var haproxyFrontends: [HAProxyFrontend] = []
    @Published var haproxyBackends: [HAProxyBackend] = []
    @Published var haproxyStatsAccessors: [String] = []
    @Published var haproxyInstalled = false
    private var hasLoadedHAProxy = false

    @Published var acmeCertificates: [ACMECertificate] = []
    @Published var acmeAccounts: [ACMEAccount] = []
    @Published var acmeInstalled = false
    private var hasLoadedACME = false

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
    /// Sections that have failed on the firewall, and how many times.
    ///
    /// A snippet that raises a PHP error leaves a permanent notice on the
    /// firewall, and a refresh timer turns that into one notice every thirty
    /// seconds — 78 of them in an afternoon, filling the bell icon and the
    /// app's own alert list with the same bug. Retrying less often is not
    /// enough: an app should not keep writing to somebody's firewall log
    /// because of a defect in itself.
    ///
    /// So after three faults a section is abandoned for the rest of the
    /// session. It comes back on a manual refresh, a firewall switch, or a
    /// relaunch — all of which are a person saying "try again".
    private var faultCounts: [Section: Int] = [:]
    private static let faultLimit = 3

    /// Previous CPU tick reading, for `deriveCPUUsage()`.
    private var lastCPUTicks: (total: Int, idle: Int)?
    private var refreshCount = 0

    init(registry: ServerRegistry) {
        let defaults = UserDefaults.standard
        mutedAlertCategories = Set(defaults.stringArray(forKey: "alerts.hidden.v2") ?? [])
        defaults.removeObject(forKey: "alerts.muted")   // superseded; see above
        alertsSilenced = defaults.bool(forKey: "alerts.silenced")
        acknowledgedAlerts = Set(defaults.stringArray(forKey: "alerts.acknowledged") ?? [])
        let tempWarn = defaults.double(forKey: "alerts.tempWarn")
        temperatureWarnOverride = tempWarn > 0 ? tempWarn : nil
        favouriteInterfaces = Set(defaults.stringArray(forKey: "interfaces.favourites") ?? [])
        let checkedAt = defaults.double(forKey: "packages.lastCheck")
        lastPackageCheck = checkedAt > 0 ? Date(timeIntervalSince1970: checkedAt) : nil
        self.registry = registry
        let profile = registry.active ?? ServerProfile()
        self.activeProfile = registry.active
        self.client = FirewallClient(profile: profile)
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
        lastCPUTicks = nil
        vpnThroughput.reset()
        systemMetrics.reset()
        gatewayMetrics.reset()
        missingEndpoints.removeAll()
        faultCounts.removeAll()
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
        store.hostOverrides = []
        store.firewallLog = []; store.systemLog = []; store.authLog = []; store.dhcpLog = []; store.openvpnLog = []
        store.openvpnServers = []; store.openvpnClients = []; store.ipsecSAs = []
        store.wireguardTunnels = []; store.wireguardPeers = []
        store.rules = []; store.aliases = []; store.portForwards = []
        store.configHistory = []; store.certificates = []; store.packages = []; store.tables = []
        store.notices = []; store.filesystems = []; store.dyndns = []
        store.isLoadingTables = false
        store.isLoadingFirewallObjects = false
        store.hasLoadedFirewallObjects = false
        store.hasLoadedHAProxy = false
        store.hasLoadedACME = false
        store.acmeCertificates = []; store.acmeAccounts = []
        store.haproxyFrontends = []; store.haproxyBackends = []
        store.alerts = []; store.errors = [:]; store.connectionError = nil; store.lastRefresh = nil
    }

    private func clearData() {
        Self.resetData(self)
        firewallLogIndex.removeAll()
    }

    // MARK: Refresh

    /// A manual refresh clears abandoned sections: the person asking is the
    /// signal that something may have changed.
    func refreshManually() async {
        faultCounts.removeAll()
        missingEndpoints.removeAll()
        await refresh()
    }

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
            } catch let err as RPCError {
                switch err {
                case .cancelled:
                    break
                case .unauthorized, .noCredentials, .tls, .notConfigured, .badURL, .forbidden:
                    fatal = err.localizedDescription
                case .fault:
                    // A PHP error in a snippet: the function is missing on this
                    // pfSense version, the shape is not what it expected, or
                    // the account lacks the privilege. Every one of these
                    // leaves a permanent notice on the firewall, so the section
                    // is counted and eventually abandoned.
                    let count = (faultCounts[section] ?? 0) + 1
                    faultCounts[section] = count
                    if optional { missingEndpoints.insert(section) }
                    freshErrors[section] = count >= Self.faultLimit
                        ? "\(err.localizedDescription) — stopped retrying, since each attempt writes a notice to the firewall. Pull to refresh to try again."
                        : err.localizedDescription
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
        deriveCPUUsage()
        seedFavouritesIfNeeded()
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
        await run(.hostOverrides, optional: true)
        // Aliases name clients, so they are needed on every refresh — not only
        // when somebody opens the Firewall tab. Rules and port forwards stay
        // on demand: 98 rules is a large payload for a screen most people
        // never look at.
        await run(.aliases, optional: true)
        guard !Task.isCancelled else { isRefreshing = false; return }

        // Logs — save previous counts before refreshing.
        let savedCounts = FirewallCounts(
            blocked: self.blockedRecently,
            rejected: self.rejectedRecently,
            passed: self.firewallLog.count - self.blockedRecently - self.rejectedRecently
        )
        await run(.firewallLog)
        prevFirewallCounts = savedCounts
        // Only the filter log is fetched on the timer, because the Overview
        // shows its counts. The other four are loaded when the Logs tab is
        // opened.
        //
        // Each is a quarter-megabyte read and a separate exec_php, and pfSense
        // serialises XML-RPC — so four of them added seconds to every refresh
        // for a screen that is usually not on the display.
        await loadSecondaryLogsIfNeeded()

        buildFirewallLogIndex()

        // VPN — all optional; a firewall may have none of these configured.
        await run(.openvpn, optional: true)
        await run(.openvpnClients, optional: true)
        await run(.ipsec, optional: true)
        await run(.wireguard, optional: true)

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
        await run(.certificates, optional: true)
        await run(.packages, optional: true)

        // Ask the repository at most every six hours, in the background.
        //
        // Not awaited: it takes seconds and the rest of the dashboard should
        // not wait behind it. Without this there would be no package alert
        // unless somebody remembered to press a button, which is not an alert.
        if shouldCheckPackages {
            Task { await self.checkPackageUpdates() }
        }
        await run(.filesystems)
        await run(.notices, optional: true)
        await run(.dyndns, optional: true)
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
        pruneAcknowledgements()
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
            if let fetched = try await client.pfTables() {
                tables = fetched
                blockedHosts = fetched.filter { $0.isNotable && $0.entryCount > 0 }
                errors[.tables] = nil
            } else {
                // Reachable only through pfctl, which is a shell, or a PHP
                // accessor this pfSense does not have. Said plainly rather
                // than shown as an empty list, which would read as "nothing
                // is blocked".
                tables = []
                blockedHosts = []
                errors[.tables] = "This pfSense exposes no way to read pf tables without a shell, so blocked hosts cannot be listed. Check Diagnostics → Tables in the webConfigurator."
            }
        } catch {
            errors[.tables] = error.localizedDescription
        }
    }

    /// Retries a single failed section. Used by the per-section retry button.
    func retrySection(_ section: Section) async {
        guard isConfigured else { return }
        await fetch(section)
        alerts = VaktpostAlert.build(from: self)
        pruneAcknowledgements()
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
        case .hostOverrides:
            hostOverrides = try await client.hostOverrides()
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
            let wg = try await client.wireguard()
            wireguardTunnels = wg.tunnels
            wireguardPeers = wg.peers
        case .firewall:
            await loadFirewallObjects()
        case .aliases:
            aliases = try await client.firewallAliases()
        case .portForwards:
            await loadFirewallObjects()
        case .carp:
            carp = try await client.carp()
        case .certificates:
            certificates = try await client.certificates()
        case .packages:
            packages = try await client.packages()
        case .filesystems:
            filesystems = try await client.filesystems()
        case .notices:
            notices = try await client.notices()
        case .dyndns:
            dyndns = try await client.dyndns()

        // Sections the refresh timer does not drive.
        //
        // `haproxy` is loaded by its own screen — a firewall running it has
        // dozens of backends and none of it changes minute to minute.
        // The other three are not reachable over XML-RPC without shelling out,
        // which the snippet rules forbid; they stay as cases so the enum is
        // exhaustive and the views referencing them compile with empty data.
        case .haproxy, .acme, .configHistory, .tables:
            break
        }
    }

    /// Fetches firewall rules, NAT port forwards and aliases on first use.
    ///
    /// These payloads are large and relatively static. Most users never look
    /// at them, so pulling them every refresh cycle wastes bandwidth and keeps
    /// them in memory for the entire session.
    /// The four logs that are not the filter log.
    ///
    /// Loaded when the Logs tab appears and refreshed while it is visible,
    /// rather than on every cycle.
    private(set) var wantsSecondaryLogs = false

    func beginSecondaryLogs() async {
        guard !wantsSecondaryLogs else { return }
        wantsSecondaryLogs = true
        await loadSecondaryLogsIfNeeded()
    }

    private func loadSecondaryLogsIfNeeded() async {
        guard wantsSecondaryLogs else { return }
        await runSection(.systemLog)
        await runSection(.authLog)
        await runSection(.dhcpLog)
        await runSection(.openvpnLog)
    }

    /// Runs one section outside the main refresh's bookkeeping.
    private func runSection(_ section: Section) async {
        guard isConfigured else { return }
        do {
            try await fetchOne(section)
            errors[section] = nil
        } catch {
            errors[section] = error.localizedDescription
        }
    }

    func loadHAProxy() async {
        guard isConfigured, !hasLoadedHAProxy else { return }
        hasLoadedHAProxy = true
        do {
            if let result = try await client.haproxy() {
                haproxyInstalled = true
                haproxyFrontends = result.frontends
                haproxyBackends = result.backends
                haproxyStatsAccessors = result.statsAccessors
            } else {
                haproxyInstalled = false
            }
            errors[.haproxy] = nil
        } catch {
            hasLoadedHAProxy = false   // let a pull-to-refresh try again
            errors[.haproxy] = error.localizedDescription
        }
    }

    func loadACME() async {
        guard isConfigured, !hasLoadedACME else { return }
        hasLoadedACME = true
        do {
            if let result = try await client.acme() {
                acmeInstalled = true
                acmeCertificates = result.certificates
                acmeAccounts = result.accounts
            } else {
                acmeInstalled = false
            }
            errors[.acme] = nil
        } catch {
            hasLoadedACME = false
            errors[.acme] = error.localizedDescription
        }
    }

    /// Polls one interface's counters until the task is cancelled.
    ///
    /// Driven by the detail screen's `.task`, so SwiftUI cancels it when the
    /// screen goes away — which matters more than usual here. Every poll is an
    /// `exec_php` that pfSense serialises against the webConfigurator, so a
    /// monitor left running in the background would make the web UI feel slow
    /// for as long as the app was open.
    ///
    /// Two seconds is a deliberate floor. It is fast enough to watch a
    /// transfer start and stop, and slow enough that the firewall is not doing
    /// nothing but answering this app.
    func monitorInterface(_ key: String, interval: Duration = .seconds(2)) async {
        liveInterfaceKey = key
        liveThroughput.reset()
        liveError = nil
        defer {
            liveInterfaceKey = nil
            liveError = nil
        }

        while !Task.isCancelled {
            do {
                let counters = try await client.interfaceCounters()
                guard !Task.isCancelled else { return }
                liveThroughput.ingest(counters)
                liveError = nil
            } catch let error as RPCError {
                if case .cancelled = error { return }
                liveError = error.localizedDescription
            } catch {
                liveError = error.localizedDescription
            }
            try? await Task.sleep(for: interval)
        }
    }

    /// Certificates close enough to expiry to badge.
    var expiringCertificateCount: Int {
        certificates.filter { !$0.isACME && ($0.health == .warn || $0.health == .bad) }.count
    }

    /// The certificate an ACME entry produced.
    ///
    /// Matched on name, which is what the package uses for both — a
    /// certificate named `example.se` in the store is the one the ACME entry
    /// `example.se` issued. Returns nil when nothing matches, which is a real
    /// state: an entry configured but never successfully run.
    func issuedCertificate(for entry: ACMECertificate) -> CertificateInfo? {
        certificates.first {
            !$0.isCA && ($0.descr == entry.name || $0.descr == entry.descr)
        }
    }

    /// ACME entries that will not renew themselves.
    var stalledACME: [ACMECertificate] { acmeCertificates.filter { !$0.enabled } }

    /// Backends HAProxy is not health-checking.
    ///
    /// Worth an alert: a backend with no check keeps receiving traffic after
    /// its servers die, and nothing else on the firewall will mention it.
    var unmonitoredBackends: [HAProxyBackend] {
        haproxyBackends.filter { !$0.isMonitored && !$0.servers.isEmpty }
    }

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
        // Aliases are not fetched here: the standard refresh already has them,
        // because they name clients.
        do {
            portForwards = try await client.portForwards()
            errors[.portForwards] = nil
        } catch {
            errors[.portForwards] = error.localizedDescription
        }
    }

    var packagesNeedingUpdate: [PackageInfo] { packages.filter(\.updateAvailable) }

    // MARK: Package updates

    @Published var isCheckingPackages = false
    @Published var packageCheckResult: String?

    /// When the repository was last asked.
    ///
    /// Persisted so a relaunch does not repeat the check, and so the screen can
    /// say how old the answer is — "no updates" from a week ago is not the same
    /// claim as "no updates" from this morning.
    @Published private(set) var lastPackageCheck: Date? {
        didSet {
            UserDefaults.standard.set(lastPackageCheck?.timeIntervalSince1970 ?? 0,
                                      forKey: "packages.lastCheck")
        }
    }

    /// Six hours.
    ///
    /// The check costs a network round trip from the firewall to the package
    /// repository, and package releases happen weekly at most — so this is
    /// about being told within a working day rather than within a minute.
    /// Without it there would be no package alert at all unless somebody
    /// remembered to press a button, which is not an alert.
    private static let packageCheckInterval: TimeInterval = 6 * 3600

    var packageCheckAge: String? {
        guard let lastPackageCheck else { return nil }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: lastPackageCheck, relativeTo: Date())
    }

    private var shouldCheckPackages: Bool {
        guard !isCheckingPackages else { return false }
        guard let last = lastPackageCheck else { return true }
        return Date().timeIntervalSince(last) > Self.packageCheckInterval
    }

    /// Checks installed packages against the repository.
    ///
    /// Deliberately manual. The call reaches the package repository over the
    /// network and takes seconds, and doing that on a thirty-second timer
    /// would make the firewall fetch a package index all day to answer a
    /// question that changes weekly.
    func checkPackageUpdates() async {
        guard isConfigured, !isCheckingPackages else { return }
        isCheckingPackages = true
        packageCheckResult = nil
        defer { isCheckingPackages = false }

        do {
            if let checked = try await client.packageUpdates() {
                // Merge rather than replace: the repository knows versions, the
                // configuration knows what is installed, and a package the
                // repository has dropped should not vanish from the list.
                let byName = Dictionary(uniqueKeysWithValues: checked.map { ($0.name, $0) })
                packages = packages.map { byName[$0.name] ?? $0 }
                for extra in checked where !packages.contains(where: { $0.name == extra.name }) {
                    packages.append(extra)
                }
                    lastPackageCheck = Date()
                let stale = packages.filter(\.updateAvailable).count
                packageCheckResult = stale == 0
                    ? "Everything is up to date."
                    : "\(stale) package\(stale == 1 ? "" : "s") can be updated."
            } else {
                packageCheckResult = "This pfSense has no way to check versions without a shell."
            }
            errors[.packages] = nil
        } catch {
            packageCheckResult = nil
            errors[.packages] = error.localizedDescription
        }
    }

    // MARK: Temperature threshold

    /// Where the temperature alert fires, in °C, or nil to follow the sensor.
    ///
    /// The built-in thresholds are a guess about hardware the app cannot see:
    /// 95 for a chipset, 80 for a CPU die. Those are reasonable defaults and
    /// wrong for somebody who knows their board runs at 80 and wants to hear
    /// about 82. Whoever owns the firewall knows what normal looks like on it,
    /// so they get to say.
    @Published var temperatureWarnOverride: Double? {
        didSet {
            UserDefaults.standard.set(temperatureWarnOverride ?? 0,
                                      forKey: "alerts.tempWarn")
        }
    }

    // MARK: Firmware

    @Published var isCheckingFirmware = false
    @Published var firmwareCheckResult: String?

    /// Re-reads the firmware version comparison.
    ///
    /// Cheap — `get_system_pkg_version()` does not hit the network the way the
    /// package check does — but still a button, because the answer it gives is
    /// the same one the last refresh already fetched unless something changed
    /// on the firewall.
    func checkFirmware() async {
        guard isConfigured, !isCheckingFirmware else { return }
        isCheckingFirmware = true
        defer { isCheckingFirmware = false }
        do {
            version = try await client.systemVersion()
            errors[.version] = nil
            firmwareCheckResult = version?.updateAvailable == true
                ? "An update is available."
                : "Checked just now — up to date."
        } catch {
            firmwareCheckResult = nil
            errors[.version] = error.localizedDescription
        }
    }

    // MARK: Favourite interfaces

    /// Interfaces pinned to the Overview.
    ///
    /// Fifteen interfaces is too many for a dashboard and one is too few — a
    /// firewall with two WANs and a handful of VLANs has three or four worth
    /// watching, and which three is a matter of what you run, not something
    /// the app can work out. Stored by series key so a VLAN and its parent
    /// lagg stay distinct.
    @Published var favouriteInterfaces: Set<String> = [] {
        didSet {
            UserDefaults.standard.set(Array(favouriteInterfaces), forKey: "interfaces.favourites")
        }
    }

    func toggleFavourite(_ iface: InterfaceStat) {
        if favouriteInterfaces.contains(iface.seriesKey) {
            favouriteInterfaces.remove(iface.seriesKey)
        } else {
            favouriteInterfaces.insert(iface.seriesKey)
        }
    }

    func isFavourite(_ iface: InterfaceStat) -> Bool {
        favouriteInterfaces.contains(iface.seriesKey)
    }

    /// What the Overview shows.
    ///
    /// Favourites if any are set, otherwise the WAN — the previous behaviour,
    /// kept as the default so the dashboard is useful before anybody has
    /// chosen anything.
    var overviewInterfaces: [InterfaceStat] {
        interfaces.filter { favouriteInterfaces.contains($0.seriesKey) }
    }

    /// Picks sensible defaults the first time interfaces are seen.
    ///
    /// WAN and LAN, because on almost every firewall those are the two worth a
    /// glance. Chosen once and recorded, so removing one sticks — a default
    /// that reasserts itself on every launch is not a default, it is a
    /// setting the person does not have.
    private func seedFavouritesIfNeeded() {
        guard !interfaces.isEmpty else { return }
        guard !UserDefaults.standard.bool(forKey: "interfaces.favouritesSeeded") else { return }
        UserDefaults.standard.set(true, forKey: "interfaces.favouritesSeeded")

        let wanted = interfaces.filter { iface in
            let name = iface.name.lowercased()
            let internalName = (iface.internalName ?? "").lowercased()
            return internalName == "wan" || internalName == "lan"
                || name.hasPrefix("wan") || name.hasPrefix("lan")
        }
        favouriteInterfaces.formUnion(wanted.map(\.seriesKey))
    }

    // MARK: Alert silencing

    /// Categories the person has chosen not to be told about.
    ///
    /// Alerts are derived on the device from status already fetched, so this
    /// filters what is shown rather than what is measured — a silenced
    /// category still appears on its own screen, it just stops driving the
    /// badge and the Overview banner.
    @Published var mutedAlertCategories: Set<String> = [] {
        didSet {
            // A new key, deliberately.
            //
            // `alerts.muted` was written by a build where the switches meant
            // the opposite thing, so anyone who touched that screen has a
            // stored set that now reads inverted — every kind silenced when
            // they had silenced nothing. Changing what a stored value means
            // without changing where it is stored is a migration, and this is
            // the cheapest correct one: start again from the default.
            UserDefaults.standard.set(Array(mutedAlertCategories), forKey: "alerts.hidden.v2")
        }
    }

    @Published var alertsSilenced: Bool = false {
        didSet { UserDefaults.standard.set(alertsSilenced, forKey: "alerts.silenced") }
    }

    /// Individual alerts the person has acknowledged.
    ///
    /// Keyed by signature rather than by identity, so the same condition
    /// reported a degree hotter stays acknowledged. Persisted, because an
    /// acknowledgement that expires when the app is backgrounded is not one.
    ///
    /// This is separate from silencing a whole category: silencing says "never
    /// tell me about certificates", acknowledging says "I have seen this one".
    /// Most things people want to stop seeing are the second kind.
    @Published var acknowledgedAlerts: Set<String> = [] {
        didSet {
            UserDefaults.standard.set(Array(acknowledgedAlerts), forKey: "alerts.acknowledged")
        }
    }

    func acknowledge(_ alert: VaktpostAlert) {
        acknowledgedAlerts.insert(alert.signature)
    }

    /// Forgets acknowledgements for conditions that are no longer true.
    ///
    /// Called after each refresh. Without it, acknowledging a gateway that was
    /// down would silence that gateway going down again next month — the
    /// acknowledgement would outlive the thing it was about.
    private func pruneAcknowledgements() {
        let present = Set(alerts.map(\.signature))
        let stale = acknowledgedAlerts.subtracting(present)
        if !stale.isEmpty { acknowledgedAlerts.subtract(stale) }
    }

    func unacknowledgeAll() {
        acknowledgedAlerts.removeAll()
    }

    /// Acknowledged conditions that are still true.
    var acknowledgedButPresent: [VaktpostAlert] {
        alerts.filter { acknowledgedAlerts.contains($0.signature) }
    }

    /// Alerts after silencing. Everything on screen uses this; `alerts` stays
    /// the unfiltered truth so the Alerts screen can say what is hidden.
    var visibleAlerts: [VaktpostAlert] {
        if alertsSilenced { return [] }
        return alerts.filter {
            !mutedAlertCategories.contains($0.category.rawValue)
                && !acknowledgedAlerts.contains($0.signature)
        }
    }

    /// Hidden by silencing, not by acknowledgement.
    ///
    /// Subtracting one count from the other would include acknowledged alerts,
    /// which are reported separately — the screen would say the same alert was
    /// hidden twice for two different reasons.
    var silencedAlertCount: Int {
        if alertsSilenced { return alerts.count }
        return alerts.filter { mutedAlertCategories.contains($0.category.rawValue) }.count
    }

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
    func interfaceLabel(for raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let lowered = raw.lowercased()
        for iface in interfaces {
            if iface.device.lowercased() == lowered { return iface.name }
            if iface.internalName?.lowercased() == lowered { return iface.name }
            if iface.name.lowercased() == lowered { return iface.name }
        }
        return raw
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

    /// One value with its aliases replaced by what they contain.
    ///
    /// Takes an address or a port, never `host:port` — splitting a joined
    /// field on ":" cannot work for IPv6, where the address is full of them.
    /// The two halves are resolved separately by the caller.
    ///
    /// Long lists are capped: `alias_url_cloudflare` holds twenty-two networks
    /// and a rule row is not the place for them.
    func resolvedValue(_ value: String, limit: Int = 3) -> String {
        let name = value.trimmingCharacters(in: .whitespaces)
        guard let members = resolveAlias(name), !members.isEmpty else { return name }
        if members.count <= limit { return members.joined(separator: ", ") }
        return members.prefix(limit).joined(separator: ", ") + " +\(members.count - limit)"
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
        if let client = clients.first(where: { $0.ip == ip }), client.name != ip {
            return client.name
        }
        return nil
    }

    /// Turns cumulative CPU ticks into a percentage.
    ///
    /// `cpu_usage()` on pfSense reports total and idle ticks since boot, not a
    /// rate — the same shape as the interface byte counters. A percentage is
    /// the change in idle ticks against the change in total ticks between two
    /// samples, so like throughput it needs two refreshes before it can show
    /// anything, and shows nothing rather than zero until then.
    private func deriveCPUUsage() {
        guard var snapshot = system,
              let total = snapshot.cpuTicksTotal,
              let idle = snapshot.cpuTicksIdle
        else { return }
        defer { lastCPUTicks = (total, idle) }

        guard let previous = lastCPUTicks else { return }
        let totalDelta = total - previous.total
        let idleDelta = idle - previous.idle

        // Counters reset on reboot, and a zero interval means the same sample
        // twice. Either way, start again rather than chart a spike.
        guard totalDelta > 0, idleDelta >= 0, idleDelta <= totalDelta else {
            lastCPUTicks = nil
            return
        }

        let busy = (1 - Double(idleDelta) / Double(totalDelta)) * 100
        snapshot.cpuUsage = min(100, max(0, busy))
        system = snapshot
    }

    /// Dyndns entries whose last-pushed address no longer matches the address
    /// on the interface they watch.
    ///
    /// This is the failure that matters and the one nothing else reports:
    /// pfSense keeps no update history, so a dyndns client that quietly stopped
    /// working looks identical to one that has had nothing to do. Comparing the
    /// cache against the live interface address catches it.
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

    var criticalNotices: [SystemNotice] { notices }

    var fullFilesystems: [Filesystem] {
        filesystems.filter { $0.health == .warn || $0.health == .bad }
    }

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
        NetworkClient.merge(leases: leases, arp: arp, statics: staticMappings,
                            overrides: hostOverrides, aliases: aliases)
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

    /// The tab badge. Silenced categories do not contribute — a badge that
    /// counts things the person has asked not to see is just a red dot they
    /// learn to ignore.
    var criticalAlertCount: Int {
        visibleAlerts.filter { $0.severity == .bad || $0.severity == .warn }.count
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
