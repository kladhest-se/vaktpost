import SwiftUI

struct ClientsView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var store: DashboardStore

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", online = "Seen", staticOnly = "Static"
        var id: String { rawValue }
    }

    @State private var filter: Filter = .all
    @State private var query = ""

    private var rows: [NetworkClient] {
        var list = store.clients
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
        MasterDetail(
            selection: $selection,
            emptyMessage: "Choose a device to see its leases, names and filter log.",
            list: { listColumn },
            detail: { id in
                // Looked up again rather than captured: a stored copy would
                // show the device as it was at the moment it was tapped, and
                // the list behind it refreshes every thirty seconds.
                if let client = store.clients.first(where: { $0.id == id }) {
                    ClientDetailView(client: client)
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
            PageHeader(title: "Clients", subtitle: store.clients.count > 0 ? "\(store.clients.count) devices" : nil)
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
                    } else if rows.isEmpty {
                        Notice(
                            symbol: "person.2.slash",
                            title: query.isEmpty ? "No clients seen" : "No matches",
                            detail: query.isEmpty
                                ? "Clients are assembled from DHCP leases, the ARP table and static mappings. All three came back empty."
                                : nil
                        )
                    } else {
                        HStack {
                            Text("\(rows.count) shown · \(store.clients.count) known")
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
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var store: DashboardStore
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
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var store: DashboardStore
    let client: NetworkClient

    private var relatedLog: [LogLine] { store.logLines(matching: client.ip) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Slab(rail: client.health, title: "Identity") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(client.name)
                                .scaledFont(18, weight: .bold)
                                .foregroundStyle(theme.label)
                            Spacer()
                            StatusPill(text: client.presence, health: client.health)
                        }
                        Text("from \(client.nameSource)")
                            .scaledFont(11)
                            .foregroundStyle(theme.labelFaint)
                        Hairline()
                        FieldRow(key: "IP", value: client.ip)
                        FieldRow(key: "MAC", value: client.mac)
                        if LocalDevice.isThisDevice(client.ip) {
                            // Said in words as well as the icon: an icon alone
                            // leaves somebody guessing what it claims.
                            HStack(spacing: 6) {
                                Image(systemName: "iphone.gen3")
                                    .scaledFont(11)
                                Text("This is the device you are using")
                                    .scaledFont(11)
                            }
                            .foregroundStyle(theme.accentColor)
                        }

                        // Every name this device has, not only the one that
                        // won the title. The firewall alias is usually the one
                        // to search a rule for, even where the DNS name reads
                        // better at the top of a card.
                        ForEach(client.knownNames, id: \.value) { entry in
                            FieldRow(key: entry.source, value: entry.value,
                                     mono: entry.source != "Description")
                        }
                        if let iface = client.interfaceName, !iface.isEmpty {
                            FieldRow(key: "Interface", value: store.interfaceLabel(for: iface) ?? iface)
                        }
                        FieldRow(key: "Known from", value: client.sourceSummary, mono: false)
                    }
                }

                if client.seenInLease || client.leaseEnds != nil {
                    Slab(rail: .info, title: "DHCP") {
                        VStack(alignment: .leading, spacing: 6) {
                            FieldRow(key: "Assignment", value: client.isStatic ? "static mapping" : "dynamic lease", mono: false)
                            if let state = client.leaseState, !state.isEmpty {
                                FieldRow(key: "Lease state", value: state)
                            }
                            if let ends = client.leaseEnds, !ends.isEmpty {
                                FieldRow(key: "Expires", value: ends)
                            }
                        }
                    }
                }

                GroupHeading(text: "Filter log")
                if relatedLog.isEmpty {
                    Slab(rail: .idle) {
                        Text("No lines mentioning \(client.ip) in the last \(store.firewallLog.count) fetched. Widen the log limit in Settings to look further back.")
                            .scaledFont(12)
                            .foregroundStyle(theme.labelMuted)
                    }
                } else {
                    ForEach(relatedLog.prefix(50)) { LogRow(line: $0) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationTitle(client.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
