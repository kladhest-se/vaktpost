import SwiftUI

/// What DNSBL has been refusing, counted from the tail of pfBlockerNG's log.
///
/// The same numbers as the package's own DNSBL Block Stats page, from the same
/// file. Where this differs is that it says what it is counting: that page
/// processes whatever log it finds, and a reader has no way to tell whether a
/// total covers today or a fortnight. Here the window is fixed at the last
/// megabyte and the screen says when the log is bigger than that.
struct DNSBLStatsView: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let error = store.errors[.dnsbl] {
                    Notice(symbol: "exclamationmark.triangle",
                           title: "Could not read the DNSBL log",
                           detail: error,
                           health: .warn)
                } else if !store.pfBlockerInstalled {
                    Notice(symbol: "shield.slash",
                           title: "pfBlockerNG is not installed",
                           detail: "DNSBL statistics come from a log the package writes.")
                } else if !store.dnsblAvailable {
                    Notice(symbol: "shield.slash",
                           title: "DNSBL is switched off",
                           detail: "pfBlockerNG is installed but its DNSBL component is disabled, so nothing is being blocked at the resolver.")
                } else if let stats = store.dnsblStats {
                    if stats.available {
                        summary(stats)
                        breakdown(stats)
                        hourly(stats)
                        counts("Blocked domains", stats.domains, symbol: "globe")
                        counts("Clients asking", stats.clients, symbol: "person.2")
                        counts("Feeds", stats.feeds, symbol: "list.bullet")
                        counts("Groups", stats.groups, symbol: "folder")
                        provenance(stats)
                    } else {
                        Notice(symbol: "checkmark.shield",
                               title: "Nothing logged",
                               detail: "DNSBL is enabled and its log is empty. Either nothing has been blocked yet, or logging is switched off in pfBlockerNG.")
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationTitle("DNSBL")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: store.activeProfile?.id) { await store.loadDNSBLStats() }
        .refreshable { await store.loadDNSBLStats(force: true) }
    }

    private func summary(_ stats: DNSBLStats) -> some View {
        Slab(rail: .ok, title: "Blocked") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(stats.events)")
                        .scaledFont(28, weight: .bold, design: .rounded)
                        .foregroundStyle(theme.label)
                    Text("requests")
                        .scaledFont(12)
                        .foregroundStyle(theme.labelMuted)
                    Spacer()
                    if let busiest = stats.busiestHour {
                        StatusPill(text: "peak \(busiest.count)/h", health: .info)
                    }
                }
                FieldRow(key: "Distinct domains", value: "\(stats.domains.count)", mono: false)
                FieldRow(key: "Clients", value: "\(stats.clients.count)", mono: false)
                if let first = stats.first, let last = stats.last {
                    FieldRow(key: "Covering", value: "\(first) — \(last)", mono: false)
                }
            }
        }
    }

    /// The share each domain took of everything blocked.
    ///
    /// Six named slices and a remainder. The remainder is the part that makes
    /// this honest: the counts are a top-twenty and the total is every event,
    /// so a donut built only from the rows would describe the top twenty while
    /// looking like it described the whole.
    @ViewBuilder
    private func breakdown(_ stats: DNSBLStats) -> some View {
        if stats.domains.count > 1 {
            let slices = DonutChart.slices(stats.domains, total: stats.events,
                                           limit: 6, theme: theme)
            Slab(rail: .info, title: "Share") {
                HStack(alignment: .center, spacing: 14) {
                    DonutChart(slices: slices,
                               centerValue: "\(stats.events)",
                               centerCaption: "blocked")
                        .frame(width: 132, height: 132)
                    DonutLegend(slices: slices)
                }
            }
        }
    }

    /// The hourly bar chart, drawn from the labels pfBlockerNG wrote.
    ///
    /// Scaled to the busiest hour in the window rather than to a fixed
    /// ceiling, because the useful reading is the shape — one hour that dwarfs
    /// the rest is a device that started doing something, and that is visible
    /// at any scale.
    @ViewBuilder
    private func hourly(_ stats: DNSBLStats) -> some View {
        if stats.hours.count > 1 {
            let peak = stats.hours.map(\.count).max() ?? 1
            Slab(rail: .info, title: "By hour", trailing: "last \(stats.hours.count)") {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(stats.hours) { hour in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(theme.accentColor.opacity(hour.count == peak ? 0.9 : 0.5))
                                .frame(height: max(2, 70 * CGFloat(hour.count) / CGFloat(peak)))
                            Text(hour.shortLabel)
                                .scaledFont(7, design: .monospaced)
                                .foregroundStyle(theme.labelFaint)
                        }
                    }
                }
                .frame(height: 86, alignment: .bottom)
            }
        }
    }

    @ViewBuilder
    private func counts(_ title: String, _ rows: [DNSBLCount], symbol: String) -> some View {
        if !rows.isEmpty {
            GroupHeading(text: title)
            let peak = rows.map(\.count).max() ?? 1
            Slab(rail: .info) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(label(row, in: title))
                                    .scaledFont(12, design: .monospaced)
                                    .foregroundStyle(theme.label)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer(minLength: 8)
                                Text("\(row.count)")
                                    .scaledFont(12, weight: .semibold, design: .monospaced)
                                    .foregroundStyle(theme.labelMuted)
                            }
                            // A share of the busiest row. Unlike the traffic
                            // list's old bar, the denominator here is stable
                            // for as long as the screen is up — this is a
                            // fixed count over a fixed window, not a rate.
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 1, style: .continuous)
                                    .fill(theme.accentColor.opacity(0.45))
                                    .frame(width: geo.size.width * CGFloat(row.count) / CGFloat(peak))
                            }
                            .frame(height: 3)
                        }
                    }
                }
            }
        }
    }

    /// Clients get their name where the firewall knows one, the way every
    /// other address in this app does.
    private func label(_ row: DNSBLCount, in title: String) -> String {
        guard title == "Clients asking" else { return row.name }
        guard let name = store.nameForAddress(row.name) else { return row.name }
        return "\(name) (\(row.name))"
    }

    private func provenance(_ stats: DNSBLStats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if stats.truncated {
                // The honest limit. A total that silently means "some of it"
                // is worse than no total.
                Text("Counted from the last \(Fmt.bytes(stats.scannedBytes)) of a \(Fmt.bytes(stats.logBytes)) log, "
                    + "so these are recent counts rather than everything pfBlockerNG has recorded.")
            } else {
                Text("Counted from the whole log, \(Fmt.bytes(stats.logBytes)).")
            }

            if stats.unparsed > 0 {
                Text("\(stats.unparsed) lines did not have the fields a complete record has — usually a line being written as it was read.")
                    .foregroundStyle(theme.labelFaint)
            }
        }
        .scaledFont(12)
        .foregroundStyle(theme.labelMuted)
        .padding(.horizontal, 2)
    }
}
