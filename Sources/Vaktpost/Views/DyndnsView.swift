import SwiftUI

/// Dynamic DNS.
///
/// Its own screen because a firewall that hosts anything tends to have twenty
/// or more entries, and buried at the bottom of System they were a wall of
/// near-identical cards that pushed everything else off the page.
///
/// The reason this is worth a screen at all: pfSense keeps no update history.
/// A dyndns client that quietly stopped working looks exactly like one with
/// nothing to do — the only evidence is the cached address drifting away from
/// the address the interface actually has, which is the comparison this makes.
struct DyndnsView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var store: DashboardStore

    @State private var query = ""
    @State private var filter: Filter = .all

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", stale = "Stale", disabled = "Disabled"
        var id: String { rawValue }
    }

    private var entries: [DyndnsEntry] {
        var list = store.dyndns
        switch filter {
        case .all: break
        case .stale:
            let staleIDs = Set(store.staleDyndns.map(\.id))
            list = list.filter { staleIDs.contains($0.id) }
        case .disabled:
            list = list.filter { !$0.enabled }
        }
        guard !query.isEmpty else { return list }
        let q = query.lowercased()
        return list.filter {
            $0.host.lowercased().contains(q)
                || ($0.descr ?? "").lowercased().contains(q)
                || ($0.cachedAddress ?? "").contains(q)
                || ($0.type ?? "").lowercased().contains(q)
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
                    if let err = store.errors[.dyndns] {
                        Notice(symbol: "exclamationmark.triangle",
                               title: "Dynamic DNS unavailable", detail: err, health: .warn)
                    } else if store.dyndns.isEmpty {
                        Notice(symbol: "globe", title: "No dynamic DNS entries configured")
                    } else {
                        summary
                        ForEach(entries) { entry in
                            DyndnsRow(entry: entry,
                                      isStale: store.staleDyndns.contains { $0.id == entry.id })
                        }
                        if entries.isEmpty {
                            Notice(symbol: "magnifyingglass", title: "No matches")
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            .readableWidth()
            }
            .refreshable { await store.refreshManually() }
        }
        .background(theme.bg.ignoresSafeArea())
        .searchable(text: $query, prompt: "Hostname, address or provider")
        .navigationTitle("Dynamic DNS")
    }

    /// One line saying whether anything needs attention, so the answer does not
    /// require scrolling twenty cards.
    private var summary: some View {
        let stale = store.staleDyndns.count
        let enabled = store.dyndns.filter(\.enabled).count
        return Slab(rail: stale > 0 ? .warn : .ok) {
            VStack(alignment: .leading, spacing: 4) {
                Text(stale > 0
                     ? "\(stale) of \(enabled) may be stale"
                     : "\(enabled) entries, all matching their interface")
                    .scaledFont(14, weight: .semibold)
                    .foregroundStyle(theme.label)
                Text(stale > 0
                     ? "The cached address no longer matches the interface being watched."
                     : "pfSense records no update history, so this compares each cached address against its interface.")
                    .scaledFont(11)
                    .foregroundStyle(theme.labelFaint)
            }
        }
    }
}

struct DyndnsRow: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var store: DashboardStore
    let entry: DyndnsEntry
    let isStale: Bool

    var body: some View {
        Slab(rail: !entry.enabled ? .idle : (isStale ? .warn : .ok),
             trailing: entry.type) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.host)
                        .scaledFont(14, weight: .semibold)
                        .foregroundStyle(theme.label)
                        .textSelection(.enabled)
                    Spacer(minLength: 8)
                    if !entry.enabled {
                        StatusPill(text: "disabled", health: .idle)
                    } else if isStale {
                        StatusPill(text: "stale", health: .warn)
                    }
                }

                if let descr = entry.descr, !descr.isEmpty {
                    Text(descr)
                        .scaledFont(11)
                        .foregroundStyle(theme.labelFaint)
                }

                FieldRow(key: "Last pushed", value: entry.cachedAddress ?? "never")
                FieldRow(key: "At", value: entry.updatedDescription, mono: false)
                if let iface = entry.interfaceName, !iface.isEmpty {
                    FieldRow(key: "Watches",
                             value: store.interfaceLabel(for: iface) ?? iface)
                }
            }
        }
    }
}
