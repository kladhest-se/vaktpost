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
                            .font(.system(size: 13))
                            .foregroundStyle(theme.label)
                    }
                }

                if store.criticalAlertCount > 0 { alertsTeaser }

                GroupHeading(text: "Uplink")
                wanSlab

                GroupHeading(text: "System")
                systemSlab
                statesSlab
                if let carp = store.carp, carp.isConfigured { carpSlab(carp) }

                GroupHeading(text: "Gateways")
                if store.gateways.isEmpty {
                    Slab(rail: .idle) {
                        Text(store.errors[.gateways] ?? "No gateway status returned.")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.labelMuted)
                    }
                } else {
                    ForEach(store.gateways) { GatewayRow(gateway: $0) }
                }

                GroupHeading(text: "Services")
                servicesSlab

                GroupHeading(text: "Firewall")
                firewallSlab
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .background(theme.bg.ignoresSafeArea())
        .refreshable { await store.refresh() }
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
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.label)
                Spacer()
            }
            HStack(spacing: 6) {
                Text(store.profile.displayName)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.labelMuted)
                if let v = store.version?.current {
                    Text("·").foregroundStyle(theme.labelFaint)
                    Text(v)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(theme.labelMuted)
                }
                Spacer()
                if let last = store.lastRefresh {
                    Text(last, style: .time)
                        .font(.system(size: 11, design: .monospaced))
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(registry.servers) { server in
                    Button {
                        Task { await store.switchTo(server) }
                    } label: {
                        Text(server.displayName)
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(registry.active?.id == server.id ? theme.accentColor : theme.card)
                            .foregroundStyle(registry.active?.id == server.id
                                             ? theme.palette.crust : theme.labelMuted)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var alertsTeaser: some View {
        NavigationLink { AlertsView() } label: {
            Slab(rail: store.alerts.first?.severity ?? .warn, title: "Alerts",
                 trailing: "\(store.criticalAlertCount)") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(store.alerts.prefix(3)) { alert in
                        HStack(spacing: 8) {
                            Image(systemName: alert.category.symbol)
                                .font(.system(size: 12))
                                .foregroundStyle(alert.severity.color(theme))
                                .frame(width: 16)
                            Text(alert.title)
                                .font(.system(size: 13))
                                .foregroundStyle(theme.label)
                                .lineLimit(1)
                            Spacer()
                        }
                    }
                    if store.alerts.count > 3 {
                        Text("+\(store.alerts.count - 3) more")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.labelFaint)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: WAN

    @ViewBuilder
    private var wanSlab: some View {
        if let wan = store.wanInterface {
            let points = store.throughput.points(for: wan.device)
            Slab(rail: wan.health, title: wan.name, trailing: wan.device) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(wan.addressLine)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(theme.labelMuted)

                    if points.count > 1 {
                        Sparkline(
                            inSeries: points.map(\.inBps),
                            outSeries: points.map(\.outBps),
                            height: 56
                        )
                        RateLegend(inBps: points.last?.inBps, outBps: points.last?.outBps)
                        Text("Derived from counter deltas over the last \(points.count) samples.")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.labelFaint)
                    } else {
                        Text("Collecting samples — a rate needs two refreshes.")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.labelFaint)
                    }
                }
            }
        } else {
            Slab(rail: .idle) {
                Text("No interface identified as the uplink yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.labelMuted)
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
                              health: level(cpu, warn: 70, bad: 90))
                    }
                    if let mem = sys.memUsage {
                        Meter(label: "Memory", value: mem / 100, readout: Fmt.pct(mem),
                              health: level(mem, warn: 80, bad: 92))
                    }
                    if let disk = sys.diskUsage {
                        Meter(label: "Disk", value: disk / 100, readout: Fmt.pct(disk),
                              health: level(disk, warn: 80, bad: 92))
                    }
                    if let swap = sys.swapUsage, swap > 0 {
                        Meter(label: "Swap", value: swap / 100, readout: Fmt.pct(swap),
                              health: level(swap, warn: 25, bad: 60))
                    }
                    if let mbuf = sys.mbufUsage {
                        Meter(label: "mbuf", value: mbuf / 100, readout: Fmt.pct(mbuf),
                              health: level(mbuf, warn: 75, bad: 90))
                    }
                    Hairline()
                    FieldRow(key: "Load average", value: sys.loadDescription)
                    if let t = sys.temperature {
                        FieldRow(key: "Temperature", value: String(format: "%.1f °C", t))
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
                        label: "States in use",
                        value: frac,
                        readout: "\(st.current ?? 0) / \(st.maximum ?? 0)",
                        health: level(frac * 100, warn: 70, bad: 88)
                    )
                } else {
                    FieldRow(key: "Current states", value: "\(st.current ?? 0)")
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
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.label)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
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
                                .font(.system(size: 13, weight: .medium))
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
                        counter("Blocked", store.blockedRecently, .bad)
                        counter("Passed", store.firewallLog.count - store.blockedRecently, .ok)
                        Spacer()
                    }
                    Hairline()
                    ForEach(store.firewallLog.prefix(4)) { LogRow(line: $0, compact: true) }
                }
            }
        }
    }

    private func counter(_ label: String, _ value: Int, _ health: Health) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(health.color(theme))
            Text(label)
                .font(.system(size: 11, weight: .medium))
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
                .font(.system(size: 12))
                .foregroundStyle(theme.warn)
        } else {
            Text("No data yet")
                .font(.system(size: 12))
                .foregroundStyle(theme.labelFaint)
        }
    }
}

struct GatewayRow: View {
    @EnvironmentObject private var theme: ThemeManager
    let gateway: GatewayStatus

    var body: some View {
        Slab(rail: gateway.health) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(gateway.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.label)
                    Spacer()
                    StatusPill(text: gateway.status, health: gateway.health)
                }
                Text(gateway.readout)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.labelMuted)
                if let ip = gateway.monitorIP, !ip.isEmpty {
                    Text("monitor \(ip)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme.labelFaint)
                }
            }
        }
    }
}
