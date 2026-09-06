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
        return list.filter {
            $0.ip.contains(q) || $0.mac.contains(q)
                || $0.name.lowercased().contains(q)
                || ($0.hostname ?? "").lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $filter) {
                ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if rows.isEmpty {
                        Notice(
                            symbol: "person.2.slash",
                            title: query.isEmpty ? "No clients seen" : "No matches",
                            detail: query.isEmpty
                                ? "Clients are assembled from DHCP leases, the ARP table and static mappings. If all three are empty, check the key's privileges."
                                : nil
                        )
                    } else {
                        HStack {
                            Text("\(rows.count) shown · \(store.clients.count) known")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(theme.labelFaint)
                            Spacer()
                        }
                        ForEach(rows) { client in
                            NavigationLink {
                                ClientDetailView(client: client)
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
            .refreshable { await store.refresh() }
        }
        .background(theme.bg.ignoresSafeArea())
        .searchable(text: $query, prompt: "Name, IP or MAC")
        .navigationTitle("Clients")
    }
}

struct ClientRow: View {
    @EnvironmentObject private var theme: ThemeManager
    let client: NetworkClient

    var body: some View {
        Slab(rail: client.health) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(client.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.label)
                        .lineLimit(1)
                    Spacer()
                    StatusPill(text: client.presence, health: client.health)
                }
                HStack(spacing: 10) {
                    Text(client.ip)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.labelMuted)
                    Text(client.mac)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme.labelFaint)
                    Spacer()
                    if let iface = client.interfaceName, !iface.isEmpty {
                        Text(iface)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
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
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(theme.label)
                            Spacer()
                            StatusPill(text: client.presence, health: client.health)
                        }
                        Hairline()
                        FieldRow(key: "IP", value: client.ip)
                        FieldRow(key: "MAC", value: client.mac)
                        if let h = client.hostname, !h.isEmpty {
                            FieldRow(key: "Hostname", value: h)
                        }
                        if let d = client.descr, !d.isEmpty {
                            FieldRow(key: "Description", value: d, mono: false)
                        }
                        if let iface = client.interfaceName, !iface.isEmpty {
                            FieldRow(key: "Interface", value: iface)
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
                            .font(.system(size: 12))
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
