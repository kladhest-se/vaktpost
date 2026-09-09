import Foundation
import SwiftUI
import Combine

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
        case carp, configHistory, certificates, packages, packageUpdates, tables
        case notices, filesystems, dyndns, hostOverrides, haproxy, acme, rrd

        var displayName: String {
            switch self {
            case .system: return "System status"
            case .version: return "Firmware version"
            case .interfaces: return "Interfaces"
            case .gateways: return "Gateways"
            case .services: return "Services"
            case .leases: return "DHCP leases"
            case .arp: return "ARP table"
            case .statics: return "Static mappings"
            case .firewallLog: return "Filter log"
            case .systemLog: return "System log"
            case .authLog: return "Authentication log"
            case .dhcpLog: return "DHCP log"
            case .openvpnLog: return "OpenVPN log"
            case .states: return "State table"
            case .openvpn: return "OpenVPN servers"
            case .openvpnClients: return "OpenVPN clients"
            case .ipsec: return "IPsec"
            case .wireguard: return "WireGuard"
            case .firewall: return "Firewall rules"
            case .aliases: return "Aliases"
            case .portForwards: return "Port forwards"
            case .carp: return "CARP"
            case .configHistory: return "Config history"
            case .certificates: return "Certificates"
            case .packages: return "Packages"
            case .packageUpdates: return "Package update check"
            case .tables: return "Blocked hosts"
            case .notices: return "System notices"
            case .filesystems: return "Filesystems"
            case .dyndns: return "Dynamic DNS"
            case .hostOverrides: return "DNS host overrides"
            case .haproxy: return "HAProxy"
            case .acme: return "ACME"
            case .rrd: return "Historical traffic"
            }
    }
    }

    /// The grouped calls a refresh makes.
    ///
    /// Grouped by screen rather than into one call: a PHP fatal cannot be
    /// caught, so a single combined snippet would mean one bad section
    /// blanking the whole dashboard.
    /// What to call a section on screen.
    ///
    /// The enum cases are wiring names; a person reading a diagnostics list
    /// needs the name of the thing that is broken, not the identifier the code
    /// happens to use for it.

    enum BatchGroup {
        case core, clients, vpn, system
    }

    // MARK: Dependencies

    let registry: ServerRegistry
    private let defaults: UserDefaults
    private let generation = BindingGeneration()
    var bindingID: UUID { generation.id }

    private func isCurrent(_ binding: UUID) -> Bool {
        generation.id == binding && !Task.isCancelled
    }

    /// Success dates belong to individual sections, including on-demand loads.
    @Published private(set) var freshness: [Section: SectionFreshness] = [:]

    @discardableResult
    private func beginFetch(_ sections: [Section]) -> UUID {
        let id = UUID()
        for section in sections { freshness[section, default: SectionFreshness()].begin(id, at: Date()) }
        return id
    }

    /// Reject obsolete bindings and record each attempted section independently.
    func checked<Value>(_ binding: UUID, sections: [Section] = [],
                        _ operation: () async throws -> Value) async throws -> Value {
        guard isCurrent(binding) else { throw RPCError.cancelled }
        let request = beginFetch(sections)
        defer {
            if bindingID == binding {
                for section in sections { freshness[section]?.fail(request, message: nil) }
            }
        }
        do {
            let value = try await operation()
            guard isCurrent(binding) else { throw RPCError.cancelled }
            for section in sections { freshness[section]?.succeed(request, at: Date()) }
            return value
        } catch {
            guard isCurrent(binding) else { throw RPCError.cancelled }
            let cancelled = error is CancellationError || (error as? RPCError) == .cancelled
            for section in sections {
                freshness[section]?.fail(request, message: cancelled ? nil : error.localizedDescription)
            }
            throw error
        }
    }

    private static func makeClient(profile: ServerProfile, registry: ServerRegistry,
                                   generation: BindingGeneration) -> FirewallClient {
        let binding = generation.id
        return FirewallClient(profile: profile) { [weak registry] expected, fingerprint in
            guard generation.id == binding else { return false }
            return registry?.pinCertificate(fingerprint, for: expected) ?? false
        }
    }

    /// Four hours at the default refresh, rather than half an hour.
    ///
    /// pfSense keeps months in RRD and this app cannot read it, so the history
    /// it keeps itself is all there is — and 60 samples was chosen when the
    /// chart was a sparkline. A pinned interface is pinned to be looked at, so
    /// the series should be long enough to show a shape. 480 points of three
    /// doubles is trivial memory.
    let throughput = ThroughputTracker(capacity: 480)

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

    /// Whether the firewall is not answering.
    ///
    /// `connectionError` is already the careful signal: it is set only when
    /// *every* section failed and the failure was fatal — a rejected password,
    /// a refused certificate, an unreachable host. A single unlucky request
    /// does not set it.
    ///
    /// It once also required `system == nil`, which never happened: the store
    /// keeps the last good data, so an app that had connected once never
    /// showed the disconnected state again. It sat behind a banner showing
    /// numbers from an hour ago, which is worse than saying nothing — a
    /// monitor that quietly shows stale readings is the failure this whole app
    /// exists to avoid.
    var isUnreachable: Bool { connectionError != nil }

    /// The theme the person chose, kept so a relaunch restores it.
    var themeName: String = "auto"

    @Published var isOverviewEditing = false

    func toggleOverviewEditing() {
        isOverviewEditing.toggle()
    }

    private var timer: Task<Void, Never>?
    /// Endpoints backed by optional packages are retried rarely once they 404,
    /// so a firewall without WireGuard doesn't pay for four dead calls a minute.
    /// Sections that have stopped being retried, for the diagnostics screen.
    ///
    /// Exposed read-only rather than made public: the screen needs to say
    /// which sections gave up and why, and that information was previously
    /// only inferable from an error string sitting on whichever card happened
    /// to show it.
    var abandonedSections: [Section] { missingEndpoints.sorted { $0.displayName < $1.displayName } }

    func faultCount(for section: Section) -> Int { faultCounts[section] ?? 0 }

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

    init(registry: ServerRegistry, defaults: UserDefaults = .standard) {
        self.defaults = defaults
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
        self.client = Self.makeClient(profile: profile, registry: registry, generation: generation)
        historyObservation = rrdLoader.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
    }

    var isConfigured: Bool { activeProfile?.isUsable ?? false }
    var profile: ServerProfile { registry.active ?? activeProfile ?? ServerProfile() }

    func logout() async {
        if let current = registry.active { registry.remove(current) }
        await rebind()
    }

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
        generation.advance()
        let binding = bindingID
        let previousClient = client
        activeProfile = registry.active
        client = Self.makeClient(profile: registry.active ?? ServerProfile(),
                                 registry: registry, generation: generation)
        clearData()
        throughput.reset()
        liveThroughput.reset()
        stateHistory.reset()
        lastCPUTicks = nil
        vpnThroughput.reset()
        systemMetrics.reset()
        gatewayMetrics.reset()
        resetRRD()
        missingEndpoints.removeAll()
        faultCounts.removeAll()
        refreshCount = 0
        await previousClient.invalidate()
        guard isCurrent(binding), isConfigured else { return }
        await refresh()
        guard isCurrent(binding) else { return }
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
        freshness.removeAll()
        firewallLogIndex.removeAll()
        blockedHosts = []
        haproxyStatsAccessors = []
        haproxyInstalled = false
        acmeInstalled = false
        isRefreshing = false
        isCheckingPackages = false
        packageCheckResult = nil
        lastPackageCheck = nil
        isCheckingFirmware = false
        firmwareCheckResult = nil
        liveInterfaceKey = nil
        liveError = nil
        prevFirewallCounts = FirewallCounts()
        wantsSecondaryLogs = false
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
        let binding = bindingID
        let client = client
        guard isConfigured, !isRefreshing else { return }
        isRefreshing = true
        defer { if bindingID == binding { isRefreshing = false } }
        refreshCount += 1

        var freshErrors: [Section: String] = [:]
        var fatal: String?

        /// Set the moment a request fails at the transport level.
        ///
        /// Each request waits 30 seconds and retries once, and a refresh makes
        /// five of them in sequence — so with the network gone, the app sat on
        /// stale data for minutes before it concluded anything. There is
        /// nothing to learn from the other four: if the firewall cannot be
        /// reached, it cannot be reached.
        ///
        /// So the first transport failure ends the cycle and says so straight
        /// away, rather than at the end of a queue of timeouts.
        var networkDown = false
        var succeeded = 0
        var succeededSections: Set<Section> = []

        /// Runs one section and records whether it worked.
        @discardableResult
        func run(_ section: Section, optional: Bool = false) async -> Bool {
            guard isCurrent(binding), !networkDown else { return false }
            // Retry a known-missing optional endpoint every 20th cycle only.
            guard !optional || !missingEndpoints.contains(section) || refreshCount % 20 == 0 else { return false }
            do {
                try await fetchOne(section)
                guard isCurrent(binding) else { return false }
                missingEndpoints.remove(section)
                succeeded += 1
                succeededSections.insert(section)
                return true
            } catch let err as RPCError {
                guard isCurrent(binding) else { return false }
                switch err {
                case .cancelled:
                    break
                case .transport, .offline:
                    // Straight to the screen. Waiting for four more timeouts
                    // to agree would take minutes.
                    fatal = err.localizedDescription
                    networkDown = true
                    connectionError = fatal
                case .unauthorized, .noCredentials, .tls, .notConfigured, .badURL,
                     .forbidden:
                    // `.transport` belongs here.
                    //
                    // It was in the default branch, recorded against the
                    // section and nothing else — so a phone with no network at
                    // all produced thirty section errors and no connection
                    // error, and the app stayed on its tabs showing whatever it
                    // had fetched last time. That is the one case the
                    // disconnected screen exists for.
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
                guard isCurrent(binding) else { return false }
                freshErrors[section] = error.localizedDescription
            }
            return false
        }
        guard isCurrent(binding) else { return }

        /// Runs one grouped call and hands the sections to a decoder.
        ///
        /// Errors are recorded against every section in the group rather than
        /// against the group. Somebody looking at an empty Gateways card wants
        /// to know why that card is empty; "batch_core failed" is an
        /// implementation detail leaking onto a screen, and would leave four
        /// other cards blank with no explanation.
        ///
        /// The fault counting that stops retrying a section works unchanged,
        /// because it keys on those same sections — and it matters more here,
        /// since a fault in a grouped call writes one notice to the firewall
        /// on behalf of five sections rather than one.
        @discardableResult
        func runBatch(
            _ group: BatchGroup,
            sections: [Section],
            decode: (FirewallClient.Batch) -> Bool
        ) async -> Bool {
            // Skipped only when every section in it has been abandoned. One
            // bad section should not stop the other four from loading.
            guard isCurrent(binding), !networkDown else { return false }
            let live = sections.filter { !missingEndpoints.contains($0) }
            guard !live.isEmpty || refreshCount % 20 == 0 else { return false }

            do {
                let batch: FirewallClient.Batch
                switch group {
                case .core: batch = try await checked(binding, sections: sections) { try await client.batchCore() }
                case .clients: batch = try await checked(binding, sections: sections) { try await client.batchClients() }
                case .vpn: batch = try await checked(binding, sections: sections) { try await client.batchVPN() }
                case .system: batch = try await checked(binding, sections: sections) { try await client.batchSystem() }
                }
                guard isCurrent(binding) else { return false }
                let result = decode(batch)
                for section in sections {
                    missingEndpoints.remove(section)
                    succeededSections.insert(section)
                }
                succeeded += 1
                return result
            } catch let err as RPCError {
                guard isCurrent(binding) else { return false }
                switch err {
                case .cancelled:
                    break
                case .transport, .offline:
                    // Straight to the screen. Waiting for four more timeouts
                    // to agree would take minutes.
                    fatal = err.localizedDescription
                    networkDown = true
                    connectionError = fatal
                case .unauthorized, .noCredentials, .tls, .notConfigured, .badURL,
                     .forbidden:
                    // `.transport` belongs here.
                    //
                    // It was in the default branch, recorded against the
                    // section and nothing else — so a phone with no network at
                    // all produced thirty section errors and no connection
                    // error, and the app stayed on its tabs showing whatever it
                    // had fetched last time. That is the one case the
                    // disconnected screen exists for.
                    fatal = err.localizedDescription
                case .fault:
                    for section in sections {
                        let count = (faultCounts[section] ?? 0) + 1
                        faultCounts[section] = count
                        missingEndpoints.insert(section)
                        freshErrors[section] = count >= Self.faultLimit
                            ? "\(err.localizedDescription) — stopped retrying, since each attempt writes a notice to the firewall. Pull to refresh to try again."
                            : err.localizedDescription
                    }
                default:
                    for section in sections { freshErrors[section] = err.localizedDescription }
                }
            } catch {
                guard isCurrent(binding) else { return false }
                for section in sections { freshErrors[section] = error.localizedDescription }
            }
            return false
        }
        guard isCurrent(binding) else { return }

        // Core status, in one call.
        //
        // These five sections used seven round trips, three of them running
        // the same telemetry snippet for system, states and filesystems. Every
        // one of them queued behind the last, and behind whatever the
        // webConfigurator was doing.
        let interfacesLoaded = await runBatch(
            .core,
            sections: [.system, .version, .states, .interfaces, .gateways, .services,
                       .filesystems]
        ) { batch in
            let telemetry = batch.object("telemetry")
            self.system = SystemStatus(telemetry)
            self.states = StateTableSize(telemetry)
            // Same derivation the individual fetch used: filesystems ride
            // inside telemetry rather than having a section of their own.
            self.filesystems = telemetry.list("filesystems")
                .compactMap { JSONDict($0) }.map(Filesystem.init)
            self.version = SystemVersion(batch.object("firmware"))
            self.interfaces = batch.rows("interfaces").map(InterfaceStat.init)
            self.gateways = batch.rows("gateways").map(GatewayStatus.init)
            self.services = batch.rows("services").map(ServiceStatus.init)
            return !self.interfaces.isEmpty
        }
        guard isCurrent(binding) else { return }

        if succeededSections.contains(.system) { deriveCPUUsage() }
        seedFavouritesIfNeeded()
        if succeededSections.contains(.states), let current = states?.current {
            stateHistory.ingest(current: current)
        }
        for gw in gateways where succeededSections.contains(.gateways) {
            gatewayMetrics.ingest(
                key: gw.name,
                delayMS: gw.delayMS,
                lossPercent: gw.lossPercent
            )
        }
        // Only sample when this cycle actually fetched counters.
        if interfacesLoaded { throughput.ingest(interfaces) }
        if succeededSections.contains(.system), let sys = system {
            if let cpu = sys.cpuUsage { systemMetrics.ingest(key: "cpu", value: cpu) }
            if let mem = sys.memUsage { systemMetrics.ingest(key: "mem", value: mem) }
            if let disk = sys.diskUsage { systemMetrics.ingest(key: "disk", value: disk) }
            if let swap = sys.swapUsage { systemMetrics.ingest(key: "swap", value: swap) }
        }
        guard isCurrent(binding) else { return }

        // Clients, in one call.
        //
        // Aliases are in here because they name clients, so they are needed on
        // every refresh — not only when somebody opens the Firewall tab. Rules
        // and port forwards stay on demand: 98 rules is a large payload for a
        // screen most people never look at.
        _ = await runBatch(
            .clients,
            sections: [.leases, .arp, .statics, .hostOverrides, .aliases]
        ) { batch in
            self.leases = batch.rows("dhcp_leases").map(DHCPLease.init)
            self.arp = batch.rows("arp_table").map(ARPEntry.init)
            self.staticMappings = batch.rows("static_mappings").map(StaticMapping.init)
            self.hostOverrides = batch.rows("host_overrides").map(HostOverride.init)
            self.aliases = batch.rows("firewall_aliases").map(FirewallAliasEntry.init)
            return true
        }
        guard isCurrent(binding) else { return }

        // Logs — save previous counts before refreshing.
        let savedCounts = FirewallCounts(
            blocked: self.blockedRecently,
            rejected: self.rejectedRecently,
            passed: self.firewallLog.count - self.blockedRecently - self.rejectedRecently
        )
        await run(.firewallLog)
        guard isCurrent(binding) else { return }
        prevFirewallCounts = savedCounts
        // Only the filter log is fetched on the timer, because the Overview
        // shows its counts. The other four are loaded when the Logs tab is
        // opened.
        //
        // Each is a quarter-megabyte read and a separate exec_php, and pfSense
        // serialises XML-RPC — so four of them added seconds to every refresh
        // for a screen that is usually not on the display.
        await loadSecondaryLogsIfNeeded()
        guard isCurrent(binding) else { return }

        buildFirewallLogIndex()

        // VPN — all optional; a firewall may have none of these configured.
        _ = await runBatch(
            .vpn,
            sections: [.openvpn, .openvpnClients, .ipsec, .wireguard]
        ) { batch in
            self.openvpnServers = batch.rows("openvpn_servers").map(OpenVPNServerStatus.init)
            self.openvpnClients = batch.rows("openvpn_clients").map(OpenVPNServerStatus.init)
            self.ipsecSAs = batch.rows("ipsec_sas").map(IPsecSA.init)
            let wg = batch.object("wireguard")
            self.wireguardTunnels = wg.list("tunnels").compactMap { JSONDict($0) }
                .map(WireGuardTunnel.init)
            self.wireguardPeers = wg.list("peers").compactMap { JSONDict($0) }
                .map(WireGuardPeer.init)
            return true
        }
        guard isCurrent(binding) else { return }

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
        guard isCurrent(binding) else { return }

        // System detail
        _ = await runBatch(
            .system,
            sections: [.carp, .certificates, .packages, .notices, .dyndns]
        ) { batch in
            self.carp = CARPStatus(batch.object("carp"))
            self.certificates = batch.rows("certificates").map { dict in
                CertificateInfo(dict, isCA: dict.bool("is_ca") ?? false)
            }
            self.packages = batch.rows("packages").map(PackageInfo.init)
            self.notices = batch.rows("notices").map(SystemNotice.init)
            self.dyndns = batch.rows("dyndns").map(DyndnsEntry.init)
            return true
        }
        guard isCurrent(binding) else { return }

        // Ask the repository at most every six hours, in the background.
        //
        // Not awaited: it takes seconds and the rest of the dashboard should
        // not wait behind it. Without this there would be no package alert
        // unless somebody remembered to press a button, which is not an alert.
        if shouldCheckPackages {
            Task {
                guard self.isCurrent(binding) else { return }
                await self.checkPackageUpdates()
            }
        }
        guard isCurrent(binding) else { return }

        for section in succeededSections { errors[section] = nil }
        for (section, message) in freshErrors { errors[section] = message }

        // A fatal error only counts when nothing at all got through.
        //
        // One unlucky request should not put "Cannot reach firewall" above a
        // screen full of data fetched seconds ago. A real problem — a rejected
        // key, a failed pin, an unreachable host — fails every section, so this
        // still catches it while a transient blip stays invisible.
        // Already set for a transport failure, and set here for the rest.
        //
        // `succeeded == 0` still guards the others: one unlucky request among
        // twenty should not put "cannot reach firewall" over a screen of fresh
        // data. A transport failure is different — it means no request can
        // succeed — and it has already been reported above.
        if !networkDown {
            connectionError = succeeded == 0 ? fatal : nil
        }
        lastRefresh = Date()
        alerts = VaktpostAlert.build(from: self)
        pruneAcknowledgements()
    }

    /// Fetches the pf tables. Called when the System screen appears, not by
    /// the refresh timer: the payload is dominated by `bogons`, which is large,
    /// static, and of no interest to anybody looking at this app.
    func loadTables() async {
        let binding = bindingID
        let client = client
        guard isConfigured, !isLoadingTables else { return }
        isLoadingTables = true
        defer { if bindingID == binding { isLoadingTables = false } }
        do {
            let fetched = try await checked(binding, sections: [.tables], { try await client.pfTables() })
            guard isCurrent(binding) else { throw RPCError.cancelled }
            if let fetched {
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
            guard isCurrent(binding) else { return }
            errors[.tables] = error.localizedDescription
        }
    }

    /// Retries a single failed section. Used by the per-section retry button.
    func retrySection(_ section: Section) async {
        let binding = bindingID
        guard isConfigured else { return }
        await fetch(section)
        guard isCurrent(binding) else { return }
        alerts = VaktpostAlert.build(from: self)
        pruneAcknowledgements()
    }

    /// Fetches a single section from the API and updates the store.
    /// Called by `retrySection` and can be called directly for on-demand refresh.
    func fetch(_ section: Section) async {
        let binding = bindingID
        errors[section] = nil
        do {
            try await fetchOne(section)
            guard isCurrent(binding) else { return }
        } catch {
            guard isCurrent(binding) else { return }
            errors[section] = error.localizedDescription
        }
    }

    /// Core fetch logic for one section. Called by both `refresh()` and `fetch(section:)`.
    /// Throws the underlying API error so refresh() can classify it properly.
    private func fetchOne(_ section: Section) async throws {
        let binding = bindingID
        let client = client
        switch section {
        case .system:
            let value = try await checked(binding, sections: [section]) { try await client.systemStatus() }
            guard isCurrent(binding) else { throw RPCError.cancelled }
            system = value
        case .version:
            let value = try await checked(binding, sections: [section]) { try await client.systemVersion() }
            guard isCurrent(binding) else { throw RPCError.cancelled }
            version = value
        case .states:
            let value = try await checked(binding, sections: [section]) { try await client.stateTableSize() }
            guard isCurrent(binding) else { throw RPCError.cancelled }
            states = value
        case .interfaces:
            let value = try await checked(binding, sections: [section]) { try await client.interfaces() }
            guard isCurrent(binding) else { throw RPCError.cancelled }
            interfaces = value
        case .gateways:
            let value = try await checked(binding, sections: [section]) { try await client.gateways() }
            guard isCurrent(binding) else { throw RPCError.cancelled }
            gateways = value
        case .services:
            let value = try await checked(binding, sections: [section]) { try await client.services() }
            guard isCurrent(binding) else { throw RPCError.cancelled }
            services = value
        case .leases:
            let value = try await checked(binding, sections: [section]) { try await client.leases() }
            guard isCurrent(binding) else { throw RPCError.cancelled }
            leases = value
        case .arp:
            let value = try await checked(binding, sections: [section]) { try await client.arpTable() }
            guard isCurrent(binding) else { throw RPCError.cancelled }
            arp = value
        case .statics:
            let value = try await checked(binding, sections: [section]) { try await client.staticMappings() }
            guard isCurrent(binding) else { throw RPCError.cancelled }
            staticMappings = value
        case .hostOverrides:
            let value = try await checked(binding, sections: [section]) { try await client.hostOverrides() }
            guard isCurrent(binding) else { throw RPCError.cancelled }
            hostOverrides = value
        case .firewallLog:
            let value = try await checked(binding, sections: [section]) { try await client.firewallLog(limit: profile.logLimit) }
            guard isCurrent(binding) else { throw RPCError.cancelled }
            firewallLog = value
        case .systemLog:
            let value = try await checked(binding, sections: [section]) { try await client.systemLog(limit: profile.logLimit) }
            guard isCurrent(binding) else { throw RPCError.cancelled }
            systemLog = value
        case .authLog:
            let value = try await checked(binding, sections: [section]) { try await client.authLog(limit: profile.logLimit) }
            guard isCurrent(binding) else { throw RPCError.cancelled }
            authLog = value
        case .dhcpLog:
            let value = try await checked(binding, sections: [section]) { try await client.dhcpLog(limit: profile.logLimit) }
            guard isCurrent(binding) else { throw RPCError.cancelled }
            dhcpLog = value
        case .openvpnLog:
            let value = try await checked(binding, sections: [section]) { try await client.openvpnLog(limit: profile.logLimit) }
            guard isCurrent(binding) else { throw RPCError.cancelled }
            openvpnLog = value
        case .openvpn:
            let value = try await checked(binding, sections: [section]) { try await client.openvpnServers() }
            guard isCurrent(binding) else { throw RPCError.cancelled }
            openvpnServers = value
        case .openvpnClients:
            let value = try await checked(binding, sections: [section]) { try await client.openvpnClients() }
            guard isCurrent(binding) else { throw RPCError.cancelled }
            openvpnClients = value
        case .ipsec:
            let value = try await checked(binding, sections: [section]) { try await client.ipsecSAs() }
            guard isCurrent(binding) else { throw RPCError.cancelled }
            ipsecSAs = value
        case .wireguard:
            let wg = try await checked(binding, sections: [section]) { try await client.wireguard() }
            guard isCurrent(binding) else { throw RPCError.cancelled }
            wireguardTunnels = wg.tunnels
            wireguardPeers = wg.peers
        case .firewall:
            await loadFirewallObjects()
            guard isCurrent(binding) else { throw RPCError.cancelled }
        case .aliases:
            let value = try await checked(binding, sections: [section]) { try await client.firewallAliases() }
            guard isCurrent(binding) else { throw RPCError.cancelled }
            aliases = value
        case .portForwards:
            await loadFirewallObjects()
            guard isCurrent(binding) else { throw RPCError.cancelled }
        case .carp:
            let value = try await checked(binding, sections: [section]) { try await client.carp() }
            guard isCurrent(binding) else { throw RPCError.cancelled }
            carp = value
        case .certificates:
            let value = try await checked(binding, sections: [section]) { try await client.certificates() }
            guard isCurrent(binding) else { throw RPCError.cancelled }
            certificates = value
        case .packages:
            let value = try await checked(binding, sections: [section]) { try await client.packages() }
            guard isCurrent(binding) else { throw RPCError.cancelled }
            packages = value
        case .filesystems:
            let value = try await checked(binding, sections: [section]) { try await client.filesystems() }
            guard isCurrent(binding) else { throw RPCError.cancelled }
            filesystems = value
        case .notices:
            let value = try await checked(binding, sections: [section]) { try await client.notices() }
            guard isCurrent(binding) else { throw RPCError.cancelled }
            notices = value
        case .dyndns:
            let value = try await checked(binding, sections: [section]) { try await client.dyndns() }
            guard isCurrent(binding) else { throw RPCError.cancelled }
            dyndns = value

        // Sections the refresh timer does not drive.
        //
        // `haproxy` is loaded by its own screen — a firewall running it has
        // dozens of backends and none of it changes minute to minute.
        // The other three are not reachable over XML-RPC without shelling out,
        // which the snippet rules forbid; they stay as cases so the enum is
        // exhaustive and the views referencing them compile with empty data.
        case .haproxy, .acme, .rrd, .configHistory, .tables, .packageUpdates:
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
        let binding = bindingID
        guard wantsSecondaryLogs else { return }
        await runSection(.systemLog)
        guard isCurrent(binding) else { return }
        await runSection(.authLog)
        guard isCurrent(binding) else { return }
        await runSection(.dhcpLog)
        guard isCurrent(binding) else { return }
        await runSection(.openvpnLog)
        guard isCurrent(binding) else { return }
    }

    /// Runs one section outside the main refresh's bookkeeping.
    private func runSection(_ section: Section) async {
        let binding = bindingID
        guard isConfigured else { return }
        do {
            try await fetchOne(section)
            guard isCurrent(binding) else { return }
            errors[section] = nil
        } catch {
            guard isCurrent(binding) else { return }
            errors[section] = error.localizedDescription
        }
    }

    func loadHAProxy() async {
        let binding = bindingID
        let client = client
        guard isConfigured, !hasLoadedHAProxy else { return }
        hasLoadedHAProxy = true
        do {
            let result = try await checked(binding, sections: [.haproxy], { try await client.haproxy() })
            guard isCurrent(binding) else { throw RPCError.cancelled }
            if let result {
                haproxyInstalled = true
                haproxyFrontends = result.frontends
                haproxyBackends = result.backends
                haproxyStatsAccessors = result.statsAccessors
            } else {
                haproxyInstalled = false
            }
            errors[.haproxy] = nil
        } catch {
            guard isCurrent(binding) else { return }
            hasLoadedHAProxy = false   // let a pull-to-refresh try again
            errors[.haproxy] = error.localizedDescription
        }
    }

    func loadACME() async {
        let binding = bindingID
        let client = client
        guard isConfigured, !hasLoadedACME else { return }
        hasLoadedACME = true
        do {
            let result = try await checked(binding, sections: [.acme], { try await client.acme() })
            guard isCurrent(binding) else { throw RPCError.cancelled }
            if let result {
                acmeInstalled = true
                acmeCertificates = result.certificates
                acmeAccounts = result.accounts
            } else {
                acmeInstalled = false
            }
            errors[.acme] = nil
        } catch {
            guard isCurrent(binding) else { return }
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
        let binding = bindingID
        let client = client
        liveInterfaceKey = key
        liveThroughput.reset()
        liveError = nil
        defer {
            if bindingID == binding {
                liveInterfaceKey = nil
                liveError = nil
            }
        }

        while isCurrent(binding) {
            do {
                let counters = try await checked(binding) { try await client.interfaceCounters() }
                guard isCurrent(binding) else { return }
                liveThroughput.ingest(counters)
                liveError = nil
            } catch let error as RPCError {
                guard isCurrent(binding) else { return }
                if case .cancelled = error { return }
                liveError = error.localizedDescription
            } catch {
                guard isCurrent(binding) else { return }
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
        let binding = bindingID
        let client = client
        guard isConfigured, !isLoadingFirewallObjects, !hasLoadedFirewallObjects else { return }
        isLoadingFirewallObjects = true
        hasLoadedFirewallObjects = true
        defer { if bindingID == binding { isLoadingFirewallObjects = false } }
        do {
            let value = try await checked(binding, sections: [.firewall]) { try await client.firewallRules() }
            guard isCurrent(binding) else { throw RPCError.cancelled }
            rules = value
            errors[.firewall] = nil
        } catch {
            guard isCurrent(binding) else { return }
            errors[.firewall] = error.localizedDescription
        }
        // Aliases are not fetched here: the standard refresh already has them,
        // because they name clients.
        do {
            let value = try await checked(binding, sections: [.portForwards]) { try await client.portForwards() }
            guard isCurrent(binding) else { throw RPCError.cancelled }
            portForwards = value
            errors[.portForwards] = nil
        } catch {
            guard isCurrent(binding) else { return }
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
            defaults.set(lastPackageCheck?.timeIntervalSince1970 ?? 0,
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
        let binding = bindingID
        let client = client
        guard isConfigured, !isCheckingPackages else { return }
        isCheckingPackages = true
        packageCheckResult = nil
        defer { if bindingID == binding { isCheckingPackages = false } }

        do {
            let checked = try await checked(binding, sections: [.packageUpdates], { try await client.packageUpdates() })
            guard isCurrent(binding) else { throw RPCError.cancelled }
            if let checked {
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
            guard isCurrent(binding) else { return }
            packageCheckResult = nil
            errors[.packages] = error.localizedDescription
        }
    }

    // MARK: RRD history

    let rrdLoader = HistoryLoader<PHPSnippet.RRDWindow, RRDHistory>(lifetime: 300)
    private var historyObservation: AnyCancellable?
    var rrdHistory: RRDHistory? { rrdLoader.value }
    var isLoadingRRD: Bool { rrdLoader.isLoading }
    var rrdWindow: PHPSnippet.RRDWindow { rrdLoader.key ?? .week }
    @Published var widenedFromEmpty = false

    /// Cache entries expire after five minutes. Changing range cancels the
    /// old request and clears its chart before the new range is displayed.
    func loadRRD(_ window: PHPSnippet.RRDWindow? = nil, widenIfEmpty: Bool = false,
                 force: Bool = false) async {
        let binding = bindingID
        let client = client
        let wanted = window ?? rrdWindow
        guard isConfigured else { return }
        if window != nil && !widenIfEmpty { widenedFromEmpty = false }
        if rrdLoader.key != wanted {
            freshness[.rrd] = SectionFreshness(lastSuccess: rrdLoader.cache[wanted]?.fetchedAt)
        }
        let request = beginFetch([.rrd])
        let accepted = await rrdLoader.load(wanted, force: force) {
            try await client.rrdTraffic(wanted)
        }
        guard isCurrent(binding) else { return }
        guard rrdLoader.key == wanted, freshness[.rrd]?.requestID == request else { return }
        guard accepted else {
            freshness[.rrd]?.fail(request, message: nil)
            return
        }
        errors[.rrd] = rrdLoader.error
        if let error = rrdLoader.error {
            freshness[.rrd]?.fail(request, message: error)
            return
        }
        if let date = rrdLoader.fetchedAt { freshness[.rrd]?.succeed(request, at: date) }
        let hasData = rrdHistory?.series.contains { !$0.points.isEmpty } ?? false
        if rrdHistory?.available == true, !hasData, widenIfEmpty, let next = wanted.next {
            widenedFromEmpty = true
            await loadRRD(next, widenIfEmpty: true, force: force)
        }
    }

    var newestRRDSample: Date? {
        rrdLoader.cache.values.flatMap { $0.value.series }.compactMap(\.newestSample).max()
    }

    func resetRRD() {
        rrdLoader.reset()
        widenedFromEmpty = false
        freshness[.rrd] = nil
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
        let binding = bindingID
        let client = client
        guard isConfigured, !isCheckingFirmware else { return }
        isCheckingFirmware = true
        defer { if bindingID == binding { isCheckingFirmware = false } }
        do {
            let value = try await checked(binding, sections: [.version]) { try await client.systemVersion() }
            guard isCurrent(binding) else { throw RPCError.cancelled }
            version = value
            errors[.version] = nil
            firmwareCheckResult = version?.updateAvailable == true
                ? "An update is available."
                : "Checked just now — up to date."
        } catch {
            guard isCurrent(binding) else { return }
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
