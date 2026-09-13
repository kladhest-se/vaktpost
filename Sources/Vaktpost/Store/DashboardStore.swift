import Foundation
import SwiftUI
import Observation

/// Holds every dashboard section independently so one failing endpoint (an
/// uninstalled package, a privilege the key lacks) degrades that card rather
/// than the whole screen.
@MainActor
@Observable
final class DashboardStore: Observable {

    enum Section: String, CaseIterable {
        case system, version, interfaces, gateways, services, leases, arp, statics
        case firewallLog, systemLog, authLog, dhcpLog, openvpnLog, states
        case openvpn, openvpnClients, ipsec, wireguard
        case firewall, aliases, portForwards
        case carp, configHistory, certificates, packages, packageUpdates, tables
        case notices, filesystems, dyndns, hostOverrides, haproxy, acme, rrd, pfblocker, dnsbl

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
            case .pfblocker: return "pfBlockerNG"
            case .dnsbl: return "DNSBL statistics"
            }
    }
    }

    enum TableReadState: Equatable {
        case notLoaded
        case live
        case unavailable
    }

    // MARK: UserDefaults keys

    private enum UDKey: String {
        case temperatureWarn = "alerts.tempWarn"
        case hostTrafficInterval = "traffic.interval"
        case favouriteInterfaces = "interfaces.favourites"
        case favouritesSeeded = "interfaces.favouritesSeeded"
        case mutedAlerts = "alerts.hidden.v2"
        case alertsSilenced = "alerts.silenced"
        case acknowledgedAlerts = "alerts.acknowledged"
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

    /// Mutable bookkeeping shared by the concurrently-started refresh jobs.
    /// Every access remains on the main actor while network awaits can still
    /// overlap, so Swift 6 can prove there is no unsynchronised shared state.
    @MainActor
    private final class RefreshCycle {
        var freshErrors: [Section: String] = [:]
        var fatal: String?
        var networkDown = false
        var succeeded = 0
        var succeededSections: Set<Section> = []
        var failedSections: Set<Section> = []
    }

    // MARK: Managers

    let alertManager = AlertManager()

    /// Both take the store's `defaults` rather than reaching for `.standard`.
    ///
    /// The store is careful to accept an injected `UserDefaults` so a test can
    /// have its own; these two ignored it and wrote to the real one, so a test
    /// touching the notification setting changed it for the person running the
    /// tests. Declared `let` and assigned in `init` for that reason.
    let expiryNotifier: ExpiryNotifier
    let topTalkers: TopTalkerRecorder

    /// Safety infrastructure for write operations.
    let auditTrail: AuditTrail
    let rateLimiter: WriteRateLimiter
    let analytics: WriteAnalytics

    /// Whether interface error counters are moving, refresh over refresh.
    ///
    /// The totals have always been on screen; what they could not say is
    /// whether anything is happening now. This is the difference between
    /// readings, which is the part worth looking at.
    var interfaceErrors = InterfaceErrorTracker()
    let gatewayManager = GatewayManager()
    let overviewLayout = OverviewLayout()
    let performanceMetrics = PerformanceMetricsStore()
    let anomalyDetector = TrafficAnomalyDetector()
    let clientHistory = ClientHistoryTracker()
    let diffViewer = FirewallDiffViewer()

    // MARK: Dependencies

    let registry: ServerRegistry
    private let defaults: UserDefaults
    private let generation: BindingGeneration
    var bindingID: UUID { generation.id }

    private func isCurrent(_ binding: UUID) -> Bool {
        generation.id == binding && !Task.isCancelled
    }

    /// Success dates belong to individual sections, including on-demand loads.
    private(set) var freshness: [Section: SectionFreshness] = [:]

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
    var liveInterfaceKey: String?
    var liveError: String?
    let vpnThroughput = ThroughputTracker(bitsMultiplier: 1)
    let systemMetrics = MetricTracker<String, Double>()
    let stateHistory = StateHistoryTracker()
    var prevFirewallCounts = FirewallCounts()

    struct FirewallCounts {
        var blocked: Int = 0
        var rejected: Int = 0
        var passed: Int = 0
    }

    private(set) var client: FirewallClient
    private(set) var writeCoordinator: WriteCoordinator
    private(set) var activeProfile: ServerProfile?

    // MARK: Data

    var system: SystemStatus?
    var version: SystemVersion?
    var states: StateTableSize?
    var interfaces: [InterfaceStat] = []
    var services: [ServiceStatus] = []
    var leases: [DHCPLease] = []
    var arp: [ARPEntry] = []
    var staticMappings: [StaticMapping] = []
    var hostOverrides: [HostOverride] = []
    var firewallLog: [LogLine] = []
    var systemLog: [LogLine] = []
    var authLog: [LogLine] = []
    var dhcpLog: [LogLine] = []
    var openvpnLog: [LogLine] = []


    var openvpnServers: [OpenVPNServerStatus] = []
    var openvpnClients: [OpenVPNServerStatus] = []
    var ipsecSAs: [IPsecSA] = []
    var wireguardTunnels: [WireGuardTunnel] = []
    var wireguardPeers: [WireGuardPeer] = []

    var rules: [FirewallRule] = []
    var aliases: [FirewallAliasEntry] = []
    var portForwards: [PortForward] = []
    /// Mirrors pfSense's filter/natconf dirty markers. Saved changes are
    /// visible in the editor immediately but do not affect traffic until the
    /// user explicitly applies them.
    var firewallChangesPending = false

    var carp: CARPStatus?
    var configHistory: [ConfigRevision] = []
    var certificates: [CertificateInfo] = []
    var packages: [PackageInfo] = []
    var notices: [SystemNotice] = []
    var filesystems: [Filesystem] = []
    var dyndns: [DyndnsEntry] = []

    // HAProxy, loaded when its screen opens rather than on the timer: a
    // firewall running it has many backends, and none of it changes minute to
    // minute.
    var haproxyFrontends: [HAProxyFrontend] = []
    var haproxyBackends: [HAProxyBackend] = []
    var haproxyStatsAccessors: [String] = []
    var haproxyInstalled = false
    private var hasLoadedHAProxy = false

    /// pfBlockerNG, loaded when its screen opens rather than on the timer. The
    /// feed counts come from pf tables, which is a handful of lookups, but most
    /// firewalls do not have the package and every one of them would pay for
    /// the question on every refresh.
    var pfBlocker: PFBlockerStatus?
    var pfBlockerInstalled = false
    private var hasLoadedPFBlocker = false

    /// DNSBL statistics, loaded alongside pfBlockerNG.
    ///
    /// Kept separate from `pfBlocker` because they answer different questions
    /// from different places — one is what pf has loaded, the other is what
    /// the resolver has been refusing — and because this one reads a megabyte
    /// of log and should not be paid for by a screen that only wants the feed
    /// counts.
    var dnsblStats: DNSBLStats?
    private var hasLoadedDNSBL = false

    /// Whether the DNSBL screen is worth offering at all.
    var dnsblAvailable: Bool {
        pfBlockerInstalled && (pfBlocker?.dnsblEnabled ?? false)
    }

    var acmeCertificates: [ACMECertificate] = []
    var acmeAccounts: [ACMEAccount] = []
    var acmeInstalled = false
    private var hasLoadedACME = false

    /// Loaded on demand rather than on the refresh timer — see `loadTables()`.
    var tables: [FirewallTable] = []
    var blockedHosts: [FirewallTable] = []
    var isLoadingTables = false
    var tableReadState: TableReadState = .notLoaded

    /// Enabled literal-source block rules, including rules created by Quick
    /// Block. Configuration remains readable even when this pfSense build has
    /// no safe PHP accessor for dynamic pf-table entries.
    var configuredHostBlocks: [FirewallRule] {
        rules.filter(\.isConfiguredHostBlock).sorted {
            if $0.interfaceName == $1.interfaceName {
                return $0.sourceSide.address < $1.sourceSide.address
            }
            return $0.interfaceName < $1.interfaceName
        }
    }

    /// Rules, aliases and port forwards are loaded lazily when the user
    /// first navigates to the Firewall screen, then refreshed on the timer.
    /// The payloads are large and most users never look, so pulling them
    /// every thirty seconds is wasted bandwidth.
    var isLoadingFirewallObjects = false
    private var hasLoadedFirewallObjects = false

    // MARK: Status

    var errors: [Section: String] = [:]
    var isRefreshing = false
    var lastRefresh: Date?
    /// Fatal connection error — shown full-screen rather than per card.
    var connectionError: String?

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

    var isOverviewEditing = false

    func toggleOverviewEditing() {
        isOverviewEditing.toggle()
    }

    private var refreshScheduler: RefreshScheduler?
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

    /// How often the host-traffic screens take a capture, in seconds.
    ///
    /// A stored preference rather than a constant, because the right number is
    /// not a property of the app. It depends on what the firewall is doing and
    /// on what the person is watching for: catching the moment a transfer
    /// starts wants a few seconds, leaving the screen open while something
    /// else is diagnosed wants half a minute or more, and the cost of being
    /// wrong lands on the webConfigurator rather than here.
    ///
    /// The floor is enforced where it is used, not here. Below roughly a
    /// second and a half the captures queue faster than they complete, and
    /// that is a fact about `rate` rather than a preference to be overridden.
    var hostTrafficInterval: TimeInterval = 15 {
        didSet { defaults.set(hostTrafficInterval, forKey: UDKey.hostTrafficInterval.rawValue) }
    }

    /// What the interval picker offers.
    ///
    /// Two seconds is the edge of what the measurement allows, not a
    /// comfortable setting: a capture is a second of wall clock and the round
    /// trip is on top of that, so on a busy firewall a two-second period is
    /// effectively continuous polling — the loop will find its time already
    /// spent and start the next capture immediately. It is offered because
    /// watching a transfer begin wants that, and the cost is visible while it
    /// is happening rather than later.
    static let hostTrafficIntervals: [TimeInterval] = [2, 5, 10, 15]

    init(registry: ServerRegistry, defaults: UserDefaults = .standard) {
        let generation = BindingGeneration()
        let auditTrail = AuditTrail(defaults: defaults)
        let rateLimiter = WriteRateLimiter()
        let analytics = WriteAnalytics()
        self.auditTrail = auditTrail
        self.rateLimiter = rateLimiter
        self.analytics = analytics
        self.generation = generation
        self.defaults = defaults
        self.expiryNotifier = ExpiryNotifier(defaults: defaults)
        self.topTalkers = TopTalkerRecorder()
        let storedInterval = defaults.double(forKey: UDKey.hostTrafficInterval.rawValue)
        // A zero means nothing was ever stored, which is different from
        // somebody choosing the fastest option.
        hostTrafficInterval = storedInterval > 0 ? storedInterval : 15
        let tempWarn = defaults.double(forKey: "alerts.tempWarn")
        alertManager.temperatureWarnOverride = tempWarn > 0 ? tempWarn : nil
        overviewLayout.alertManager = alertManager
        overviewLayout.gatewayManager = gatewayManager
        favouriteInterfaces = Set(defaults.stringArray(forKey: "interfaces.favourites") ?? [])
        let checkedAt = defaults.double(forKey: "packages.lastCheck")
        lastPackageCheck = checkedAt > 0 ? Date(timeIntervalSince1970: checkedAt) : nil
        self.registry = registry
        let profile = registry.active ?? ServerProfile()
        let binding = generation.id
        let client = Self.makeClient(profile: profile, registry: registry, generation: generation)
        self.activeProfile = registry.active
        self.client = client
        self.writeCoordinator = WriteCoordinator(
            profile: profile,
            client: client,
            auditTrail: auditTrail,
            rateLimiter: rateLimiter,
            analytics: analytics,
            isBindingCurrent: {
                generation.id == binding && registry.active?.id == profile.id
            }
        )
        auditTrail.bind(to: registry.active?.id)
    }

    var isConfigured: Bool { activeProfile?.isUsable ?? false }
    var profile: ServerProfile { registry.active ?? activeProfile ?? ServerProfile() }
    var canAdminister: Bool { profile.isAdministrationEnabled }

    func logout() async throws {
        if let current = registry.active {
            try auditTrail.delete(for: current.id)
            try registry.remove(current).get()
        }
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

    func removed(_ profile: ServerProfile) async throws {
        // Delete the protected records first. If that fails the credential and
        // profile remain intact. Registry removal similarly keeps metadata when
        // Keychain cleanup fails, making either failure visible and retryable.
        try auditTrail.delete(for: profile.id)
        try registry.remove(profile).get()
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
        let profile = registry.active ?? ServerProfile()
        let currentGeneration = generation
        let reboundClient = Self.makeClient(profile: profile,
                                            registry: registry, generation: generation)
        client = reboundClient
        writeCoordinator = WriteCoordinator(
            profile: profile,
            client: reboundClient,
            auditTrail: auditTrail,
            rateLimiter: rateLimiter,
            analytics: analytics,
            isBindingCurrent: { [weak registry] in
                currentGeneration.id == binding && registry?.active?.id == profile.id
            }
        )
        auditTrail.bind(to: registry.active?.id)
        clearData()
        throughput.reset()
        liveThroughput.reset()
        stateHistory.reset()
        lastCPUTicks = nil
        vpnThroughput.reset()
        systemMetrics.reset()
        gatewayManager.reset()
        resetRRD()
        missingEndpoints.removeAll()
        faultCounts.removeAll()
        refreshCount = 0
        await previousClient.invalidate()
        guard isCurrent(binding), isConfigured else { return }
        Task { await refresh() }
        startAutoRefresh()
    }

    /// Closure that resets all data properties to their initial (empty) state.
    /// Automatically stays in sync because new properties are added here.
    private static let resetData: (DashboardStore) -> Void = { store in
        store.system = nil; store.version = nil; store.states = nil; store.carp = nil
        store.interfaces = []; store.gatewayManager.gateways = []; store.services = []
        store.leases = []; store.arp = []; store.staticMappings = []
        store.hostOverrides = []
        store.firewallLog = []; store.systemLog = []; store.authLog = []; store.dhcpLog = []; store.openvpnLog = []
        store.openvpnServers = []; store.openvpnClients = []; store.ipsecSAs = []
        store.wireguardTunnels = []; store.wireguardPeers = []
        store.rules = []; store.aliases = []; store.portForwards = []
        store.firewallChangesPending = false
        store.filterSeparators = []; store.natSeparators = []
        store.configHistory = []; store.certificates = []; store.packages = []; store.tables = []
        store.pfBlocker = nil; store.pfBlockerInstalled = false
        store.dnsblStats = nil
        store.interfaceErrors.reset()
        store.notices = []; store.filesystems = []; store.dyndns = []
        store.isLoadingTables = false
        store.tableReadState = .notLoaded
        store.isLoadingFirewallObjects = false
        store.hasLoadedFirewallObjects = false
        store.hasLoadedHAProxy = false
        store.hasLoadedACME = false
        store.hasLoadedPFBlocker = false
        store.hasLoadedDNSBL = false
        store.acmeCertificates = []; store.acmeAccounts = []
        store.haproxyFrontends = []; store.haproxyBackends = []
        store.alertManager.alerts = []; store.errors = [:]; store.connectionError = nil; store.lastRefresh = nil
    }

    private func clearData() {
        Self.resetData(self)
        freshness.removeAll()
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
        overviewLayout.sync(from: self)
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
        let refreshStartTime = Date()

        let cycle = RefreshCycle()

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
        /// Runs one section and records whether it worked.
        @discardableResult
        @MainActor @Sendable
        func run(_ section: Section, optional: Bool = false) async -> Bool {
            guard isCurrent(binding), !cycle.networkDown else { return false }
            // Retry a known-missing optional endpoint every 20th cycle only.
            guard !optional || !missingEndpoints.contains(section) || refreshCount % 20 == 0 else { return false }
            do {
                try await fetchOne(section)
                guard isCurrent(binding) else { return false }
                missingEndpoints.remove(section)
                cycle.succeeded += 1
                cycle.succeededSections.insert(section)
                return true
            } catch let err as RPCError {
                guard isCurrent(binding) else { return false }
                recordError(err, for: section, optional: optional)
            } catch {
                guard isCurrent(binding) else { return false }
                cycle.failedSections.insert(section)
                cycle.freshErrors[section] = error.localizedDescription
            }
            return false
        }

        @MainActor
        func recordError(_ err: RPCError, for section: Section, optional: Bool) {
            if err != .cancelled { cycle.failedSections.insert(section) }
            switch err {
            case .cancelled:
                break
            case .transport, .offline:
                cycle.fatal = err.localizedDescription
                cycle.networkDown = true
                connectionError = cycle.fatal
            case .unauthorized, .noCredentials, .tls, .notConfigured, .badURL, .forbidden:
                cycle.fatal = err.localizedDescription
            case .fault:
                let count = (faultCounts[section] ?? 0) + 1
                faultCounts[section] = count
                if optional { missingEndpoints.insert(section) }
                cycle.freshErrors[section] = count >= Self.faultLimit
                    ? "\(err.localizedDescription) — stopped retrying, since each attempt writes a notice to the firewall. Pull to refresh to try again."
                    : err.localizedDescription
            default:
                cycle.freshErrors[section] = err.localizedDescription
            }
        }

        @MainActor
        func recordBatchError(_ err: RPCError, for sections: [Section]) {
            if err != .cancelled { cycle.failedSections.formUnion(sections) }
            switch err {
            case .cancelled:
                break
            case .transport, .offline:
                cycle.fatal = err.localizedDescription
                cycle.networkDown = true
                connectionError = cycle.fatal
            case .unauthorized, .noCredentials, .tls, .notConfigured, .badURL, .forbidden:
                cycle.fatal = err.localizedDescription
            case .fault:
                for section in sections {
                    let count = (faultCounts[section] ?? 0) + 1
                    faultCounts[section] = count
                    missingEndpoints.insert(section)
                    cycle.freshErrors[section] = count >= Self.faultLimit
                        ? "\(err.localizedDescription) — stopped retrying, since each attempt writes a notice to the firewall. Pull to refresh to try again."
                        : err.localizedDescription
                }
            default:
                for section in sections { cycle.freshErrors[section] = err.localizedDescription }
            }
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
        @MainActor @Sendable
        func runBatch(
            _ group: BatchGroup,
            sections: [Section],
            decode: @MainActor (FirewallClient.Batch) -> Bool
        ) async -> Bool {
            // Skipped only when every section in it has been abandoned. One
            // bad section should not stop the other four from loading.
            guard isCurrent(binding), !cycle.networkDown else { return false }
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
                    cycle.succeededSections.insert(section)
                }
                cycle.succeeded += 1
                return result
            } catch let err as RPCError {
                guard isCurrent(binding) else { return false }
                recordBatchError(err, for: sections)
            } catch {
                guard isCurrent(binding) else { return false }
                cycle.failedSections.formUnion(sections)
                for section in sections { cycle.freshErrors[section] = error.localizedDescription }
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
            self.gatewayManager.gateways = batch.rows("gateways").map(GatewayStatus.init)
            self.services = batch.rows("services").map(ServiceStatus.init)
            return !self.interfaces.isEmpty
        }
        guard isCurrent(binding) else { return }

        if cycle.succeededSections.contains(.system) { deriveCPUUsage() }
        seedFavouritesIfNeeded()
        if cycle.succeededSections.contains(.states), let current = states?.current {
            stateHistory.ingest(current: current)
        }
        for gw in gatewayManager.gateways where cycle.succeededSections.contains(.gateways) {
            gatewayManager.ingest(
                key: gw.name,
                delayMS: gw.delayMS,
                lossPercent: gw.lossPercent
            )
        }
        // Only sample when this cycle actually fetched counters.
        if interfacesLoaded { throughput.ingest(interfaces) }
        if cycle.succeededSections.contains(.system), let sys = system {
            if let cpu = sys.cpuUsage { systemMetrics.ingest(key: "cpu", value: cpu) }
            if let mem = sys.memUsage { systemMetrics.ingest(key: "mem", value: mem) }
            if let disk = sys.diskUsage { systemMetrics.ingest(key: "disk", value: disk) }
            if let swap = sys.swapUsage { systemMetrics.ingest(key: "swap", value: swap) }
        }
        guard isCurrent(binding) else { return }

        // Fetch clients, logs, VPN, and system batches in parallel.
        //
        // These four batches are independent of each other. Running them
        // concurrently cuts the round-trip latency from ~4× to ~1× (plus the
        // core batch time), since pfSense serialises XML-RPC calls.
        
        // Capture previous firewall counts on the main actor before the task group.
        let savedCounts = FirewallCounts(
            blocked: self.overviewLayout.blockedRecently,
            rejected: self.overviewLayout.rejectedRecently,
            passed: self.firewallLog.count - self.overviewLayout.blockedRecently - self.overviewLayout.rejectedRecently
        )

        async let clientsLoaded = runBatch(
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

        async let firewallLogLoaded = run(.firewallLog)

        // Filter rules and port forwards were entirely absent from this
        // cycle — no batch listed them, no individual `run()` call requested
        // them, only `.firewallLog` did. `store.refresh()` is what every
        // successful (and, since the reorder failure fix, unsuccessful) write
        // in the Firewall feature calls afterward, on the assumption that it
        // brings rules and forwards current. It never has: the only paths
        // that actually populated them were a screen's first appearance and
        // a handful of call sites passing `force: true` directly. A rule
        // deleted through the web GUI, or by anything else, could sit in
        // `store.rules` indefinitely — through any number of refreshes,
        // automatic or manual — until a write depending on it failed against
        // a rule that no longer existed and reported it as a mystery, which
        // is exactly what surfaced this.
        //
        // One call, not two. `.firewall` and `.portForwards` both resolve to
        // the identical `loadFirewallObjects(force: true)` — the same
        // function call, not merely the same effect — so running both as
        // separate concurrent tasks here would race that one call against
        // itself for no benefit. `.firewall` alone refreshes rules, port
        // forwards, and separators together, exactly as it does everywhere
        // else this function is called from.
        async let firewallObjectsLoaded = run(.firewall)

        async let vpnLoaded = runBatch(
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

        async let systemLoaded = runBatch(
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

        _ = await (clientsLoaded, firewallLogLoaded, vpnLoaded, systemLoaded, firewallObjectsLoaded)
        guard isCurrent(binding) else { return }
        
        // Restore previous firewall counts after the firewall log was fetched.
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

        for section in cycle.succeededSections { errors[section] = nil }
        for (section, message) in cycle.freshErrors { errors[section] = message }

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
        if !cycle.networkDown {
            connectionError = cycle.succeeded == 0 ? cycle.fatal : nil
        }
        lastRefresh = Date()
        alertManager.alerts = VaktpostAlert.build(from: self)
        alertManager.pruneAcknowledgements()
        overviewLayout.sync(from: self)
        interfaceErrors.record(interfaces)
        scheduleExpiryNotifications()
        
        // Detect traffic anomalies
        let currentCounts = TrafficAnomalyDetector.TrafficCounts(
            blocked: overviewLayout.blockedRecently,
            rejected: overviewLayout.rejectedRecently,
            passed: overviewLayout.passedRecently,
            timestamp: Date()
        )
        _ = anomalyDetector.analyze(currentCounts: currentCounts, previousCounts: TrafficAnomalyDetector.TrafficCounts(
            blocked: prevFirewallCounts.blocked,
            rejected: prevFirewallCounts.rejected,
            passed: prevFirewallCounts.passed,
            timestamp: Date()
        ))
        
        // Update client history
        clientHistory.update(
            leases: leases,
            arp: arp,
            statics: staticMappings,
            hostOverrides: hostOverrides
        )
        
        // Take config snapshot
        diffViewer.snapshot(
            rules: rules,
            aliases: aliases,
            portForwards: portForwards
        )
        
        performanceMetrics.recordRefresh(
            duration: Date().timeIntervalSince(refreshStartTime),
            sectionsCompleted: cycle.succeededSections.count,
            // Only attempted sections can fail. The old subtraction counted
            // every lazy screen that this refresh deliberately did not load.
            sectionsFailed: cycle.failedSections.count,
            success: cycle.failedSections.isEmpty
        )
    }

    /// Keep the pending expiry notifications in step with what was just read.
    ///
    /// On every refresh rather than only when the certificate list changes:
    /// comparing two lists of certificates to decide whether to reconcile is
    /// more code than reconciling, and the reconcile is a local operation with
    /// nothing on the wire.
    ///
    /// Skipped when the certificate section failed. An empty list from a
    /// failed fetch looks exactly like a firewall with no certificates, and
    /// acting on it would cancel every pending notification for this server
    /// because one request timed out.
    func scheduleExpiryNotifications() {
        guard errors[.certificates] == nil, !certificates.isEmpty else { return }
        let certificates = self.certificates
        let id = profile.id.uuidString
        let name = profile.displayName
        Task { await expiryNotifier.reconcile(certificates: certificates,
                                              serverID: id,
                                              serverName: name) }
    }

    /// Fetches the operational pf tables. Called when the System screen
    /// appears, not by the refresh timer: these dynamic entries are useful on
    /// demand and not worth another XML-RPC request every thirty seconds.
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
                tableReadState = .live
                errors[.tables] = nil
            } else {
                // Reachable only through pfctl, which is a shell, or a PHP
                // accessor this pfSense does not have. Said plainly rather
                // than shown as an empty list, which would read as "nothing
                // is blocked".
                tables = []
                blockedHosts = []
                tableReadState = .unavailable
                // This is a platform capability, not a failed request. Keep
                // the limitation visible beside the feature without making
                // Diagnostics report a permanent false failure.
                errors[.tables] = nil
            }
        } catch {
            guard isCurrent(binding) else { return }
            tableReadState = .notLoaded
            errors[.tables] = error.localizedDescription
        }
    }

    /// Retries a single failed section. Used by the per-section retry button.
    func retrySection(_ section: Section) async {
        let binding = bindingID
        guard isConfigured else { return }
        await fetch(section)
        guard isCurrent(binding) else { return }
        alertManager.alerts = VaktpostAlert.build(from: self)
        alertManager.pruneAcknowledgements()
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
        try await fetchSection(binding, section, client: client)
    }

    private func fetchSection(_ binding: UUID, _ section: Section, client: FirewallClient) async throws {
        switch section {
        case .system:
            try await assign(binding, [section], fetcher: { try await client.systemStatus() }) { self.system = $0 }
        case .version:
            try await assign(binding, [section], fetcher: { try await client.systemVersion() }) { self.version = $0 }
        case .states:
            try await assign(binding, [section], fetcher: { try await client.stateTableSize() }) { self.states = $0 }
        case .interfaces:
            try await assign(binding, [section], fetcher: { try await client.interfaces() }) { self.interfaces = $0 }
        case .gateways:
            try await assign(binding, [section], fetcher: { try await client.gateways() }) { self.gatewayManager.gateways = $0 }
        case .services:
            try await assign(binding, [section], fetcher: { try await client.services() }) { self.services = $0 }
        case .leases:
            try await assign(binding, [section], fetcher: { try await client.leases() }) { self.leases = $0 }
        case .arp:
            try await assign(binding, [section], fetcher: { try await client.arpTable() }) { self.arp = $0 }
        case .statics:
            try await assign(binding, [section], fetcher: { try await client.staticMappings() }) { self.staticMappings = $0 }
        case .hostOverrides:
            try await assign(binding, [section], fetcher: { try await client.hostOverrides() }) { self.hostOverrides = $0 }
        case .firewallLog:
            try await assign(binding, [section], fetcher: { try await client.firewallLog(limit: self.profile.logLimit) }) { self.firewallLog = $0 }
            capLogs()
        case .systemLog:
            try await assign(binding, [section], fetcher: { try await client.systemLog(limit: self.profile.logLimit) }) { self.systemLog = $0 }
            capLogs()
        case .authLog:
            try await assign(binding, [section], fetcher: { try await client.authLog(limit: self.profile.logLimit) }) { self.authLog = $0 }
            capLogs()
        case .dhcpLog:
            try await assign(binding, [section], fetcher: { try await client.dhcpLog(limit: self.profile.logLimit) }) { self.dhcpLog = $0 }
            capLogs()
        case .openvpnLog:
            try await assign(binding, [section], fetcher: { try await client.openvpnLog(limit: self.profile.logLimit) }) { self.openvpnLog = $0 }
            capLogs()
        case .openvpn:
            try await assign(binding, [section], fetcher: { try await client.openvpnServers() }) { self.openvpnServers = $0 }
        case .openvpnClients:
            try await assign(binding, [section], fetcher: { try await client.openvpnClients() }) { self.openvpnClients = $0 }
        case .ipsec:
            try await assign(binding, [section], fetcher: { try await client.ipsecSAs() }) { self.ipsecSAs = $0 }
        case .wireguard:
            let wg = try await checked(binding, sections: [section]) { try await client.wireguard() }
            guard isCurrent(binding) else { throw RPCError.cancelled }
            wireguardTunnels = wg.tunnels
            wireguardPeers = wg.peers
        case .firewall:
            // `force: true`, not the default. `loadFirewallObjects()` was
            // built to guard against repeating itself for a screen opening
            // for the first time — cheap on every open after the first,
            // exactly as intended there. Called the same way from inside a
            // refresh cycle, that guard means the opposite of what a refresh
            // is for: `hasLoadedFirewallObjects` being true from the first
            // load is precisely the case where a refresh needs to run, not
            // skip. Rules, port forwards and separators have been fetched
            // once per session and never again since this was added — silent,
            // because nothing about a stale rule list looks wrong until a
            // write depending on it, like a reorder, fails against a rule
            // that no longer exists and reports it as a mystery.
            await loadFirewallObjects(force: true)
            guard isCurrent(binding) else { throw RPCError.cancelled }
        case .aliases:
            try await assign(binding, [section], fetcher: { try await client.firewallAliases() }) { self.aliases = $0 }
        case .portForwards:
            await loadFirewallObjects(force: true)
            guard isCurrent(binding) else { throw RPCError.cancelled }
        case .carp:
            try await assign(binding, [section], fetcher: { try await client.carp() }) { self.carp = $0 }
        case .certificates:
            try await assign(binding, [section], fetcher: { try await client.certificates() }) { self.certificates = $0 }
        case .packages:
            try await assign(binding, [section], fetcher: { try await client.packages() }) { self.packages = $0 }
        case .filesystems:
            try await assign(binding, [section], fetcher: { try await client.filesystems() }) { self.filesystems = $0 }
        case .notices:
            try await assign(binding, [section], fetcher: { try await client.notices() }) { self.notices = $0 }
        case .dyndns:
            try await assign(binding, [section], fetcher: { try await client.dyndns() }) { self.dyndns = $0 }
        // Loaded when their own screen opens, not by section fetch. Retrying
        // one of these from Diagnostics goes through its loader instead.
        case .haproxy, .acme, .pfblocker, .dnsbl, .rrd, .configHistory, .tables, .packageUpdates:
            break
        }
    }

    private func assign<T>(_ binding: UUID, _ sections: [Section], fetcher: @escaping () async throws -> T, assign: @escaping (T) -> Void) async throws {
        let startTime = Date()
        let endpointName = sections.first?.rawValue ?? "unknown"
        do {
            let value: T = try await checked(binding, sections: sections) {
                var fresh = SectionFreshness()
                fresh.begin(binding, at: Date())
                do {
                    let result = try await fetcher()
                    fresh.succeed(binding, at: Date())
                    return result
                } catch {
                    let cancelled = error is CancellationError || (error as? RPCError) == .cancelled
                    fresh.fail(binding, message: cancelled ? nil : error.localizedDescription)
                    throw error
                }
            }
            let duration = Date().timeIntervalSince(startTime)
            performanceMetrics.recordAPIRequest(endpoint: endpointName, duration: duration, success: true)
            guard isCurrent(binding) else { throw RPCError.cancelled }
            assign(value)
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            performanceMetrics.recordAPIRequest(endpoint: endpointName, duration: duration, success: false)
            throw error
        }
    }

    /// Cap log arrays to prevent unbounded memory growth on busy firewalls.
    private static let maxLogLines = 2000

    private func capLogs() {
        if firewallLog.count > Self.maxLogLines { firewallLog = Array(firewallLog.prefix(Self.maxLogLines)) }
        if systemLog.count > Self.maxLogLines { systemLog = Array(systemLog.prefix(Self.maxLogLines)) }
        if authLog.count > Self.maxLogLines { authLog = Array(authLog.prefix(Self.maxLogLines)) }
        if dhcpLog.count > Self.maxLogLines { dhcpLog = Array(dhcpLog.prefix(Self.maxLogLines)) }
        if openvpnLog.count > Self.maxLogLines { openvpnLog = Array(openvpnLog.prefix(Self.maxLogLines)) }
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

    func beginIncidentTimeline() async {
        let binding = bindingID
        let needsSecondaryLogs = !wantsSecondaryLogs
        wantsSecondaryLogs = true
        if firewallLog.isEmpty { await runSection(.firewallLog) }
        guard isCurrent(binding) else { return }
        if needsSecondaryLogs || systemLog.isEmpty || authLog.isEmpty || dhcpLog.isEmpty || openvpnLog.isEmpty {
            await loadSecondaryLogsIfNeeded()
        }
    }

    func refreshIncidentTimeline() async {
        wantsSecondaryLogs = true
        let binding = bindingID
        for section: Section in [.firewallLog, .systemLog, .authLog, .dhcpLog, .openvpnLog] {
            guard isCurrent(binding), !Task.isCancelled else { return }
            await runSection(section)
        }
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

    func loadPFBlocker(force: Bool = false) async {
        let binding = bindingID
        let client = client
        if force { hasLoadedPFBlocker = false }
        guard isConfigured, !hasLoadedPFBlocker else { return }
        hasLoadedPFBlocker = true
        do {
            let result = try await checked(binding, sections: [.pfblocker], { try await client.pfBlocker() })
            guard isCurrent(binding) else { throw RPCError.cancelled }
            pfBlockerInstalled = result != nil
            pfBlocker = result
            errors[.pfblocker] = nil
        } catch {
            guard isCurrent(binding) else { return }
            hasLoadedPFBlocker = false   // let a pull-to-refresh try again
            errors[.pfblocker] = error.localizedDescription
        }
    }

    /// DNSBL statistics.
    ///
    /// Gated on pfBlockerNG being installed with DNSBL enabled, which means
    /// `loadPFBlocker` has to have run first — it is called here rather than
    /// assumed, so opening this screen directly works as well as arriving at
    /// it from the package screen.
    func loadDNSBLStats(force: Bool = false) async {
        let binding = bindingID
        let client = client
        if force { hasLoadedDNSBL = false }
        guard isConfigured, !hasLoadedDNSBL else { return }

        await loadPFBlocker(force: force)
        guard isCurrent(binding), dnsblAvailable else { return }

        hasLoadedDNSBL = true
        do {
            let result = try await checked(binding, sections: [.dnsbl], { try await client.dnsblStats() })
            guard isCurrent(binding) else { throw RPCError.cancelled }
            dnsblStats = result
            errors[.dnsbl] = nil
        } catch {
            guard isCurrent(binding) else { return }
            hasLoadedDNSBL = false
            errors[.dnsbl] = error.localizedDescription
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

    /// Fetch interface counters for external use (e.g., comparison view polling).
    func fetchInterfaceCounters() async throws -> [InterfaceStat] {
        try await client.interfaceCounters()
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

    func loadFirewallObjects(force: Bool = false) async {
        let binding = bindingID
        let client = client
        if force { hasLoadedFirewallObjects = false }
        guard isConfigured, !isLoadingFirewallObjects, !hasLoadedFirewallObjects else { return }
        isLoadingFirewallObjects = true
        defer { if bindingID == binding { isLoadingFirewallObjects = false } }
        do {
            let value = try await checked(binding, sections: [.firewall]) { try await client.firewallRules() }
            guard isCurrent(binding) else { throw RPCError.cancelled }
            rules = value
            errors[.firewall] = nil
        } catch {
            guard isCurrent(binding) else { return }
            hasLoadedFirewallObjects = false
            errors[.firewall] = error.localizedDescription
        }
        do {
            let value = try await checked(binding, sections: [.portForwards]) { try await client.portForwards() }
            guard isCurrent(binding) else { throw RPCError.cancelled }
            portForwards = value
            errors[.portForwards] = nil
            hasLoadedFirewallObjects = true
        } catch {
            guard isCurrent(binding) else { return }
            hasLoadedFirewallObjects = false
            errors[.portForwards] = error.localizedDescription
        }

        // Best-effort, and deliberately quiet about it. This is read-only
        // decoration on top of rules and forwards that already loaded
        // successfully — a missing or wrong separator changes nothing about
        // what traffic is allowed, so a failure here does not get an error
        // banner, does not clear `hasLoadedFirewallObjects`, and does not
        // block a retry of the section that actually matters.
        if let separators = try? await client.ruleSeparators(), isCurrent(binding) {
            filterSeparators = separators.filter
            natSeparators = separators.nat
            firewallChangesPending = separators.applyPending
        }
    }

    /// Guarantees one firewall-object read which starts after a write.
    ///
    /// `loadFirewallObjects(force: true)` still declines to start while an
    /// earlier load is in flight. That is right for ordinary refresh callers,
    /// but wrong after a mutation: the in-flight read may have started before
    /// the write and can legitimately contain the old order. Wait for it to
    /// finish, then begin the forced read while still on the main actor, so no
    /// other loader can enter between the check and `loadFirewallObjects`.
    func refreshFirewallObjectsAfterWrite() async {
        let binding = bindingID
        while isCurrent(binding), isLoadingFirewallObjects {
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard isCurrent(binding) else { return }
        await loadFirewallObjects(force: true)
    }

    /// Filter-rule separators, by interface. Position is inferred — see
    /// `RuleSeparator.afterRuleIndex` — and shown as a best effort rather than
    /// asserted as exact.
    var filterSeparators: [RuleSeparator] = []
    /// NAT separators. The storage path this reads was not confirmed against
    /// pfSense source the way the filter path was; an empty array here may
    /// mean there are none, or may mean the assumed path was wrong.
    var natSeparators: [RuleSeparator] = []

    var packagesNeedingUpdate: [PackageInfo] { packages.filter(\.updateAvailable) }

    // MARK: Package updates

    var isCheckingPackages = false
    var packageCheckResult: String?

    /// When the repository was last asked.
    ///
    /// Persisted so a relaunch does not repeat the check, and so the screen can
    /// say how old the answer is — "no updates" from a week ago is not the same
    /// claim as "no updates" from this morning.
    private(set) var lastPackageCheck: Date? {
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
                // `uniquingKeysWith`, not `uniqueKeysWithValues`: this is
                // built from whatever the firewall's repository returned, and
                // the trapping initialiser would turn two entries of one
                // package name into a crash rather than a duplicate row.
                let byName = Dictionary(checked.map { ($0.name, $0) },
                                        uniquingKeysWith: { _, latest in latest })
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
    var rrdHistory: RRDHistory? { rrdLoader.value }
    var isLoadingRRD: Bool { rrdLoader.isLoading }
    var rrdWindow: PHPSnippet.RRDWindow { rrdLoader.key ?? .week }
    var widenedFromEmpty = false

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

    // MARK: Firmware

    var isCheckingFirmware = false
    var firmwareCheckResult: String?

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
    var favouriteInterfaces: Set<String> = [] {
        didSet {
            UserDefaults.standard.set(Array(favouriteInterfaces), forKey: UDKey.favouriteInterfaces.rawValue)
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
        guard !UserDefaults.standard.bool(forKey: UDKey.favouritesSeeded.rawValue) else { return }
        UserDefaults.standard.set(true, forKey: UDKey.favouritesSeeded.rawValue)

        let wanted = interfaces.filter { iface in
            let name = iface.name.lowercased()
            let internalName = (iface.internalName ?? "").lowercased()
            return internalName == "wan" || internalName == "lan"
                || name.hasPrefix("wan") || name.hasPrefix("lan")
        }
        favouriteInterfaces.formUnion(wanted.map(\.seriesKey))
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

    /// The client list's entry for an address, if it has one.
    ///
    /// A capture reports addresses; the client list is keyed by device. Most of
    /// the time the address the capture saw is the one the client list shows
    /// and a direct match is the answer.
    ///
    /// When it is not — a device holding several addresses, or one whose
    /// client-list entry came from a lease while the capture caught it on a
    /// second address — the ARP and DHCP tables know which MAC is behind the
    /// address, and the MAC is what identifies a device. Matching that way
    /// rather than giving up means a second address does not become a row that
    /// mysteriously will not open.
    ///
    /// Nil for anything the firewall does not recognise as a client, which on
    /// a WAN is most of what a capture returns.
    func client(matching address: String) -> NetworkClient? {
        guard let key = ClientAddress.key(address) else { return nil }

        if let direct = overviewLayout.clients.first(where: { ClientAddress.key($0.ip) == key }) {
            return direct
        }

        let mac = arp.first(where: { ClientAddress.key($0.ip) == key })?.mac
            ?? leases.first(where: { ClientAddress.key($0.ip) == key })?.mac
        guard let mac, !mac.isEmpty, mac != "—" else { return nil }
        return overviewLayout.clients.first { $0.mac == mac }
    }

    /// Load the tables the investigation screen searches.
    ///
    /// Several of them load only when their own screen is first opened, which
    /// made the search quietly incomplete: the answer to "which rules apply to
    /// this device" was "none" until somebody had happened to visit the
    /// Firewall screen first. A search screen that depends on where you have
    /// been is worse than one that takes a moment to open.
    ///
    /// Each loader already guards against repeating itself, so this is cheap
    /// on every open after the first. They run one after another rather than
    /// together because pfSense serialises `exec_php` against its own web UI
    /// anyway — starting three at once would not make them finish sooner, and
    /// would take the webConfigurator down with them if they did.
    ///
    /// DNSBL is not forced. It is the only one that reads a megabyte of log,
    /// and it declines by itself when pfBlockerNG is absent or its DNSBL
    /// component is off — which on most firewalls is always.
    func loadInvestigationData() async {
        await loadFirewallObjects()
        await loadDNSBLStats()
    }

    /// Interfaces reporting new errors since the last refresh.
    var interfacesWithRisingErrors: [InterfaceStat] {
        interfaceErrors.rising(among: interfaces)
    }

    /// How many contradictions the client tables currently hold.
    ///
    /// Only the ones that break traffic, so the badge on More means "something
    /// is wrong now" rather than "there is a list to read". A duplicate
    /// hostname is worth showing on the screen and is not worth a badge.
    var conflictCount: Int {
        ConflictDetector.find(arp: arp, leases: leases,
                              staticMappings: staticMappings,
                              hostOverrides: hostOverrides)
            .filter { $0.kind.severity == .bad }
            .count
    }

    /// Where an interface sits in the list the host-traffic sampler indexes.
    ///
    /// Matches the way `interfaceLabel` does — a device name, pfSense's
    /// internal handle, or the description — because the hint arrives from
    /// whichever table happened to know about the device. The ARP table spells
    /// it `lagg0.100`; a DHCP lease spells the same interface `lan`.
    ///
    /// Nil when nothing matches, and the caller has to handle that rather than
    /// fall back to a default. Sampling the wrong interface would attribute
    /// one network's traffic to a device on another, which is a more
    /// misleading answer than no answer.
    func interfaceSlot(for raw: String?) -> Int? {
        guard let raw, !raw.isEmpty, !raw.contains(",") else { return nil }
        let lowered = raw.lowercased()
        return interfaces.firstIndex { iface in
            iface.device.lowercased() == lowered
                || iface.internalName?.lowercased() == lowered
                || iface.name.lowercased() == lowered
        }
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
        if let client = overviewLayout.clients.first(where: { $0.ip == ip }), client.name != ip {
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

    // MARK: Auto refresh

    func startAutoRefresh() {
        let interval = max(10, profile.refreshSeconds)
        refreshScheduler = RefreshScheduler(interval: TimeInterval(interval))
        refreshScheduler?.start { [self] in
            await refresh()
        }
    }

    func stopAutoRefresh() {
        refreshScheduler?.stop(reason: .manual)
        refreshScheduler = nil
    }

    func logLines(matching ip: String) -> [LogLine] {
        let keys = Set([ip].compactMap(ClientAddress.key))
        return firewallLog.filter { $0.involves(addresses: keys) }
    }

    func refreshClientInvestigation() async {
        let binding = bindingID
        for section: Section in [.leases, .arp, .statics, .hostOverrides, .aliases, .firewallLog] {
            guard isCurrent(binding), !Task.isCancelled else { return }
            await fetch(section)
        }
    }
}

// MARK: - Singleton for Shortcuts/App Intents
extension DashboardStore {
    static weak var shared: DashboardStore?
}
