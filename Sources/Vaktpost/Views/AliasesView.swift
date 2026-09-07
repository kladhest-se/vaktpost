import SwiftUI

/// Firewall aliases.
///
/// Its own screen rather than a tab on Firewall, because the rules and NAT
/// lists no longer mention aliases by name — they show the addresses those
/// aliases contain. This is where you come to look one up, which is a
/// different task from reading a rule.
struct AliasesView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var store: DashboardStore

    @State private var query = ""

    private var aliases: [FirewallAliasEntry] {
        guard !query.isEmpty else { return store.aliases }
        let q = query.lowercased()
        return store.aliases.filter {
            $0.name.lowercased().contains(q)
                || ($0.descr ?? "").lowercased().contains(q)
                || $0.addresses.contains { $0.lowercased().contains(q) }
                // Searching for a host should find the aliases holding it,
                // including through nesting — that is most of why anybody
                // opens this screen.
                || (store.resolveAlias($0.name) ?? []).contains { $0.lowercased().contains(q) }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if let err = store.errors[.aliases] {
                    Notice(symbol: "exclamationmark.triangle",
                           title: "Aliases unavailable", detail: err, health: .warn)
                } else if store.aliases.isEmpty {
                    Notice(symbol: "tag.slash", title: "No aliases configured")
                } else {
                    HStack {
                        Text("\(aliases.count) of \(store.aliases.count) aliases")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(theme.labelFaint)
                        Spacer()
                    }
                    ForEach(aliases) { AliasRow(alias: $0) }
                    if aliases.isEmpty {
                        Notice(symbol: "magnifyingglass", title: "No matches")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .refreshable { await store.refreshManually() }
        .background(theme.bg.ignoresSafeArea())
        .task { await store.loadFirewallObjects() }
        .searchable(text: $query, prompt: "Alias name, address or port")
        .navigationTitle("Aliases")
    }
}

struct AliasRow: View {
    @EnvironmentObject private var theme: ThemeManager
    let alias: FirewallAliasEntry
    @State private var expanded = false

    var body: some View {
        Slab(rail: .info, trailing: alias.type) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(alias.name)
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.label)
                    Spacer()
                    Text("\(alias.addresses.count)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(theme.labelFaint)
                }
                if let d = alias.descr, !d.isEmpty {
                    Text(d)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.labelMuted)
                }
                if !alias.addresses.isEmpty {
                    let shown = expanded ? alias.addresses : Array(alias.addresses.prefix(5))
                    ForEach(Array(shown.enumerated()), id: \.offset) { idx, addr in
                        HStack {
                            Text(addr)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(theme.label)
                            Spacer()
                            if idx < alias.details.count {
                                Text(alias.details[idx])
                                    .font(.system(size: 11))
                                    .foregroundStyle(theme.labelFaint)
                                    .lineLimit(1)
                            }
                        }
                    }
                    if alias.addresses.count > 5 {
                        Button {
                            withAnimation { expanded.toggle() }
                        } label: {
                            Text(expanded ? "Show less" : "Show all \(alias.addresses.count)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(theme.accentColor)
                        }
                    }
                }
            }
        }
    }
}
