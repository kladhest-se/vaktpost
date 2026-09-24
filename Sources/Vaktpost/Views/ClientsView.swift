import SwiftUI

struct ClientsView: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", online = "Seen", staticOnly = "Static"
        var id: String { rawValue }
    }

    /// The two halves of the same question.
    ///
    /// "Which devices are on this network" and "which of them is using it" are
    /// asked in the same breath, and having the second one three taps away
    /// under More meant the answer to the first was usually where the looking
    /// stopped. Deliberately plain words: this is the screen somebody opens
    /// when the internet is slow, and a clever label is a thing to decode at
    /// the moment they least want to.
    enum Pane: String, CaseIterable, Identifiable {
        case devices = "Devices", traffic = "Traffic"
        var id: String { rawValue }
    }

    @State private var pane: Pane = .devices
    @State private var filter: Filter = .all
    @State private var query = ""

    private var rows: [NetworkClient] {
        var list = store.overviewLayout.clients
        switch filter {
        case .all: break
        case .online: list = list.filter { $0.seenInARP || $0.online == true }
        case .staticOnly: list = list.filter(\.isStatic)
        }
        guard !query.isEmpty else { return list }
        let q = query.lowercased()
        return list.filter { client in
            client.ip.contains(q)
                || client.mac.lowercased().contains(q)
                || client.name.lowercased().contains(q)
                || (client.hostname ?? "").lowercased().contains(q)
                // Every other name the firewall knows it by, not only the one
                // that won the title: a device shown as its DNS override is
                // still findable by the description on its static mapping.
                || client.knownNames.contains { $0.value.lowercased().contains(q) }
                // And the interface, so "vlan_100" narrows to one segment.
                || (store.interfaceLabel(for: client.interfaceName ?? "") ?? "")
                    .lowercased().contains(q)
        }
    }

    @State private var selection: String?

    var body: some View {
        Group {
            switch pane {
            case .devices: devicesPane
            // Full width rather than inside the split view: on iPad the
            // sampler would otherwise sit in a narrow list column with an
            // empty detail pane beside it saying "choose a device", which is
            // advice about a screen the person is not looking at.
            case .traffic: trafficPane
            }
        }
        .onChange(of: store.bindingID) { _, _ in selection = nil }
    }

    private var paneSwitcher: some View {
        Picker("", selection: $pane) {
            ForEach(Pane.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    private var trafficPane: some View {
        ScrollView {
            PageHeader(title: "Clients", subtitle: "Who is using the network")
            paneSwitcher
            HostTrafficPanel()
                .padding(.top, 6)
                .padding(.bottom, 28)
        }
        .background(theme.bg.ignoresSafeArea())
    }

    private var devicesPane: some View {
        MasterDetail(
            selection: $selection,
            emptyMessage: "Choose a device to see its leases, names and filter log.",
            list: { listColumn },
            detail: { id in
                // Looked up again rather than captured: a stored copy would
                // show the device as it was at the moment it was tapped, and
                // the list behind it refreshes every thirty seconds.
                if let client = store.overviewLayout.clients.first(where: { $0.id == id }) {
                    ClientDetailView(client: client).id(store.bindingID)
                } else {
                    Notice(symbol: "questionmark.circle",
                           title: "That device is no longer in the list")
                }
            }
        )
    }

    /// Whichever of the client sections failed, if any.
    private var clientFetchFailure: String? {
        for section: DashboardStore.Section in [.leases, .arp, .statics, .hostOverrides] {
            if let message = store.errors[section] { return message }
        }
        return nil
    }

    private var listColumn: some View {
        ScrollView {
            PageHeader(title: "Clients", subtitle: !store.overviewLayout.clients.isEmpty ? "\(store.overviewLayout.clients.count) devices" : nil)
            paneSwitcher
            VStack(spacing: 0) {
                FreshnessView(sections: [.leases, .arp, .statics, .hostOverrides, .aliases], showNames: true)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                // Below the header, in the content — `.searchable` would put
                // it in the navigation bar above the title and jump on focus,
                // which is what it did on the Firewall screen.
                InlineSearchField(text: $query, prompt: "Name, IP or MAC")
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                Picker("", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                LazyVStack(alignment: .leading, spacing: 10) {
                    // A failed fetch first, because it looks identical to an
                    // empty network otherwise. "No clients seen" is a
                    // reassuring sentence to show somebody whose firewall is
                    // not answering, and it sent this app's own batching bug
                    // unnoticed for a build.
                    if let failure = clientFetchFailure {
                        Notice(
                            symbol: "exclamationmark.triangle",
                            title: "Could not read the client tables",
                            detail: failure,
                            health: .warn
                        )
                    }
                    if rows.isEmpty && clientFetchFailure == nil {
                        Notice(
                            symbol: "person.2.slash",
                            title: query.isEmpty ? "No clients seen" : "No matches",
                            detail: query.isEmpty
                                ? "Clients are assembled from DHCP leases, the ARP table and static mappings. All three came back empty."
                                : nil
                        )
                    } else {
                        HStack {
                            Text("\(rows.count) shown · \(store.overviewLayout.clients.count) known")
                                .scaledFont(12, design: .monospaced)
                                .foregroundStyle(theme.labelFaint)
                            Spacer()
                        }
                        ForEach(rows) { client in
                            Button {
                                selection = client.id
                            } label: {
                                ClientRow(client: client)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .refreshable { await store.refreshManually() }
        }
        .background(theme.bg.ignoresSafeArea())
    }
}

/// One device in the list.
///
/// A copy of `ClientsView`'s body was pasted over this one — an edit that
/// replaced every `var body: some View {` in the file rather than the first —
/// so this struct carried a whole master-detail container and its real card
/// was left below under another name.
struct ClientRow: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore
    let client: NetworkClient

    /// Whether this row is the phone running the app.
    ///
    /// Matched on IP, not MAC. iOS has refused to give an app the Wi-Fi MAC
    /// since iOS 7 — every app reads `02:00:00:00:00:00` — and Private Wi-Fi
    /// Address means the address the firewall sees is generated per network
    /// anyway. The IP is what the system will actually tell us, and it is
    /// right for as long as the lease lasts.
    private var isThisDevice: Bool {
        LocalDevice.isThisDevice(client.ip)
    }

    var body: some View {
        Slab(rail: client.health) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    // This phone, marked.
                    //
                    // Picking your own device out of two hundred rows is worth
                    // a small icon — otherwise it means checking a MAC in
                    // Settings and scanning for it.
                    if isThisDevice {
                        Image(systemName: "iphone.gen3")
                            .scaledFont(12)
                            .foregroundStyle(theme.accentColor)
                            .accessibilityLabel("This device")
                    }
                    Text(client.name)
                        .scaledFont(15, weight: .semibold)
                        .foregroundStyle(theme.label)
                        .lineLimit(2)
                    Spacer()
                    StatusPill(text: client.presence, health: client.health)
                }
                HStack(spacing: 10) {
                    Text(client.ip)
                        .scaledFont(12, weight: .medium, design: .monospaced)
                        .foregroundStyle(theme.labelMuted)
                    Text(client.mac)
                        .scaledFont(11, design: .monospaced)
                        .foregroundStyle(theme.labelFaint)
                    Spacer()
                    if let iface = client.interfaceName, !iface.isEmpty {
                        Text(store.interfaceLabel(for: iface) ?? iface)
                            .scaledFont(10, weight: .semibold, design: .monospaced)
                            .foregroundStyle(theme.labelFaint)
                    }
                }
            }
        }
    }
}

struct ClientDetailView: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore
    let client: NetworkClient
    @State private var action = "All"
    @State private var query = ""
    @State private var refreshing = false
    @State private var vendor: MacVendorLookupResult?

    private var investigation: ClientInvestigation {
        ClientInvestigation(client: client, leases: store.leases, arp: store.arp,
                            mappings: store.staticMappings, overrides: store.hostOverrides,
                            aliases: store.aliases)
    }

    private var relatedLog: [LogLine] {
        let keys = Set(investigation.addresses.compactMap(ClientAddress.key))
        return store.firewallLog.filter { $0.involves(addresses: keys) }
    }

    private var filteredLog: [LogLine] {
        relatedLog.filter { line in
            let verdict = line.action ?? line.filterFields?.action
            let matchesAction = action == "All" || (action == "Allowed" ? verdict == "pass" :
                verdict == "block" || verdict == "reject")
            return matchesAction && (query.isEmpty || line.text.localizedCaseInsensitiveContains(query))
        }
    }

    private func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        await store.refreshClientInvestigation()
    }

    var body: some View {
        ScrollView {
            PageHeader(title: "Client investigation", subtitle: client.name)
            VStack(alignment: .leading, spacing: 14) {
                FreshnessView(sections: [.leases, .arp, .statics, .hostOverrides, .aliases], showNames: true)
                Slab(rail: client.health, title: "Identity and names") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(client.name).scaledFont(18, weight: .bold)
                            Spacer()
                            StatusPill(text: client.presence, health: client.health)
                        }
                        FieldRow(key: "MAC", value: client.mac)
                        vendorFields
                        FieldRow(key: "Known from", value: client.sourceSummary, mono: false)
                        ForEach(investigation.names, id: \.self) { name in
                            Text(name).scaledFont(12)
                        }
                    }
                    .textSelection(.enabled)
                }
                Slab(rail: .info, title: "Associated addresses") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(investigation.addresses, id: \.self) { ip in
                            FieldRow(key: LocalDevice.isThisDevice(ip) ? "This device" : "Address", value: ip)
                        }
                        Text("Addresses come from the fetched ARP, DHCP and static mapping tables. "
                            + "Lease history may include addresses that have since been reassigned.")
                            .scaledFont(12).foregroundStyle(theme.labelMuted)
                    }.textSelection(.enabled)
                }
                // Every other card on this screen reads from data the refresh
                // already fetched. This one asks the firewall to measure
                // something, so it is a button rather than a value.
                ClientTrafficCard(client: client, addresses: investigation.addresses)
                // Straight through to everything that references this device,
                // with the address already in the box.
                NavigationLink {
                    InvestigateView(initialQuery: client.ip)
                } label: {
                    Slab(rail: .info) {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .scaledFont(14)
                                .foregroundStyle(theme.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("What references this device")
                                    .scaledFont(13, weight: .semibold)
                                    .foregroundStyle(theme.label)
                                Text("Aliases, firewall rules, port forwards, VPN and DNSBL")
                                    .scaledFont(11)
                                    .foregroundStyle(theme.labelFaint)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .scaledFont(11, weight: .semibold)
                                .foregroundStyle(theme.labelFaint)
                        }
                    }
                }
                .buttonStyle(.plain)
                records
                GroupHeading(text: "Matching firewall log")
                FreshnessView(sections: [.firewallLog], showNames: true)
                Text("\(relatedLog.count) matching entries in \(store.firewallLog.count) fetched. "
                    + "These match address endpoints; they do not prove which device held an address at the time. "
                    + "Increase the log limit in Settings to look further back.")
                    .scaledFont(12).foregroundStyle(theme.labelMuted)
                Picker("Log action", selection: $action) {
                    ForEach(["All", "Allowed", "Blocked"], id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.segmented)
                InlineSearchField(text: $query, prompt: "Search matching log entries")
                if filteredLog.isEmpty {
                    Notice(symbol: "doc.text.magnifyingglass", title: "No matching entries in the fetched log")
                }
                LazyVStack(spacing: 10) {
                    // The same rows as the Logs tab, and the same detail
                    // behind them. A matching line is usually the start of
                    // "why was that blocked", which the entry answers and a
                    // row cannot.
                    ForEach(filteredLog) { line in
                        NavigationLink {
                            LogDetailView(line: line)
                        } label: {
                            LogRow(line: line)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens this log entry")
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationTitle(client.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: client.id) {
            vendor = nil
            let result = await MacVendorDatabase.shared.lookup(mac: client.mac)
            guard !Task.isCancelled else { return }
            vendor = result
        }
        .refreshable { await refresh() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }.disabled(refreshing).accessibilityLabel("Refresh client investigation")
            }
        }
    }

    @ViewBuilder
    private var vendorFields: some View {
        switch vendor {
        case nil:
            FieldRow(key: "Manufacturer", value: "Looking up…", mono: false)
        case .found(let name, let prefix, let registry):
            FieldRow(key: "Manufacturer", value: name, mono: false)
            FieldRow(key: "IEEE assignment", value: "\(registry) · \(prefix)")
            FieldRow(key: "Lookup", value: "Offline IEEE registry", mono: false)
        case .locallyAdministered:
            FieldRow(key: "Manufacturer", value: "Local or private MAC", mono: false)
            Text("This address may be randomized or assigned locally, so its prefix does not reliably identify the hardware vendor.")
                .scaledFont(11)
                .foregroundStyle(theme.labelFaint)
        case .multicast:
            FieldRow(key: "Manufacturer", value: "Multicast address", mono: false)
        case .unknown:
            FieldRow(key: "Manufacturer", value: "Not found in bundled IEEE registry", mono: false)
        case .invalid:
            FieldRow(key: "Manufacturer", value: "Invalid or unavailable MAC", mono: false)
        case .unavailable:
            FieldRow(key: "Manufacturer", value: "Offline registry unavailable", mono: false)
        }
    }

    private var records: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupHeading(text: "Lease and neighbor evidence")
            ForEach(Array(investigation.leases.enumerated()), id: \.offset) { _, lease in
                Slab(rail: .info, title: "DHCP lease") {
                    VStack(alignment: .leading, spacing: 6) {
                        FieldRow(key: "Address", value: lease.ip)
                        FieldRow(key: "State", value: lease.state)
                        FieldRow(key: "Interface", value: store.interfaceLabel(for: lease.interfaceName ?? "") ?? lease.interfaceName ?? "—")
                        FieldRow(key: "Starts", value: lease.starts ?? "—")
                        FieldRow(key: "Expires", value: lease.ends ?? "—")
                    }
                }
            }
            ForEach(Array(investigation.neighbors.enumerated()), id: \.offset) { _, entry in
                Slab(rail: .info, title: "ARP observation") {
                    VStack(alignment: .leading, spacing: 6) {
                        FieldRow(key: "Address", value: entry.ip)
                        FieldRow(key: "Interface", value: store.interfaceLabel(for: entry.interfaceName ?? "") ?? entry.interfaceName ?? "—")
                        FieldRow(key: "Expires in", value: entry.expiryDescription ?? "—")
                    }
                }
            }
            ForEach(Array(investigation.mappings.enumerated()), id: \.offset) { _, mapping in
                Slab(rail: .info, title: "Static mapping") {
                    VStack(alignment: .leading, spacing: 6) {
                        FieldRow(key: "Address", value: mapping.ip)
                        FieldRow(key: "Description", value: mapping.descr ?? "—", mono: false)
                        FieldRow(key: "Interface", value: store.interfaceLabel(for: mapping.interfaceName ?? "") ?? mapping.interfaceName ?? "—")
                    }
                }
            }
        }.textSelection(.enabled)
    }
}
