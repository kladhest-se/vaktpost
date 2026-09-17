import SwiftUI

struct NetworkView: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore

    @State private var selectedTab = 0
    @State private var interfaceFilter: InterfaceFilter = .all
    @State private var showQuickBlock = false
    @State private var showReloadConfirm = false
    @State private var quickBlockInterface: InterfaceStat?
    @State private var showWriteError = false
    @State private var writeError: WriteError?
    // Interfaces only — gateways have no detail view to select into.
    @State private var selection: String?

    enum InterfaceFilter: String, CaseIterable, Identifiable {
        case all = "All", up = "Up", down = "Down"
        var id: String { rawValue }
    }

    var body: some View {
        Group {
            if selectedTab == 0 {
                // A split view on iPad: comparing two interfaces' throughput
                // side by side is exactly the kind of thing this screen is
                // for, and it was previously the same push-and-lose-the-list
                // navigation as a phone regardless of how much width was
                // available.
                MasterDetail(
                    selection: $selection,
                    emptyMessage: "Choose an interface to see its throughput, history and client traffic.",
                    list: { interfacesColumn },
                    detail: { id in
                        // Looked up again rather than captured: a stored copy
                        // would show the interface as it was at the moment it
                        // was tapped, and this list refreshes on every cycle.
                        if let iface = store.interfaces.first(where: { $0.id == id }) {
                            InterfaceDetailView(iface: iface).id(store.bindingID)
                        } else {
                            Notice(symbol: "questionmark.circle",
                                   title: "That interface is no longer in the list")
                        }
                    }
                )
            } else {
                // Full width rather than inside the split view: gateways have
                // no detail screen to select into, so a list column beside an
                // empty "choose something" pane would be advice about a
                // screen that does not exist.
                ScrollView {
                    PageHeader(title: "Network", subtitle: "\(store.gatewayManager.gateways.count) gateways")
                    tabPicker
                    gatewaysContent
                }
                .readableWidth()
                .refreshable { await store.refreshManually() }
                .background(theme.bg.ignoresSafeArea())
            }
        }
        .navigationTitle("Network")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if selectedTab == 0 && store.interfaces.count > 1 {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink {
                        InterfaceComparisonView()
                    } label: {
                        Image(systemName: "arrow.left.arrow.right")
                    }
                }
            }
        }
        .sheet(isPresented: $showQuickBlock) {
            NavigationStack {
                QuickBlockView(showsDoneButton: true)
            }
        }
        .confirmationSheet(
            isPresented: $showReloadConfirm,
            title: "Reload firewall rules",
            message: store.writeCoordinator.preview(for: .reloadFirewall),
            destructive: true,
            destructiveLabel: "Reload",
            confirmLabel: "Cancel",
            onConfirm: { await reloadFirewall() },
            onCancel: {}
        )
        .writeErrorAlert(isErrorPresented: $showWriteError, error: $writeError)
        // A selected interface belongs to the firewall it was selected on.
        // Left alone across a switch, the detail pane would keep showing
        // one firewall's interface — by name only, since the id is a
        // "device-name" pair another firewall could coincidentally share —
        // while the list beside it had already moved to the next one.
        .onChange(of: store.bindingID) { _, _ in selection = nil }
    }

    private var tabPicker: some View {
        Picker("Network", selection: $selectedTab) {
            Text("Interfaces").tag(0)
            Text("Gateways").tag(1)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Interfaces

    private var filteredInterfaces: [InterfaceStat] {
        switch interfaceFilter {
        case .all: return store.interfaces
        case .up: return store.interfaces.filter { $0.status == "up" }
        case .down: return store.interfaces.filter { $0.status != "up" }
        }
    }

    private var interfacesColumn: some View {
        ScrollView {
            PageHeader(title: "Network", subtitle: "\(store.interfaces.count) interfaces")
            tabPicker
            Picker("Status", selection: $interfaceFilter) {
                ForEach(InterfaceFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 4)

            interfacesContent
        }
        .refreshable { await store.refreshManually() }
        .background(theme.bg.ignoresSafeArea())
    }

    private var interfacesContent: some View {
        VStack(spacing: 12) {
            FreshnessView(sections: [.interfaces])
            
            if let err = store.errors[.interfaces] {
                Notice(
                    symbol: "exclamationmark.triangle",
                    title: "Could not read interface status",
                    detail: err,
                    health: .warn
                )
            }
            
            let interfaces = filteredInterfaces
            if interfaces.isEmpty && store.errors[.interfaces] == nil {
                Notice(
                    symbol: "point.3.connected.trianglepath.dotted",
                    title: interfaceFilter == .all ? "No interfaces reported" : "No \(interfaceFilter.rawValue) interfaces",
                    detail: interfaceFilter == .all
                        ? "The firewall did not report any interfaces."
                        : nil
                )
            } else {
                ForEach(interfaces) { iface in
                    InterfaceCard(iface: iface, selection: $selection)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 28)
    }

    // MARK: Gateways

    private var gatewaysContent: some View {
        VStack(spacing: 12) {
            FreshnessView(sections: [.gateways])
            
            if store.gatewayManager.gateways.isEmpty {
                if let err = store.errors[.gateways] {
                    Notice(
                        symbol: "exclamationmark.triangle",
                        title: "Could not read gateway status",
                        detail: err,
                        health: .warn
                    )
                } else {
                    Notice(
                        symbol: "routing.compose",
                        title: "No gateways reported",
                        detail: "The firewall did not report any gateways."
                    )
                }
            } else {
                ForEach(store.gatewayManager.gateways, id: \.name) { gw in
                    GatewayCard(gateway: gw, gatewayMetrics: store.gatewayManager.gatewayMetrics)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 28)
    }

    // MARK: - Actions

    private func reloadFirewall() async {
        do {
            _ = try await store.writeCoordinator.execute(.reloadFirewall)
            await store.refresh()
        } catch {
            writeError = WriteError.from(error, operation: .reloadFirewall)
            showWriteError = true
        }
    }
}

/// One interface, as a card.
struct InterfaceCard: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore
    @State private var showQuickBlock = false
    let iface: InterfaceStat
    @Binding var selection: String?

    var body: some View {
        Button {
            selection = iface.id
        } label: {
        Slab(rail: iface.health) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Button {
                        store.toggleFavourite(iface)
                    } label: {
                        Image(systemName: store.isFavourite(iface) ? "star.fill" : "star")
                            .scaledFont(12)
                            .foregroundStyle(store.isFavourite(iface)
                                             ? theme.accentColor : theme.labelFaint)
                    }
                    .buttonStyle(.plain)
                    
                    Text(iface.name)
                        .scaledFont(15, weight: .semibold)
                        .foregroundStyle(theme.label)
                        .lineLimit(2)
                    Spacer()
                    // Only when errors are moving. A total since boot is not
                    // worth a badge on a list — it would sit there for the
                    // life of the link and be learned as furniture.
                    if store.interfaceErrors.change(for: iface)?.isRising == true {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .scaledFont(11)
                            .foregroundStyle(theme.warn)
                            .accessibilityLabel("Link errors rising")
                    }
                    StatusPill(text: iface.status, health: iface.health)
                }
                
                HStack(spacing: 10) {
                    Text(iface.addressLine)
                        .scaledFont(12, weight: .medium, design: .monospaced)
                        .foregroundStyle(theme.labelMuted)
                    Spacer()
                    if let media = iface.media, !media.isEmpty {
                        Text(media)
                            .scaledFont(10, weight: .semibold, design: .monospaced)
                            .foregroundStyle(theme.labelFaint)
                    }
                }
                
                if let inBytes = iface.inBytes, let outBytes = iface.outBytes {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("IN")
                                .scaledFont(10, weight: .bold, design: .rounded)
                                .tracking(0.8)
                                .foregroundStyle(theme.labelFaint)
                            Text(Fmt.bytes(inBytes))
                                .scaledFont(13, weight: .medium, design: .monospaced)
                                .foregroundStyle(theme.ok)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("OUT")
                                .scaledFont(10, weight: .bold, design: .rounded)
                                .tracking(0.8)
                                .foregroundStyle(theme.labelFaint)
                            Text(Fmt.bytes(outBytes))
                                .scaledFont(13, weight: .medium, design: .monospaced)
                                .foregroundStyle(theme.info)
                        }
                    }
                }
                
                ThroughputChart(
                    tracker: store.throughput,
                    store: store,
                    device: iface.seriesKey,
                    height: 44
                )

                Divider()
                    .padding(.vertical, 6)

                HStack(spacing: 8) {
                    Button {
                        showQuickBlock = true
                    } label: {
                        Label("Block", systemImage: "xmark.circle.fill")
                            .scaledFont(11, weight: .medium)
                    }
                    .buttonStyle(.plain)
                    .disabled(!store.canAdminister)
                    .opacity(store.canAdminister ? 1 : 0.45)

                    Spacer()

                    // The whole card is now the navigation target (wrapped
                    // above), so this is a plain trailing indicator, not its
                    // own link -- a second, nested NavigationLink to the same
                    // destination would be redundant and re-narrow the tap
                    // target back down to just this label.
                    Label("Details", systemImage: "chevron.right")
                        .scaledFont(11, weight: .medium)
                }
                .foregroundStyle(theme.labelMuted)
            }
        }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showQuickBlock) {
            NavigationStack {
                QuickBlockView(showsDoneButton: true)
            }
        }
    }
}

/// One gateway, as a card.
struct GatewayCard: View {
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
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(gateway.name)
                        .scaledFont(15, weight: .semibold)
                        .foregroundStyle(theme.label)
                        .lineLimit(2)
                    Spacer()
                    StatusPill(text: gateway.status, health: gateway.health)
                }
                
                Text(gateway.readout)
                    .scaledFont(12, design: .monospaced)
                    .foregroundStyle(theme.labelMuted)
                
                if let ip = gateway.monitorIP, !ip.isEmpty {
                    Text("monitor \(ip)")
                        .scaledFont(11, design: .monospaced)
                        .foregroundStyle(theme.labelFaint)
                }
                
                GatewayTrend(
                    delayPoints: delayPoints,
                    lossPoints: lossPoints,
                    latestDelay: gateway.delayMS,
                    latestLoss: gateway.lossPercent
                )
            }
        }
    }
}
