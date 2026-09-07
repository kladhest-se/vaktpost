import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var store: DashboardStore
    @EnvironmentObject private var registry: ServerRegistry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                banner

                if registry.servers.count > 1 { serverSwitcher }

                if let msg = store.connectionError {
                    Slab(rail: .bad, title: "Connection") {
                        Text(msg)
                            .scaledFont(13)
                            .foregroundStyle(theme.label)
                    }
                }

                if store.criticalAlertCount > 0 { alertsTeaser }

                GroupHeading(text: store.favouriteInterfaces.isEmpty ? "Uplink" : "Interfaces")
                uplinkSlabs

                GroupHeading(text: "System")
                systemSlab
                statesSlab
                if let carp = store.carp, carp.isConfigured { carpSlab(carp) }

                GroupHeading(text: "Gateways")
                if store.gateways.isEmpty {
                    Slab(rail: .idle) {
                        Text(store.errors[.gateways] ?? "No gateway status returned.")
                            .scaledFont(13)
                            .foregroundStyle(theme.labelMuted)
                    }
                } else {
                    ForEach(store.gateways) { GatewayRow(gateway: $0, gatewayMetrics: store.gatewayMetrics) }
                }

                GroupHeading(text: "Services")
                servicesSlab

                GroupHeading(text: "Firewall")
                firewallSlab
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
            .readableWidth()
        }
        .background(theme.bg.ignoresSafeArea())
        .refreshable { await store.refreshManually() }
        .navigationTitle("Overview")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { AlertsView() } label: {
                    Image(systemName: store.criticalAlertCount > 0 ? "bell.badge.fill" : "bell")
                        .foregroundStyle(store.criticalAlertCount > 0 ? theme.warn : theme.labelMuted)
                }
            }
        }
    }

    // MARK: Banner

    private var banner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Circle()
                    .fill(store.overallHealth.color(theme))
                    .frame(width: 10, height: 10)
                Text(store.headline)
                    .scaledFont(16, weight: .semibold)
                    .foregroundStyle(theme.label)
                Spacer()
            }
            HStack(spacing: 6) {
                Text(store.profile.displayName)
                    .scaledFont(12, weight: .medium, design: .monospaced)
                    .foregroundStyle(theme.labelMuted)
                if let v = store.version?.current {
                    Text("·").foregroundStyle(theme.labelFaint)
                    Text(v)
                        .scaledFont(12, design: .monospaced)
                        .foregroundStyle(theme.labelMuted)
                }
                Spacer()
                if let last = store.lastRefresh {
                    Text(last, style: .time)
                        .scaledFont(11, design: .monospaced)
                        .foregroundStyle(theme.labelFaint)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.bgSunken)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(store.overallHealth.color(theme).opacity(0.35), lineWidth: 1)
        )
        .padding(.top, 8)
    }

    private var serverSwitcher: some View {
        ServerSwitcher(
            servers: registry.servers,
            activeID: registry.active?.id
        ) { server in
            Task { await store.switchTo(server) }
        }
    }

    private var alertsTeaser: some View {
        NavigationLink { AlertsView() } label: {
            Slab(rail: store.visibleAlerts.first?.severity ?? .warn, title: "Alerts",
                 trailing: "\(store.criticalAlertCount)") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(store.visibleAlerts.prefix(3)) { alert in
                        HStack(spacing: 8) {
                            Image(systemName: alert.category.symbol)
                                .scaledFont(12)
                                .foregroundStyle(alert.severity.color(theme))
                                .scaledFrame(width: 16)
                            Text(alert.title)
                                .scaledFont(13)
                                .foregroundStyle(theme.label)
                                .lineLimit(2)
                            Spacer()
                        }
                    }
                    if store.visibleAlerts.count > 3 {
                        Text("+\(store.visibleAlerts.count - 3) more")
                            .scaledFont(11)
                            .foregroundStyle(theme.labelFaint)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Interfaces

    /// The interfaces worth watching: whatever has been starred on the Network
    /// tab, or the uplink if nothing has.
    @ViewBuilder
    private var uplinkSlabs: some View {
        let shown = store.overviewInterfaces
        if shown.isEmpty {
            Slab(rail: .idle) {
                Text("No interface identified as the uplink yet.")
                    .scaledFont(13)
                    .foregroundStyle(theme.labelMuted)
            }
        } else {
            ForEach(shown) { iface in
                // Tappable, like the Network tab: the same interface, watched
                // at two-second resolution instead of thirty.
                NavigationLink {
                    InterfaceDetailView(iface: iface)
                } label: {
                    Slab(rail: iface.health, title: iface.name, trailing: iface.device) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(iface.addressLine)
                                .scaledFont(12, design: .monospaced)
                                .foregroundStyle(theme.labelMuted)
                            // Taller than a sparkline, because these are the
                            // interfaces somebody chose to watch. 56 points is
                            // enough to say "there is traffic" and not enough
                            // to see its shape, which is the question a pinned
                            // interface is pinned for.
                            ThroughputChart(
                                tracker: store.throughput,
                                store: store,
                                device: iface.seriesKey,
                                height: 110,
                                showExplanatoryText: true
                            )
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: System

    private var systemSlab: some View {
        Slab(rail: .info, title: "Resources", trailing: uptimeText) {
            if let sys = store.system {
                VStack(spacing: 12) {
                    if let cpu = sys.cpuUsage {
                        Meter(label: "CPU", value: cpu / 100, readout: Fmt.pct(cpu),
                              health: level(cpu, warn: HealthThresholds.cpuWarn, bad: HealthThresholds.cpuBad))
                        SingleMetricSparkline(values: store.systemMetrics.points(for: "cpu").map(\.value),
                                              label: "CPU", height: 24)
                    }
                    if let mem = sys.memUsage {
                        Meter(label: "Memory", value: mem / 100, readout: Fmt.pct(mem),
                              health: level(mem, warn: HealthThresholds.memWarn, bad: HealthThresholds.memBad))
                        SingleMetricSparkline(values: store.systemMetrics.points(for: "mem").map(\.value),
                                              label: "Memory", height: 24)
                    }
                    if let disk = sys.diskUsage {
                        Meter(label: "Disk", value: disk / 100, readout: Fmt.pct(disk),
                              health: level(disk, warn: HealthThresholds.diskWarn, bad: HealthThresholds.diskBad))
                        SingleMetricSparkline(values: store.systemMetrics.points(for: "disk").map(\.value),
                                              label: "Disk", height: 24)
                    }
                    if let swap = sys.swapUsage, swap > 0 {
                        Meter(label: "Swap", value: swap / 100, readout: Fmt.pct(swap),
                              health: level(swap, warn: HealthThresholds.swapWarn, bad: HealthThresholds.swapBad))
                        SingleMetricSparkline(values: store.systemMetrics.points(for: "swap").map(\.value),
                                              label: "Swap", height: 24)
                    }
                    if let mbuf = sys.mbufUsage {
                        Meter(label: "mbuf", value: mbuf / 100, readout: Fmt.pct(mbuf),
                              health: level(mbuf, warn: HealthThresholds.mbufWarn, bad: HealthThresholds.mbufBad))
                    }
                    Hairline()
                    FieldRow(key: "Load average", value: sys.loadDescription)
                    if let t = sys.temperature {
                        FieldRow(key: "Temperature", value: String(format: "%.1f °C", t))
                    } else {
                        // Said once, quietly, rather than left as a gap. The
                        // API returns null until a thermal sensor module is
                        // loaded, and there is no way to tell that apart from
                        // "this box has no sensor" without saying so.
                        FieldRow(key: "Temperature",
                                 value: "no sensor loaded",
                                 mono: false)
                    }
                    if let hardware = sys.hardwareDescription {
                        FieldRow(key: "Hardware", value: hardware, mono: false)
                    }
                }
            } else {
                placeholder(.system)
            }
        }
    }

    private var uptimeText: String? {
        store.system?.uptimeSeconds.map { "up \(Fmt.uptime($0))" }
    }

    private var statesSlab: some View {
        Slab(rail: .info, title: "State table") {
            if let st = store.states {
                if let frac = st.fraction {
                    Meter(
                        label: st.isDefaultLimit ? "States in use (default limit)" : "States in use",
                        value: frac,
                        readout: "\(st.current ?? 0) / \(st.effectiveMaximum ?? 0)",
                        health: level(frac * 100, warn: 70, bad: 88)
                    )
                    StateTrendLine(values: store.stateHistory.points.map(\.value), max: st.effectiveMaximum ?? 0)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        FieldRow(key: "Current states", value: "\(st.current ?? 0)")
                        if !store.stateHistory.points.isEmpty {
                            StateTrendLine(values: store.stateHistory.points.map(\.value), max: 10000)
                        }
                    }
                }
            } else {
                placeholder(.states)
            }
        }
    }

    private func carpSlab(_ carp: CARPStatus) -> some View {
        NavigationLink { SystemView() } label: {
            Slab(rail: carp.health, title: "CARP") {
                HStack {
                    Text(carp.summary)
                        .scaledFont(13, weight: .medium)
                        .foregroundStyle(theme.label)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .scaledFont(11, weight: .semibold)
                        .foregroundStyle(theme.labelFaint)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Services

    private var servicesSlab: some View {
        let down = store.servicesDown
        return Slab(
            rail: down.isEmpty ? .ok : .bad,
            title: "Service health",
            trailing: "\(store.services.count) total"
        ) {
            if store.services.isEmpty {
                placeholder(.services)
            } else if down.isEmpty {
                HStack {
                    StatusPill(text: "all running", health: .ok)
                    Spacer()
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(down) { svc in
                        HStack {
                            Text(svc.descr ?? svc.name)
                                .scaledFont(13, weight: .medium)
                                .foregroundStyle(theme.label)
                            Spacer()
                            StatusPill(text: svc.status.isEmpty ? "stopped" : svc.status, health: .bad)
                        }
                    }
                }
            }
        }
    }

    // MARK: Firewall

    private var firewallSlab: some View {
        Slab(rail: .info, title: "Recent filter activity",
             trailing: "last \(store.firewallLog.count) lines") {
            if store.firewallLog.isEmpty {
                placeholder(.firewallLog)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 18) {
                        deltaCounter("Blocked", store.blockedRecently, store.blockedDelta, .bad)
                        deltaCounter("Rejected", store.rejectedRecently, store.rejectedDelta, .warn)
                        deltaCounter("Passed", store.passedRecently, store.passedDelta, .ok)
                        Spacer()
                    }
                    Hairline()
                    ForEach(store.firewallLog.prefix(4)) { LogRow(line: $0, compact: true) }
                }
            }
        }
    }

    private func deltaCounter(_ label: String, _ value: Int, _ delta: Int?, _ health: Health) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(value)")
                    .scaledFont(22, weight: .bold, design: .rounded)
                    .foregroundStyle(health.color(theme))
                if let delta {
                    let sign = delta > 0 ? "↑" : delta < 0 ? "↓" : "→"
                    let pct = Int(abs(Double(delta) / Double(max(store.prevFirewallCounts.blocked, store.prevFirewallCounts.rejected, store.prevFirewallCounts.passed, 1)) * 100))
                    Text("\(sign) \(pct)%")
                        .scaledFont(11, weight: .medium, design: .monospaced)
                        .foregroundStyle(delta > 0 ? theme.bad.opacity(0.8) : delta < 0 ? theme.ok.opacity(0.8) : theme.labelMuted)
                }
            }
            Text(label)
                .scaledFont(11, weight: .medium)
                .foregroundStyle(theme.labelFaint)
        }
    }

    // MARK: Helpers

    private func level(_ v: Double, warn: Double, bad: Double) -> Health {
        if v >= bad { return .bad }
        if v >= warn { return .warn }
        return .ok
    }

    @ViewBuilder
    private func placeholder(_ section: DashboardStore.Section) -> some View {
        if let err = store.errors[section] {
            Text(err)
                .scaledFont(12)
                .foregroundStyle(theme.warn)
        } else {
            Text("No data yet")
                .scaledFont(12)
                .foregroundStyle(theme.labelFaint)
        }
    }
}

struct GatewayRow: View {
    @EnvironmentObject private var theme: ThemeManager
    let gateway: GatewayStatus
    /// Not optional. The store's tracker is a `let` that is never nil, so the
    /// optional only ever held a value — and an optional cannot be observed,
    /// which is what kept this row from redrawing as latency changed.
    @ObservedObject var gatewayMetrics: GatewayMetricTracker

    private var delayPoints: [Double] {
        gatewayMetrics.readings(for: gateway.name).compactMap { $0.delayMS }
    }

    private var lossPoints: [Double] {
        gatewayMetrics.readings(for: gateway.name).compactMap { $0.lossPercent }
    }

    var body: some View {
        Slab(rail: gateway.health) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(gateway.name)
                        .scaledFont(15, weight: .semibold)
                        .foregroundStyle(theme.label)
                    Spacer()
                    StatusPill(text: gateway.status, health: gateway.health)
                }
                Text(gateway.readout)
                    .scaledFont(12, design: .monospaced)
                    .foregroundStyle(theme.labelMuted)
                GatewayTrend(
                    delayPoints: delayPoints,
                    lossPoints: lossPoints,
                    latestDelay: gateway.delayMS,
                    latestLoss: gateway.lossPercent
                )
                if let ip = gateway.monitorIP, !ip.isEmpty {
                    Text("monitor \(ip)")
                        .scaledFont(11, design: .monospaced)
                        .foregroundStyle(theme.labelFaint)
                }
            }
        }
    }
}
