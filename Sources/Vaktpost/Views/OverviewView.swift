import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var store: DashboardStore
    @EnvironmentObject private var registry: ServerRegistry

    @State private var visibleSections: [OverviewSection] = []
    @State private var draggedSection: OverviewSection?
    @State private var draggingOffset: CGFloat = 0
    @State private var estimatedSectionHeight: CGFloat = 80

    var isEditingBinding: Binding<Bool> {
        Binding(
            get: { self.store.isOverviewEditing },
            set: { self.store.isOverviewEditing = $0 }
        )
    }

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

                        if store.criticalAlertCount > 0 {
                            alertsTeaser
                                .wobble(isEditingBinding.wrappedValue)
                        }

                        ForEach(Array(visibleSections.enumerated()), id: \.element.self) { index, section in
                            SectionView(
                                section: section,
                                title: section.displayName,
                                isEditing: isEditingBinding,
                                visibleSections: $visibleSections,
                                registry: registry,
                                content: { sectionContentView(section) },
                                draggedSection: $draggedSection,
                                draggingOffset: $draggingOffset,
                                estimatedSectionHeight: estimatedSectionHeight,
                                currentIndex: index
                            )
                        }

                        if isEditingBinding.wrappedValue {
                            hiddenSectionsPicker
                        }
                        
                        if visibleSections.isEmpty && !isEditingBinding.wrappedValue {
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
        }
    }

    private var longPressGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .onEnded { _ in
                isEditingBinding.wrappedValue.toggle()
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
        visibleSections = OverviewSection.allCases.filter { active.overviewVisibleSections.contains($0.rawValue) }
    }
    
    @ViewBuilder
    private var hiddenSectionsPicker: some View {
        let hidden = OverviewSection.allCases.filter { !visibleSections.contains($0) }
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
    }
    
    private func addSection(_ section: OverviewSection) {
        guard let active = registry.active else { return }
        registry.setOverviewSectionVisibility(active, section, visible: true)
    }

    @ViewBuilder
    private func sectionContentView(_ section: OverviewSection) -> AnyView {
        switch section {
        case .status:
            return AnyView(statusSlab)
        case .interfaces:
            return AnyView(interfacesSlab)
        case .system:
            return AnyView(systemSlab)
        case .gateways:
            return AnyView(gatewaysSlab)
        case .services:
            return AnyView(servicesSlab)
        case .firewall:
            return AnyView(firewallSlab)
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

    private var statusSlab: some View {
        Slab(rail: store.overallHealth) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Overall")
                        .scaledFont(11, weight: .semibold)
                        .foregroundStyle(theme.labelFaint)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(store.overallHealth.color(theme))
                            .frame(width: 8, height: 8)
                        Text(store.overallHealth.name.uppercased())
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
                    Text("\(store.interfacesUp) of \(store.interfaces.count)")
                        .scaledFont(14, weight: .medium)
                        .foregroundStyle(theme.label)
                }
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

    private var gatewaysSlab: some View {
        if store.gateways.isEmpty {
            return AnyView(Slab(rail: .idle) {
                Text(store.errors[.gateways] ?? "No gateway status returned.")
                    .scaledFont(13)
                    .foregroundStyle(theme.labelMuted)
            })
        } else {
            return AnyView(VStack(alignment: .leading, spacing: 8) {
                ForEach(store.gateways, id: \.name) { gw in
                    GatewayRow(gateway: gw, gatewayMetrics: store.gatewayMetrics)
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

private struct SectionView: View {
    let section: OverviewSection
    let title: String
    @Binding var isEditing: Bool
    @Binding var visibleSections: [OverviewSection]
    let registry: ServerRegistry
    let content: () -> AnyView
    @EnvironmentObject private var theme: ThemeManager
    
    @Binding var draggedSection: OverviewSection?
    @Binding var draggingOffset: CGFloat
    let estimatedSectionHeight: CGFloat
    let currentIndex: Int

    @GestureState private var gestureOffset: CGFloat = 0
    @State private var isDragging = false
    
    private var sectionOffset: CGFloat {
        guard let dragged = draggedSection,
              dragged != section else {
            return 0
        }
        return 0
    }

    @State private var dropTargetIndex: Int?
    @State private var isAnimating = false
    @State private var dragDistance: CGFloat = 0

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                isDragging = true
                draggedSection = section
                dragDistance = value.translation.height
                
                let dragSteps = Int(dragDistance / estimatedSectionHeight)
                dropTargetIndex = max(0, min(visibleSections.count - 1, currentIndex + dragSteps))
            }
            .onEnded { value in
                isDragging = false
                dragDistance = 0
                
                let dragSteps = Int(value.translation.height / estimatedSectionHeight)
                let finalIndex = max(0, min(visibleSections.count - 1, currentIndex + dragSteps))
                
                if abs(value.translation.height) > 20, finalIndex != currentIndex {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        var newSections = visibleSections
                        let fromIndex = newSections.firstIndex(of: section)!
                        let item = newSections.remove(at: fromIndex)
                        let toIndex = finalIndex > fromIndex ? finalIndex - 1 : finalIndex
                        newSections.insert(item, at: toIndex)
                        visibleSections = newSections
                    }
                }
                
                dropTargetIndex = nil
                draggedSection = nil
            }
    }

    private var dropIndicatorOffset: CGFloat {
        guard let target = dropTargetIndex else {
            return 0
        }
        
        let dragged = draggedSection
        let draggedIndex = dragged.map { visibleSections.firstIndex(of: $0) } ?? .none
        
        if let draggedIndex = draggedIndex, target > currentIndex {
            // Dragging down - sections between current and target move up
            if currentIndex > draggedIndex && currentIndex <= target {
                return -estimatedSectionHeight
            }
        } else if let draggedIndex = draggedIndex, target < currentIndex {
            // Dragging up - sections between target and current move down
            if currentIndex < draggedIndex && currentIndex >= target {
                return estimatedSectionHeight
            }
        }
        
        return 0
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
                            .background(Color.red, in: Circle())
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
            }
            .animation(.easeInOut(duration: 0.2), value: isEditing)
            .offset(y: section == draggedSection ? gestureOffset + dragDistance : dropIndicatorOffset)
            .scaleEffect(section == draggedSection ? 1.03 : 1.0)
            .opacity(section == draggedSection ? 0.95 : 1.0)
            .shadow(color: section == draggedSection ? .black.opacity(0.2) : .clear, radius: 12, y: section == draggedSection ? 8 : 0)
            
            if isEditing {
                sectionMockup
            } else {
                content()
            }
        }
        .gesture(isEditing ? dragGesture : nil)
    }
    
    private var sectionMockup: some View {
        Rectangle()
            .fill(theme.labelFaint.opacity(0.08))
            .frame(height: 1)
    }

    private func hideSection() {
        guard let active = registry.active else { return }
        registry.setOverviewSectionVisibility(active, section, visible: false)
    }
    
    private func moveSectionUp() {
        guard let currentIndex = visibleSections.firstIndex(of: section),
              currentIndex > 0 else { return }
        var newSections = visibleSections
        newSections.swapAt(currentIndex, currentIndex - 1)
        visibleSections = newSections
    }
    
    private func moveSectionDown() {
        guard let currentIndex = visibleSections.firstIndex(of: section),
              currentIndex < visibleSections.count - 1 else { return }
        var newSections = visibleSections
        newSections.swapAt(currentIndex, currentIndex + 1)
        visibleSections = newSections
    }
}

extension View {
    @ViewBuilder
    func `if`<Content>(_ condition: Bool, transform: (Self) -> Content) -> some View where Content: View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

extension View {
    @ViewBuilder
    func wobble(_ isEditing: Bool) -> some View {
        if isEditing {
            self.animation(.easeInOut(duration: 0.5).repeatCount(3, autoreverses: true), value: isEditing)
                .offset(x: CGFloat.random(in: -1...1), y: 0)
        } else {
            self
        }
    }
}
