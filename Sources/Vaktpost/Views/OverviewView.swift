import SwiftUI

struct OverviewView: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore
    @Environment(\.serverRegistry) private var registry: ServerRegistry

    @State private var visibleSections: [OverviewSection] = []
    @State private var draggedSection: OverviewSection?
    @State private var collapsedSections: Set<String> = []
    /// The measured height of each section.
    ///
    /// A single estimate was why dragging felt wrong: the status banner is a
    /// third of the system card, so one number was too large for half the
    /// sections and too small for the rest, and a card would jump two places
    /// or refuse to move. Each row reports its own height and the drag walks
    /// the real geometry.
    @State private var sectionHeights: [OverviewSection: CGFloat] = [:]
    @State private var isEditing = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                theme.bg.ignoresSafeArea()
                
                ScrollView {
                    PageHeader(title: "Overview", subtitle: store.profile.displayName)
                    VStack(alignment: .leading, spacing: 14) {
                        if let msg = store.connectionError {
                            connectionBannerContent(for: msg)
                        }

                        if store.alertManager.criticalAlertCount > 0 {
                            alertsTeaser
                                .wobble(isEditing)
                        }

                        let indexedSections = Array(visibleSections.enumerated())
                        ForEach(indexedSections, id: \.element.self) { index, section in
                            SectionView(
                                section: section,
                                title: section.displayName,
                                isEditing: $isEditing,
                                visibleSections: $visibleSections,
                                collapsedSections: $collapsedSections,
                                registry: registry,
                                content: { sectionContentView(section) },
                                draggedSection: $draggedSection,
                                sectionHeights: $sectionHeights,
                                currentIndex: index
                            )
                        }

                        if isEditing {
                            hiddenSectionsPicker
                        }
                        
                        if visibleSections.isEmpty && !isEditing {
                            Spacer(minLength: 200)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .gesture(longPressGesture)
            .refreshable { await store.refreshManually() }
            .onChange(of: registry.active?.id) { _, _ in loadVisibleSections() }
            .onChange(of: registry.active?.overviewVisibleSections) { _, _ in loadVisibleSections() }
            .onAppear { loadVisibleSections() }
            .onChange(of: store.isOverviewEditing) { _, isEditing in
                self.isEditing = isEditing
                if isEditing { loadVisibleSections() }
            }
            .onChange(of: registry.active?.overviewVisibleSections) { _, _ in
                if isEditing { loadVisibleSections() }
            }
        }
    }

    private var longPressGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .onEnded { _ in
                store.isOverviewEditing.toggle()
            }
    }

    private func connectionBannerContent(for msg: String) -> some View {
        Slab(rail: .bad, title: "Connection") {
            Text(msg)
                .scaledFont(13)
                .foregroundStyle(theme.label)
        }
    }

    private func loadVisibleSections() {
        guard let active = registry.active else { return }
        // The stored array in its stored order.
        //
        // Filtering `allCases` returned declaration order and threw the saved
        // arrangement away, so a section dragged to the top came back in the
        // middle on the next appearance.
        // Migrate the stored names first, and write them back.
        //
        // Expanding an old name at read time and leaving it in storage was
        // half a migration. Hiding VPN servers removed `vpnServers`, which was
        // never stored; `vpn` stayed, and the next load expanded it again — so
        // both VPN sections reappeared as soon as anything else was added,
        // which looked exactly like the sections being linked together.
        var names = active.overviewVisibleSections
        if let migrated = OverviewSection.migrate(storedNames: names) {
            names = migrated
            registry.setOverviewSectionNames(active, migrated)
        }

        var seen = Set<OverviewSection>()
        visibleSections = names
            .compactMap(OverviewSection.init(rawValue:))
            .filter { seen.insert($0).inserted }
        collapsedSections = Set(active.collapsedSections.compactMap { OverviewSection.init(rawValue: $0) }.map(\.rawValue))
    }
    
    private func resetSections() {
        guard let active = registry.active else { return }
        registry.resetSectionOrder(toDefault: active)
        loadVisibleSections()
    }
    
    @ViewBuilder
    private var hiddenSectionsPicker: some View {
        let hidden = OverviewSection.allCases.filter { !visibleSections.contains($0) }
        VStack(alignment: .leading, spacing: 8) {
            if hidden.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hidden Sections")
                        .scaledFont(12, weight: .semibold)
                        .foregroundStyle(theme.labelFaint)
                        .padding(.top, 8)
                    
                    ForEach(hidden) { section in
                        HStack {
                            Text(section.displayName)
                                .scaledFont(14)
                                .foregroundStyle(theme.label)
                            Spacer()
                            Button {
                                addSection(section)
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(theme.ok)
                                    .scaledFont(20)
                            }
                        }
                    }
                }
            }
            
            Button {
                resetSections()
            } label: {
                Label("Reset to Default", systemImage: "arrow.counterclockwise")
                    .scaledFont(14)
                    .foregroundStyle(theme.label)
            }
        }
    }
    
    private func addSection(_ section: OverviewSection) {
        if !visibleSections.contains(section) {
            visibleSections.append(section)
        }
        guard let active = registry.active else { return }
        registry.setOverviewSectionVisibility(active, section, visible: true)
    }

    /// No `@ViewBuilder`: this returns `AnyView` through explicit `return`
    /// statements, which turns the builder off anyway and warns about it.
    private func sectionContentView(_ section: OverviewSection) -> AnyView {
        switch section {
        case .status:
            return AnyView(statusSlab.sectionFreshness([.system]))
        case .interfaces:
            return AnyView(interfacesSlab.sectionFreshness([.interfaces]))
        case .system:
            return AnyView(systemSlab.sectionFreshness([.system]))
        case .gateways:
            return AnyView(gatewaysSlab.sectionFreshness([.gateways]))
        case .services:
            return AnyView(servicesSlab.sectionFreshness([.services]))
        case .firewall:
            return AnyView(firewallSlab.sectionFreshness([.firewallLog]))
        case .vpnServers:
            return AnyView(vpnServersSlab)
        case .vpnClients:
            return AnyView(vpnClientsSlab)
        case .clients:
            return AnyView(topTalkersSlab)
        case .dnsbl:
            return AnyView(dnsblSlab)
        }
    }

    /// DNSBL, when there is a DNSBL.
    ///
    /// The section is always in the list — it has to be, or somebody who
    /// installs pfBlockerNG later would have to find a hidden section to turn
    /// it on. What varies is what it says: a firewall without the package gets
    /// one line explaining why there is nothing here, not an empty card and
    /// not a spinner that never resolves.
    private var dnsblSlab: some View {
        NavigationLink { DNSBLStatsView() } label: {
            Slab(rail: store.dnsblAvailable ? .ok : .idle, title: "DNSBL",
                 trailing: store.dnsblStats.map { "\($0.events)" }) {
                VStack(alignment: .leading, spacing: 6) {
                    if !store.pfBlockerInstalled {
                        Text("pfBlockerNG is not installed on this firewall.")
                            .scaledFont(12)
                            .foregroundStyle(theme.labelMuted)
                    } else if !store.dnsblAvailable {
                        Text("pfBlockerNG is installed, but DNSBL is switched off.")
                            .scaledFont(12)
                            .foregroundStyle(theme.labelMuted)
                    } else if let stats = store.dnsblStats, stats.available {
                        // A donut and four names. The shape is what a glance
                        // is for: one wedge swallowing the circle is a device
                        // that has started phoning somewhere new, and that is
                        // legible before any of the labels are read.
                        let slices = DonutChart.slices(stats.domains, total: stats.events,
                                                       limit: 4, theme: theme)
                        HStack(alignment: .center, spacing: 14) {
                            DonutChart(slices: slices,
                                       centerValue: "\(stats.events)",
                                       centerCaption: "blocked",
                                       thickness: 13)
                                .frame(width: 104, height: 104)
                            DonutLegend(slices: slices)
                        }
                        if let busiest = stats.busiestHour {
                            Text("Busiest hour \(busiest.label) with \(busiest.count).")
                                .scaledFont(11)
                                .foregroundStyle(theme.labelFaint)
                        }
                    } else {
                        Text("Nothing blocked in the log yet.")
                            .scaledFont(12)
                            .foregroundStyle(theme.labelMuted)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .task { await store.loadDNSBLStats() }
    }

    private var alertsTeaser: some View {
        NavigationLink { AlertsView() } label: {
            Slab(rail: store.alertManager.visibleAlerts.first?.severity ?? .warn, title: "Alerts",
                 trailing: "\(store.alertManager.criticalAlertCount)") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(store.alertManager.visibleAlerts.prefix(3)) { alert in
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
                    if store.alertManager.visibleAlerts.count > 3 {
                        Text("+\(store.alertManager.visibleAlerts.count - 3) more")
                            .scaledFont(11)
                            .foregroundStyle(theme.labelFaint)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var statusSlab: some View {
        Slab(rail: store.overviewLayout.overallHealth) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Overall")
                        .scaledFont(11, weight: .semibold)
                        .foregroundStyle(theme.labelFaint)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(store.overviewLayout.overallHealth.color(theme))
                            .frame(width: 8, height: 8)
                        Text(store.overviewLayout.overallHealth.name.uppercased())
                            .scaledFont(14, weight: .semibold)
                            .foregroundStyle(theme.label)
                    }
                }

                Divider()
                    .frame(height: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Uptime")
                        .scaledFont(11, weight: .semibold)
                        .foregroundStyle(theme.labelFaint)
                    if let uptime = store.system?.uptimeSeconds {
                        Text(formatUptime(Double(uptime)))
                            .scaledFont(14, weight: .medium)
                            .foregroundStyle(theme.label)
                    }
                }

                Divider()
                    .frame(height: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Interfaces")
                        .scaledFont(11, weight: .semibold)
                        .foregroundStyle(theme.labelFaint)
                    Text("\(store.overviewLayout.interfacesUp) of \(store.interfaces.count)")
                        .scaledFont(14, weight: .medium)
                        .foregroundStyle(theme.label)
                }

                Divider()
                    .frame(height: 30)

                NavigationLink {
                    UpdatesView()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 3) {
                            Text("Updates")
                                .scaledFont(11, weight: .semibold)
                                .foregroundStyle(theme.labelFaint)
                            Image(systemName: "chevron.right")
                                .scaledFont(8, weight: .bold)
                                .foregroundStyle(theme.labelFaint)
                        }
                        if let version = store.version, version.updateAvailable == true {
                            if let latest = version.latest {
                                Text("v\(latest)")
                                    .scaledFont(14, weight: .medium)
                                    .foregroundStyle(theme.warn)
                            }
                        } else if store.packagesNeedingUpdate.isEmpty && (store.version?.updateAvailable != true) {
                            Text("up to date")
                                .scaledFont(14, weight: .medium)
                                .foregroundStyle(theme.ok)
                        } else if !store.packagesNeedingUpdate.isEmpty {
                            Text("\(store.packagesNeedingUpdate.count) pkg\(store.packagesNeedingUpdate.count > 1 ? "s" : "")")
                                .scaledFont(14, weight: .medium)
                                .foregroundStyle(theme.warn)
                        } else {
                            Text(store.packageCheckAge.map { "checked \($0)" } ?? "—")
                                .scaledFont(14, weight: .medium)
                                .foregroundStyle(theme.labelMuted)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func formatUptime(_ seconds: Double) -> String {
        let days = Int(seconds) / 86400
        let hours = (Int(seconds) % 86400) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if days > 0 {
            return "\(days)d \(hours)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    private var interfacesSlab: some View {
        let shown = store.overviewInterfaces
        if shown.isEmpty {
            return AnyView(Slab(rail: .idle) {
                Text("No interface identified as the uplink yet.")
                    .scaledFont(13)
                    .foregroundStyle(theme.labelMuted)
            })
        } else {
            return AnyView(VStack(alignment: .leading, spacing: 10) {
                ForEach(shown) { iface in
                    NavigationLink {
                        InterfaceDetailView(iface: iface)
                    } label: {
                        Slab(rail: iface.health, title: iface.name, trailing: iface.device) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(iface.addressLine)
                                    .scaledFont(12, design: .monospaced)
                                    .foregroundStyle(theme.labelMuted)
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
            })
        }
    }

    private var systemSlab: some View {
        Slab(rail: .info, title: "Resources", trailing: uptimeText) {
            if let sys = store.system {
                VStack(spacing: 12) {
                    if let cpu = sys.cpuUsage {
                        Meter(label: "CPU", value: cpu / 100, readout: Fmt.pct(cpu),
                              health: level(cpu, warn: HealthThresholds.cpuWarn, bad: HealthThresholds.cpuBad))
                    }
                    if let mem = sys.memUsage {
                        Meter(label: "Memory", value: mem / 100, readout: Fmt.pct(mem),
                              health: level(mem, warn: HealthThresholds.memWarn, bad: HealthThresholds.memBad))
                    }
                    if let disk = sys.diskUsage {
                        Meter(label: "Disk", value: disk / 100, readout: Fmt.pct(disk),
                              health: level(disk, warn: HealthThresholds.diskWarn, bad: HealthThresholds.diskBad))
                    }
                    if let swap = sys.swapUsage, swap > 0 {
                        Meter(label: "Swap", value: swap / 100, readout: Fmt.pct(swap),
                              health: level(swap, warn: HealthThresholds.swapWarn, bad: HealthThresholds.swapBad))
                    }
                    if let mbuf = sys.mbufUsage {
                        Meter(label: "mbuf", value: mbuf / 100, readout: Fmt.pct(mbuf),
                              health: level(mbuf, warn: HealthThresholds.mbufWarn, bad: HealthThresholds.mbufBad))
                    }
                    Hairline()
                    FieldRow(key: "Load average", value: sys.loadDescription)
                    if !sys.coreTemps.isEmpty {
                        FieldRow(key: "CPU", value: sys.coreTemps.map { String(format: "%d: %.1f °C", $0.core, $0.temp) }.joined(separator: " · "))
                        if let t = sys.temperature, let source = sys.temperatureSource {
                            let label = sys.temperatureLabel
                            FieldRow(key: label, value: String(format: "%.1f °C (%@)", t, source as NSString))
                        }
                    } else if let t = sys.temperature {
                        let label = sys.temperatureLabel
                        if let source = sys.temperatureSource {
                            FieldRow(key: label, value: String(format: "%.1f °C (%@)", t, source as NSString))
                        } else {
                            FieldRow(key: label, value: String(format: "%.1f °C", t))
                        }
                    } else {
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
                        HStack {
                            Text("States")
                                .scaledFont(13)
                                .foregroundStyle(theme.labelMuted)
                            Spacer()
                            Text("\(st.current ?? 0)")
                                .scaledFont(18, weight: .semibold, design: .monospaced)
                                .foregroundStyle(theme.label)
                            if !store.stateHistory.points.isEmpty {
                                StateTrendLine(values: store.stateHistory.points.map(\.value), max: st.effectiveMaximum ?? 10000)
                                    .frame(width: 80, height: 24)
                            }
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

    private var servicesSlab: some View {
        let down = store.overviewLayout.servicesDown
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

    private var gatewaysSlab: some View {
        if store.gatewayManager.gateways.isEmpty {
            return AnyView(Slab(rail: .idle) {
                Text(store.errors[.gateways] ?? "No gateway status returned.")
                    .scaledFont(13)
                    .foregroundStyle(theme.labelMuted)
            })
        } else {
            return AnyView(VStack(alignment: .leading, spacing: 8) {
                ForEach(store.gatewayManager.gateways, id: \.name) { gw in
                    GatewayRow(gateway: gw, gatewayMetrics: store.gatewayManager.gatewayMetrics)
                }
            })
        }
    }

    private var firewallSlab: some View {
        Slab(rail: .info, title: "Recent filter activity",
             trailing: "last \(store.firewallLog.count) lines") {
            if store.firewallLog.isEmpty {
                placeholder(.firewallLog)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 18) {
                        deltaCounter("Blocked", store.overviewLayout.blockedRecently, store.overviewLayout.blockedDelta, .bad)
                        deltaCounter("Rejected", store.overviewLayout.rejectedRecently, store.overviewLayout.rejectedDelta, .warn)
                        deltaCounter("Passed", store.overviewLayout.passedRecently, store.overviewLayout.passedDelta, .ok)
                        Spacer()
                    }
                    Hairline()
                    // Tappable, like the same rows on the Logs tab. A blocked
                    // line on the Overview is the one somebody most wants to
                    // open, and it was the one place they could not.
                    ForEach(store.firewallLog.prefix(4)) { line in
                        NavigationLink {
                            LogDetailView(line: line)
                        } label: {
                            LogRow(line: line, compact: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// The servers themselves: what is listening, on what, and how much has
    /// gone through it.
    ///
    /// The first version of this card was a count of peers and connections,
    /// which is the clients' question wearing the servers' title. A server
    /// section should answer "is this thing up and working" — name, state,
    /// port, and the traffic it has carried — and leave who is on it to the
    /// section about who is on it.
    ///
    /// RX and TX are summed from the connections for OpenVPN, because the
    /// server endpoint reports no totals of its own; WireGuard reports the
    /// tunnel's own counters. Both are since the daemon last started, not a
    /// rate, and are labelled as totals rather than left to be mistaken for
    /// throughput.
    private var vpnServersSlab: some View {
        Slab(rail: vpnServersHealth, title: "VPN servers", trailing: vpnServersTrailing) {
            if !hasVPNServers {
                placeholder(.openvpn)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(store.openvpnServers) { server in
                        // Not `statusLabel`. With no status field — which is
                        // what 26.07 returns — it falls back to "2 connected",
                        // and a count of clients is the clients' section's
                        // answer, not this one's. A server that appears in
                        // `status/openvpn/servers` is running, so that is what
                        // it says.
                        serverRow(name: server.name,
                                  health: server.status == nil ? .ok : server.health,
                                  status: server.status ?? "listening",
                                  port: server.port,
                                  rx: server.connections.compactMap(\.bytesReceived).reduce(0, +),
                                  tx: server.connections.compactMap(\.bytesSent).reduce(0, +))
                    }
                    ForEach(store.wireguardTunnels) { tunnel in
                        serverRow(name: tunnel.descr ?? tunnel.name,
                                  health: tunnel.health,
                                  status: tunnel.statusLabel,
                                  port: tunnel.listenPort,
                                  rx: tunnel.bytesReceived ?? 0,
                                  tx: tunnel.bytesSent ?? 0)
                    }
                    ForEach(store.ipsecSAs) { sa in
                        // IPsec reports no byte counters here and no listen
                        // port, so the row carries what it does have rather
                        // than padding the same columns with dashes.
                        HStack(alignment: .firstTextBaseline) {
                            Text(sa.connectionName)
                                .scaledFont(12, weight: .semibold)
                                .foregroundStyle(theme.label)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(sa.remoteHost ?? sa.state)
                                .scaledFont(11, design: .monospaced)
                                .foregroundStyle(sa.health.color(theme))
                        }
                    }
                }
            }
        }
    }

    private func serverRow(name: String, health: Health, status: String,
                           port: String?, rx: Double, tx: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(name)
                    .scaledFont(13, weight: .semibold)
                    .foregroundStyle(theme.label)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(status)
                    .scaledFont(11, design: .monospaced)
                    .foregroundStyle(health.color(theme))
            }
            HStack(spacing: 10) {
                if let port, !port.isEmpty {
                    metric("PORT", port)
                }
                metric("RX", Fmt.bytes(rx))
                metric("TX", Fmt.bytes(tx))
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .scaledFont(8, weight: .medium)
                .foregroundStyle(theme.labelFaint)
            Text(value)
                .scaledFont(11, design: .monospaced)
                .foregroundStyle(theme.labelMuted)
        }
    }

    /// Who is connected, across every server, in one list.
    ///
    /// This said "this firewall does not connect out to any VPN" and showed
    /// nothing, because it was listing OpenVPN *client instances* — the
    /// outbound tunnels this firewall dials. That is a real thing and a rare
    /// one, and it is not what somebody opening a section called VPN clients
    /// wants: they want the people currently on the VPN.
    ///
    /// So this is every OpenVPN connection and every WireGuard peer that has
    /// handshaken, named, with where they came from and what they have moved.
    private var vpnClientsSlab: some View {
        Slab(rail: vpnClientsHealth, title: "VPN clients", trailing: vpnClientsTrailing) {
            if connectedClients.isEmpty && liveWireGuardPeers.isEmpty {
                Text(hasVPNServers
                     ? "Nobody is connected right now."
                     : "No VPN is configured on this firewall.")
                    .scaledFont(12)
                    .foregroundStyle(theme.labelFaint)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(connectedClients) { client in
                        clientRow(name: client.commonName,
                                  where: client.virtualAddress ?? client.remoteHost,
                                  rx: client.bytesReceived,
                                  tx: client.bytesSent,
                                  health: .ok)
                    }
                    ForEach(liveWireGuardPeers) { peer in
                        clientRow(name: peer.descr ?? peer.shortKey,
                                  where: peer.allowedIPs.first ?? peer.tunnel,
                                  rx: peer.bytesReceived,
                                  tx: peer.bytesSent,
                                  health: peer.health)
                    }
                }
            }
        }
    }

    /// One line per client.
    ///
    /// Three lines each — name, endpoint, transfer, timestamp — turned four
    /// connected devices into most of a screen, and a dashboard card is a
    /// glance rather than a report. The endpoint and the connect time are on
    /// the VPN screen, which is a tap away and is where somebody looking for
    /// them is going anyway.
    ///
    /// What survives is what identifies the client and what says it is doing
    /// something: who, where it sits on the tunnel, and how much has moved.
    private func clientRow(name: String, where address: String?,
                           rx: Double?, tx: Double?, health: Health) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(health.color(theme))
                .frame(width: 6, height: 6)

            Text(name)
                .scaledFont(12, weight: .semibold)
                .foregroundStyle(theme.label)
                .lineLimit(1)
                .truncationMode(.middle)

            if let address, !address.isEmpty {
                Text(address)
                    .scaledFont(10, design: .monospaced)
                    .foregroundStyle(theme.labelFaint)
                    .lineLimit(1)
                    // Lower priority than the transfer figures: an address
                    // that truncates is still recognisable, a byte count that
                    // truncates is wrong.
                    .layoutPriority(-1)
            }

            Spacer(minLength: 4)

            Text("\(Fmt.bytes(rx ?? 0)) / \(Fmt.bytes(tx ?? 0))")
                .scaledFont(10, design: .monospaced)
                .foregroundStyle(theme.labelMuted)
                .lineLimit(1)
                .layoutPriority(1)
        }
    }

    /// Every OpenVPN connection on every server, busiest first.
    private var connectedClients: [OpenVPNConnection] {
        store.openvpnServers.flatMap(\.connections)
            .sorted { ($0.bytesReceived ?? 0) + ($0.bytesSent ?? 0)
                    > ($1.bytesReceived ?? 0) + ($1.bytesSent ?? 0) }
    }

    /// WireGuard peers that are connected now.
    ///
    /// Having ever handshaken was the wrong test. A laptop that closed its lid
    /// yesterday still has a handshake timestamp, so the card listed peers
    /// last seen eighteen hours and a day ago under a heading about who is
    /// connected.
    ///
    /// `health == .ok` is a handshake inside five minutes, which for WireGuard
    /// means the peer is up: it rehandshakes roughly every two minutes while
    /// traffic flows. Anything older is somewhere else now, and the VPN screen
    /// still lists it with its last-seen time.
    private var liveWireGuardPeers: [WireGuardPeer] {
        store.wireguardPeers.filter { $0.health == .ok }
    }

    private var hasVPNServers: Bool {
        !store.openvpnServers.isEmpty || !store.wireguardTunnels.isEmpty
            || !store.wireguardPeers.isEmpty || !store.ipsecSAs.isEmpty
    }

    /// Health per section rather than one figure for all of VPN.
    ///
    /// A combined health meant a down tunnel turned the whole card amber and a
    /// healthy server could not say so. Each section now answers for itself.
    private var vpnServersHealth: Health {
        guard hasVPNServers else { return .info }
        if store.wireguardTunnels.contains(where: { $0.health == .bad }) { return .bad }
        if store.ipsecSAs.contains(where: { $0.health == .bad }) { return .warn }
        let up = store.openvpnServers.count
            + store.wireguardTunnels.filter(\.isUp).count
            + store.ipsecSAs.filter { $0.health == .ok }.count
        return up > 0 ? .ok : .warn
    }

    /// Nobody connected is not a fault.
    ///
    /// A remote-access VPN with no one on it at four in the morning is working
    /// exactly as intended, and a card that goes amber for it teaches people
    /// to ignore the colour.
    private var vpnClientsHealth: Health {
        connectedClients.isEmpty && liveWireGuardPeers.isEmpty ? .info : .ok
    }

    private var vpnServersTrailing: String? {
        guard hasVPNServers else { return nil }
        let total = store.openvpnServers.count + store.wireguardTunnels.count + store.ipsecSAs.count
        return "\(total)"
    }

    private var vpnClientsTrailing: String? {
        let count = connectedClients.count + liveWireGuardPeers.count
        return count == 0 ? nil : "\(count)"
    }

    private var topTalkersSlab: some View {
        Slab(rail: .info, title: "Top talkers", trailing: "\(store.overviewLayout.topTalkers.count) device\(store.overviewLayout.topTalkers.count == 1 ? "" : "s")") {
            if store.overviewLayout.topTalkers.isEmpty {
                Text("No client data yet")
                    .scaledFont(12)
                    .foregroundStyle(theme.labelFaint)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(store.overviewLayout.topTalkers) { talker in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(talker.ip)
                                        .scaledFont(12, design: .monospaced)
                                    if let name = talker.hostname {
                                        Text(name)
                                            .scaledFont(11)
                                            .foregroundStyle(theme.labelMuted)
                                    }
                                }
                                Text(talker.mac)
                                    .scaledFont(10, design: .monospaced)
                                    .foregroundStyle(theme.labelFaint)
                            }
                            Spacer()
                            Text(talker.rankLabel)
                                .scaledFont(10)
                                .foregroundStyle(talker.sourceCount >= 3 ? theme.ok : theme.labelMuted)
                        }
                    }
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
    @Environment(\.themeManager) private var theme: ThemeManager
    let gateway: GatewayStatus
    let gatewayMetrics: GatewayMetricTracker

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

private struct SectionView: View {
    let section: OverviewSection
    let title: String
    @Binding var isEditing: Bool
    @Binding var visibleSections: [OverviewSection]
    @Binding var collapsedSections: Set<String>
    let registry: ServerRegistry
    let content: () -> AnyView
    @Environment(\.themeManager) private var theme: ThemeManager
    
    @Binding var draggedSection: OverviewSection?
    @Binding var sectionHeights: [OverviewSection: CGFloat]
    let currentIndex: Int

    @State private var isDragging = false
    @State private var isCollapsed = false

    /// Where the drag started, in the list.
    ///
    /// The rows reorder while the finger is still down, so `currentIndex`
    /// changes underneath the gesture. The origin is fixed at the start and
    /// every target is computed from it, which is what keeps a drag from
    /// fighting its own reordering.
    @State private var dragOrigin: Int?
    @State private var translation: CGFloat = 0

    /// How far the dragged card is from its slot.
    ///
    /// The card follows the finger; its slot has already moved to wherever the
    /// reordering put it, so the visible offset is the finger's travel minus
    /// the distance the slot itself has travelled. Without that subtraction
    /// the card runs away from the cursor by a row each time the list shifts.
    private var liveOffset: CGFloat {
        guard isDragging, let origin = dragOrigin else { return 0 }
        // The distance this card's slot has already travelled, in real
        // heights: the rows it passed are not all the same size, so counting
        // them and multiplying by an average put the card visibly off the
        // finger by the third row.
        return translation - travelled(from: origin, to: currentIndex)
    }

    /// The height of the rows between two positions, signed.
    private func travelled(from: Int, to: Int) -> CGFloat {
        guard from != to else { return 0 }
        let range = from < to ? (from + 1)...to : (to + 1)...from
        let distance = range.reduce(CGFloat.zero) { total, index in
            guard visibleSections.indices.contains(index) else { return total }
            return total + height(of: visibleSections[index])
        }
        return from < to ? distance : -distance
    }

    /// A measured height, or a middling default until the row has been laid
    /// out once.
    private func height(of section: OverviewSection) -> CGFloat {
        sectionHeights[section] ?? 80
    }

    /// Where a drag of this distance should land, measured in real rows.
    private func targetIndex(from origin: Int, translation: CGFloat) -> Int {
        var index = origin
        var remaining = translation

        if remaining > 0 {
            while index < visibleSections.count - 1 {
                let next = height(of: visibleSections[index + 1])
                    // Two thirds, not half.
                //
                // Half means a card swaps the instant it overlaps its
                // neighbour, so a small wobble near a boundary flips it back
                // and forth. The extra sixth is hysteresis: enough that a
                // deliberate move still feels immediate and a shaky hand does
                // not.
                guard remaining > next * 0.66 else { break }
                remaining -= next
                index += 1
            }
        } else {
            while index > 0 {
                let previous = height(of: visibleSections[index - 1])
                guard -remaining > previous * 0.66 else { break }
                remaining += previous
                index -= 1
            }
        }
        return index
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if dragOrigin == nil {
                    dragOrigin = currentIndex
                    isDragging = true
                    draggedSection = section
                }
                translation = value.translation.height

                guard let origin = dragOrigin else { return }

                // Walk the real rows rather than dividing by an average.
                //
                // A card swaps once it is more than halfway over its
                // neighbour, and "halfway" depends on how tall that neighbour
                // is — which is what made this feel jumpy with sections
                // ranging from a banner to a full system card.
                let target = targetIndex(from: origin, translation: translation)

                if target != currentIndex,
                   let from = visibleSections.firstIndex(of: section) {
                    // Reorder as the finger moves. Everything else animates
                    // into place because the ForEach re-renders with the new
                    // order — the cards move in relation to each other, which
                    // is the whole point of dragging one.
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                        var reordered = visibleSections
                        let item = reordered.remove(at: from)
                        reordered.insert(item, at: target)
                        visibleSections = reordered
                    }
                }
            }
            .onEnded { _ in
                // Saved once, at the end. Persisting on every swap would write
                // the profile a dozen times during one gesture.
                persistOrder(visibleSections)
                HapticFeedback.sectionReorder()

                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isDragging = false
                    translation = 0
                    dragOrigin = nil
                    draggedSection = nil
                }
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if isEditing {
                    Button {
                        hideSection()
                    } label: {
                        Image(systemName: "xmark")
                            .scaledFont(10, weight: .bold)
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(theme.bad, in: Circle())
                            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    }
                    .accessibilityHidden(true)
                    
                    Image(systemName: "line.3.horizontal")
                        .scaledFont(14)
                        .foregroundStyle(theme.labelFaint)
                        .symbolVariant(.fill)
                        .frame(width: 24)
                        .contentShape(Rectangle())
                }
                
                GroupHeading(text: title)
                Spacer()
                
                if !isEditing {
                    Button {
                        toggleCollapse()
                    } label: {
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .scaledFont(10)
                            .foregroundStyle(theme.labelFaint)
                            .symbolVariant(.fill.circle)
                            .frame(width: 20, height: 20)
                    }
                    .accessibilityLabel(isCollapsed ? "Expand \(title)" : "Collapse \(title)")
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isEditing)
            
            if isEditing {
                sectionMockup
            } else if isCollapsed {
                Text("Section collapsed")
                    .scaledFont(12)
                    .foregroundStyle(theme.labelFaint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                content()
            }
        }
        // Lifted as a whole, not just its title.
        //
        // These were on the header row, so dragging moved the heading and left
        // the card behind it — the offsets that used to nudge the neighbours
        // are gone because the list reorders underneath instead.
        // Reports its own height so the drag can walk real geometry. Read
        // during layout and written back once it changes, which is cheap: a
        // section's height only moves when its contents do.
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: SectionHeightKey.self,
                                       value: [section: proxy.size.height])
            }
        )
        .onPreferenceChange(SectionHeightKey.self) { heights in
            for (key, value) in heights where sectionHeights[key] != value {
                sectionHeights[key] = value
            }
        }
        .offset(y: liveOffset)
        .scaleEffect(isDragging ? 1.03 : 1.0)
        .opacity(isDragging ? 0.95 : 1.0)
        .shadow(color: isDragging ? theme.label.opacity(0.15) : .clear,
                radius: 12, y: isDragging ? 8 : 0)
        .zIndex(isDragging ? 1 : 0)
        .gesture(isEditing ? dragGesture : nil)
        .onAppear {
            if let active = registry.active, active.collapsedSections.contains(section.rawValue) {
                isCollapsed = true
            }
        }
    }
    
    private var sectionMockup: some View {
        Rectangle()
            .fill(theme.labelFaint.opacity(0.08))
            .frame(height: 1)
    }

    private func hideSection() {
        visibleSections.removeAll { $0 == section }
        guard let active = registry.active else { return }
        registry.setOverviewSectionVisibility(active, section, visible: false)
    }
    
    private func toggleCollapse() {
        isCollapsed.toggle()
        guard let active = registry.active else { return }
        registry.setOverviewSectionCollapsed(active, section, collapsed: isCollapsed)
    }
    
    /// Writes the arrangement back to the profile.
    ///
    /// Every path that reorders has to call this: the order is stored per
    /// firewall, and a rearrangement that lives only in view state is undone
    /// the next time the screen appears.
    private func persistOrder(_ sections: [OverviewSection]) {
        guard let active = registry.active else { return }
        registry.setOverviewSectionOrder(active, sections)
    }
}

extension View {
    @ViewBuilder
    func wobble(_ isEditing: Bool) -> some View {
        if isEditing {
            self
                .animation(.easeInOut(duration: 0.5).repeatCount(3, autoreverses: true), value: isEditing)
                .wobbleOffset()
        } else {
            self
        }
    }
}

private struct WobbleOffset: ViewModifier {
    @State private var offset = CGFloat.random(in: -1...1)
    
    func body(content: Content) -> some View {
        content.offset(x: offset, y: 0)
    }
}

private extension View {
    func wobbleOffset() -> some View {
        modifier(WobbleOffset())
    }
}

/// Collects each section's measured height.
///
/// A dictionary rather than a single value, because the rows report
/// independently and the drag needs all of them at once — it walks from one
/// row to another and has to know how tall each one it passes is.
struct SectionHeightKey: PreferenceKey {
    static var defaultValue: [OverviewSection: CGFloat] { [:] }

    static func reduce(value: inout [OverviewSection: CGFloat],
                       nextValue: () -> [OverviewSection: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}
