import SwiftUI

/// Where the firewall's own tables contradict each other.
///
/// Nothing here is fetched. Every conflict is a comparison between tables the
/// client refresh already pulled, which is why this costs nothing to look at
/// and why it can be wrong in only one direction: it can miss something, but
/// anything it reports is two records this firewall is holding at once.
struct ConflictsView: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore

    private var conflicts: [ConflictDetector.Conflict] {
        ConflictDetector.find(arp: store.arp,
                              leases: store.leases,
                              staticMappings: store.staticMappings,
                              hostOverrides: store.hostOverrides)
    }

    private var serious: [ConflictDetector.Conflict] {
        conflicts.filter { $0.kind.severity == .bad }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if store.arp.isEmpty && store.leases.isEmpty {
                    Notice(symbol: "questionmark.circle",
                           title: "Nothing to compare yet",
                           detail: "This reads the ARP, lease, static mapping and DNS override tables. Refresh the dashboard first.")
                } else if conflicts.isEmpty {
                    Notice(symbol: "checkmark.circle",
                           title: "No contradictions",
                           detail: "No two records in the ARP, lease, static mapping or DNS override tables disagree.",
                           health: .ok)
                } else {
                    summary
                    ForEach(conflicts) { conflict in
                        row(conflict)
                    }
                }
                explanation
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationTitle("Conflicts")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await store.refresh() }
    }

    private var summary: some View {
        Slab(rail: serious.isEmpty ? .warn : .bad, title: "Found") {
            HStack(alignment: .firstTextBaseline) {
                Text("\(conflicts.count)")
                    .scaledFont(28, weight: .bold, design: .rounded)
                    .foregroundStyle(theme.label)
                Text(conflicts.count == 1 ? "contradiction" : "contradictions")
                    .scaledFont(12)
                    .foregroundStyle(theme.labelMuted)
                Spacer()
                if !serious.isEmpty {
                    StatusPill(text: "\(serious.count) breaking traffic", health: .bad)
                }
            }
        }
    }

    private func row(_ conflict: ConflictDetector.Conflict) -> some View {
        Slab(rail: conflict.kind.severity, title: conflict.kind.title, trailing: conflict.subject) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(conflict.sides.enumerated()), id: \.offset) { _, side in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(conflict.kind.severity.color(theme))
                            .frame(width: 5, height: 5)
                        Text(side)
                            .scaledFont(12, design: .monospaced)
                            .foregroundStyle(theme.label)
                    }
                }

                // What it means in the terms somebody debugging would use.
                // "Duplicate address" names the fault; it does not say that
                // traffic will follow whichever device answered ARP last,
                // which is the part that explains the symptom.
                Text(conflict.kind.consequence)
                    .scaledFont(11)
                    .foregroundStyle(theme.labelMuted)

                NavigationLink {
                    InvestigateView(initialQuery: conflict.subject)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                        Text("What else references this")
                    }
                    .scaledFont(11, weight: .medium)
                    .foregroundStyle(theme.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Every check compares tables this app has already fetched. Nothing here asks the firewall anything, so it costs nothing to look at.")

            // The limit, stated. A clean result is not proof of a healthy
            // network, and somebody who reads it that way has been misled by
            // this screen rather than helped by it.
            Text("It can only see what the firewall records. A device with a hardcoded address that has never spoken will not be in the ARP table, and nothing here will know about it.")

            Text("Expired leases are ignored. An old lease naming a different device is the address having been handed on, which is the system working.")
        }
        .scaledFont(12)
        .foregroundStyle(theme.labelMuted)
        .padding(.horizontal, 2)
    }
}
