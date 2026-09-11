import SwiftUI

/// pfBlockerNG, as far as the firewall will say without being asked to parse
/// its own logs.
///
/// The headline is the number of addresses pf currently holds across the
/// aliases pfBlockerNG maintains, because that is what is actually blocking
/// traffic. A feed file on disk says what was downloaded; a pf table says what
/// is loaded into the running firewall, and those differ whenever an update
/// has been fetched and not applied.
struct PFBlockerView: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let error = store.errors[.pfblocker] {
                    Notice(symbol: "exclamationmark.triangle",
                           title: "Could not read pfBlockerNG",
                           detail: error,
                           health: .warn)
                } else if let status = store.pfBlocker {
                    summary(status)
                    dnsblLink(status)
                    feeds(status)
                    logs(status)
                    diagnostics(status)
                } else if store.pfBlockerInstalled == false && store.errors[.pfblocker] == nil {
                    Notice(symbol: "shield.slash",
                           title: "pfBlockerNG is not installed",
                           detail: "Nothing on this firewall keeps the aliases or databases the package writes.")
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationTitle("pfBlockerNG")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.loadPFBlocker() }
        .refreshable { await store.loadPFBlocker(force: true) }
    }

    private func summary(_ status: PFBlockerStatus) -> some View {
        Slab(rail: status.enabled ? .ok : .idle, title: "Blocking") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(status.blockedAddresses)")
                        .scaledFont(28, weight: .bold, design: .rounded)
                        .foregroundStyle(theme.label)
                        .contentTransition(.numericText())
                    Text("addresses loaded into pf")
                        .scaledFont(12)
                        .foregroundStyle(theme.labelMuted)
                    Spacer()
                    StatusPill(text: status.enabled ? "enabled" : "disabled",
                               health: status.enabled ? .ok : .idle)
                }
                FieldRow(key: "DNSBL", value: status.dnsblEnabled ? "enabled" : "disabled", mono: false)
                FieldRow(key: "Lists", value: "\(status.feeds.count)", mono: false)
            }
        }
    }

    /// Through to the block statistics, where DNSBL is actually running.
    ///
    /// Offered only when the component is enabled: a link to a screen that can
    /// only say "this is switched off" is a worse answer than no link.
    @ViewBuilder
    private func dnsblLink(_ status: PFBlockerStatus) -> some View {
        if status.dnsblEnabled {
            NavigationLink {
                DNSBLStatsView()
            } label: {
                Slab(rail: .info) {
                    HStack(spacing: 10) {
                        Image(systemName: "chart.bar.doc.horizontal")
                            .scaledFont(14)
                            .foregroundStyle(theme.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("DNSBL block stats")
                                .scaledFont(13, weight: .semibold)
                                .foregroundStyle(theme.label)
                            Text("What the resolver has been refusing, and for whom")
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
        }
    }

    @ViewBuilder
    private func feeds(_ status: PFBlockerStatus) -> some View {
        if status.feeds.isEmpty {
            Notice(symbol: "list.bullet",
                   title: "No pfB_ aliases",
                   detail: "The package is present but has not created any aliases yet. That is normal before its first update runs.")
        } else {
            GroupHeading(text: "Lists")

            if !status.unloadedFeeds.isEmpty {
                // Configured but holding nothing in pf is the failure worth
                // surfacing: it looks identical to a quiet feed on any screen
                // that prints a zero.
                Notice(symbol: "exclamationmark.circle",
                       title: "\(status.unloadedFeeds.count) list\(status.unloadedFeeds.count == 1 ? "" : "s") with nothing in them",
                       detail: "These aliases are configured but have no table file and no inline members, so they are not blocking anything. A list whose update has not run yet looks like this.",
                       health: .warn)
            }

            ForEach(status.feeds) { feed in
                Slab(rail: feed.entries == nil ? .warn : .info, trailing: feed.type) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feed.shortName)
                                .scaledFont(13, weight: .semibold)
                                .foregroundStyle(theme.label)
                            if let descr = feed.descr {
                                Text(descr)
                                    .scaledFont(11)
                                    .foregroundStyle(theme.labelFaint)
                            }
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(feed.entries.map { "\($0)" } ?? "not downloaded")
                                .scaledFont(12, design: .monospaced)
                                .foregroundStyle(feed.entries == nil ? theme.warn : theme.label)
                            if feed.entries != nil {
                                Text(feed.source.description)
                                    .scaledFont(8)
                                    .foregroundStyle(theme.labelFaint)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func logs(_ status: PFBlockerStatus) -> some View {
        if !status.logs.isEmpty {
            GroupHeading(text: "Logs")
            Slab(rail: .info) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(status.logs) { log in
                        HStack(alignment: .firstTextBaseline) {
                            Text(log.name)
                                .scaledFont(12, design: .monospaced)
                                .foregroundStyle(theme.label)
                            Spacer(minLength: 8)
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(Fmt.bytes(log.bytes))
                                    .scaledFont(11, design: .monospaced)
                                    .foregroundStyle(theme.labelMuted)
                                if let updated = log.updated {
                                    Text(Fmt.dateTime(updated))
                                        .scaledFont(10)
                                        .foregroundStyle(theme.labelFaint)
                                }
                            }
                        }
                    }
                    Hairline()
                    // Described rather than read. A busy firewall's block log
                    // runs to hundreds of megabytes, and pulling it across the
                    // wire to count its lines would cost more than the count
                    // is worth. The modification time answers the question
                    // somebody actually has.
                    Text("Sizes and times only. A log that has not been written to in days is a component that is not running, which is what these are here to show.")
                        .scaledFont(11)
                        .foregroundStyle(theme.labelFaint)
                    }
            }
        }
    }

    private func diagnostics(_ status: PFBlockerStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if status.accessor != nil {
                Text("Counts come from the pf tables behind pfBlockerNG's own aliases — the running firewall, rather than the files it downloads.")
            } else {
                // Not a warning any more. This pfSense simply does not expose
                // the pf accessor, which is the normal case on Plus, and the
                // counts come from the file pf loads from instead.
                Text("Counts come from the table files pfBlockerNG downloads, in /var/db/aliastables, which is what pf is loaded from. This pfSense does not expose a pf accessor, so a list written but not yet applied still counts here.")
            }

            if !status.foundPaths.isEmpty {
                Text("Found: \(status.foundPaths.joined(separator: ", ")).")
                    .scaledFont(11, design: .monospaced)
                    .foregroundStyle(theme.labelFaint)
            }
        }
        .scaledFont(12)
        .foregroundStyle(theme.labelMuted)
        .padding(.horizontal, 2)
    }
}
