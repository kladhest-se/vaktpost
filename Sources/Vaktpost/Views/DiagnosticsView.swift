import SwiftUI

/// What is not working, in one place.
///
/// Every section already records why it failed, but that error only appears on
/// the card it belongs to — so a person whose Gateways card is empty has to
/// find the Gateways card to learn why, and somebody wondering whether the app
/// is healthy has to visit nine screens to find out. Several of this app's own
/// bugs went unnoticed for a session because the evidence was scattered.
///
/// Nothing here is fetched. It is the state the refresh already produced,
/// gathered and named.
struct DiagnosticsView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var store: DashboardStore
    @EnvironmentObject private var registry: ServerRegistry

    private var failing: [(section: DashboardStore.Section, message: String)] {
        store.errors
            .map { (section: $0.key, message: $0.value) }
            .sorted { $0.section.displayName < $1.section.displayName }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                summary
                NavigationLink("Data freshness") { DataFreshnessView() }
                    .foregroundStyle(theme.accentColor)

                if !failing.isEmpty {
                    GroupHeading(text: "Not working")
                    ForEach(failing, id: \.section) { entry in
                        Slab(rail: store.abandonedSections.contains(entry.section) ? .bad : .warn) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(entry.section.displayName)
                                        .scaledFont(14, weight: .semibold)
                                        .foregroundStyle(theme.label)
                                    Spacer(minLength: 8)
                                    if store.abandonedSections.contains(entry.section) {
                                        StatusPill(text: "stopped retrying", health: .bad)
                                    }
                                }
                                Text(entry.message)
                                    .scaledFont(12)
                                    .foregroundStyle(theme.labelMuted)
                                    .textSelection(.enabled)

                                let faults = store.faultCount(for: entry.section)
                                if faults > 0 {
                                    // Said plainly, because each attempt has a
                                    // cost the person cannot otherwise see: a
                                    // faulting snippet writes a notice to the
                                    // firewall every time it runs.
                                    Text("\(faults) failed attempt\(faults == 1 ? "" : "s") — each one leaves a notice on the firewall.")
                                        .scaledFont(10)
                                        .foregroundStyle(theme.labelFaint)
                                }
                            }
                        }
                    }
                }

                GroupHeading(text: "Connection")
                Slab(rail: store.connectionError == nil ? .ok : .bad) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let err = store.connectionError {
                            Text(err)
                                .scaledFont(13)
                                .foregroundStyle(theme.label)
                                .textSelection(.enabled)
                        } else {
                            FieldRow(key: "Firewall",
                                     value: registry.active?.displayName ?? "none selected")
                            if let version = store.version?.current {
                                FieldRow(key: "Version", value: version)
                            }
                            HStack {
                                Text("LAST REFRESH ATTEMPT")
                                    .scaledFont(9, weight: .semibold)
                                    .foregroundStyle(theme.labelFaint)
                                Spacer()
                                if let last = store.lastRefresh {
                                    // The same rendering the Overview uses, so
                                    // the two cannot disagree about the time.
                                    Text(last, style: .time)
                                        .scaledFont(12, design: .monospaced)
                                        .foregroundStyle(theme.labelMuted)
                                } else {
                                    Text("never")
                                        .scaledFont(12, design: .monospaced)
                                        .foregroundStyle(theme.labelFaint)
                                }
                            }
                        }
                    }
                }

                GroupHeading(text: "Throughput sampling")
                Slab(rail: store.throughput.summary.isEmpty ? .warn : .info) {
                    VStack(alignment: .leading, spacing: 4) {
                        if store.throughput.summary.isEmpty {
                            Text("No interface has been sampled yet.")
                                .scaledFont(13)
                                .foregroundStyle(theme.label)
                            Text("A rate needs two readings. If this stays empty after a couple of refreshes, the counters are not arriving.")
                                .scaledFont(11)
                                .foregroundStyle(theme.labelFaint)
                        } else {
                            ForEach(store.throughput.summary, id: \.key) { entry in
                                HStack {
                                    Text(entry.key)
                                        .scaledFont(11, design: .monospaced)
                                        .foregroundStyle(theme.labelMuted)
                                    Spacer()
                                    Text("\(entry.points) point\(entry.points == 1 ? "" : "s")")
                                        .scaledFont(11, design: .monospaced)
                                        .foregroundStyle(entry.points > 1 ? theme.ok : theme.warn)
                                }
                            }
                            let waiting = store.throughput.awaitingSecondSample
                            if !waiting.isEmpty {
                                Text("Baseline only, no rate yet: \(waiting.joined(separator: ", "))")
                                    .scaledFont(10)
                                    .foregroundStyle(theme.labelFaint)
                            }
                        }
                    }
                }
                }

                GroupHeading(text: "Historical traffic")
                Slab(rail: rrdRail) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(rrdHeadline)
                            .scaledFont(13)
                            .foregroundStyle(theme.label)
                        if let detail = rrdDetail {
                            Text(detail)
                                .scaledFont(11, design: .monospaced)
                                .foregroundStyle(theme.labelFaint)
                                .textSelection(.enabled)
                        }
                        if store.rrdHistory == nil && !store.isLoadingRRD {
                            Button("Read it now") {
                                Task { await store.loadRRD() }
                            }
                            .scaledFont(13, weight: .semibold)
                            .foregroundStyle(theme.accentColor)
                        }
                    }
                }

            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
            .readableWidth()
        }
        .refreshable { await store.refreshManually() }
        .background(theme.bg.ignoresSafeArea())
        .navigationTitle("Diagnostics")
    }

    // MARK: RRD
    //
    // On this screen because a chart that draws nothing cannot explain itself
    // in the space it has, and because "which files came back" is the fact
    // that decides whether history will ever work here. The throughput panel
    // above settled the same kind of question in one screenshot.

    private var rrdRail: Health {
        if store.errors[.rrd] != nil { return .warn }
        guard let history = store.rrdHistory else { return .idle }
        return history.available && !history.series.isEmpty ? .ok : .warn
    }

    private var rrdHeadline: String {
        if store.isLoadingRRD { return "Reading…" }
        if store.errors[.rrd] != nil { return "The read failed" }
        guard let history = store.rrdHistory else { return "Not read yet" }
        if !history.available { return "This pfSense cannot read RRD from PHP" }
        if history.series.isEmpty { return "Readable, but no traffic series came back" }
        return "\(history.series.count) series across \(Set(history.series.map(\.file)).count) interfaces"
    }

    private var rrdDetail: String? {
        if let err = store.errors[.rrd] { return err }
        guard let history = store.rrdHistory else { return nil }
        if !history.available {
            return "rrd_fetch is not available; that needs the PHP rrd extension."
        }
        let files = Array(Set(history.series.map(\.file))).sorted()
        guard !files.isEmpty else {
            return "No *-traffic.rrd files were found in /var/db/rrd."
        }
        // Point counts as well as names.
        //
        // "144 series" tells us the fetch worked and nothing about whether any
        // of them carry samples — a series that parsed to zero points renders
        // as a blank chart, which is what sent the last round of guessing.
        let samples = history.series.reduce(0) { $0 + $1.points.count }
        let withData = history.series.filter { !$0.points.isEmpty }.count
        // What the firewall had, beside what survived: all-unknown values and
        // an empty file look the same once they reach the app.
        let seen = history.series.reduce(0) { $0 + $1.valuesSeen }

        // When the firewall last wrote one of these files.
        //
        // If that is hours ago, a day of unknown values needs no further
        // explanation — pfSense writes them every minute while monitoring is
        // on, so a stale file means the recording stopped, not that the app
        // read it wrongly.
        var freshness = ""
        let ages = history.series.map(\.ageSeconds).filter { $0 >= 0 }
        if let newest = ages.min() {
            freshness = newest < 120
                ? "\nLast written \(newest)s ago."
                : "\nLast written \(newest / 60) minutes ago — pfSense writes these every minute while monitoring is on, so nothing has been recorded since."
        }

        // Which window answered, so a week-long fallback succeeding is not
        // mistaken for the day working.
        let windows = Set(history.series.filter { !$0.points.isEmpty }.map(\.resolution))
        var how = ""
        if let used = windows.first, windows.count == 1 {
            switch used {
            case 300: how = " at 5-minute resolution"
            case 60: how = " at 1-minute resolution"
            case -1: how = " — but only over a week, so nothing recent is recorded"
            default: how = " at rrdtool's default"
            }
        }

        return "\(samples) samples in \(withData) of \(history.series.count) series\(how)"
            + " — \(seen) values offered, \(samples) numeric"
            + freshness + "\n"
            + files.joined(separator: ", ")
    }

    private var summary: some View {
        Slab(rail: failing.isEmpty ? .ok : .warn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(failing.isEmpty
                     ? "Everything the app asks for is answering"
                     : "\(failing.count) of \(DashboardStore.Section.allCases.count) sections are failing")
                    .scaledFont(14, weight: .semibold)
                    .foregroundStyle(theme.label)
                Text("Nothing here is fetched — it is what the last refresh already found out.")
                    .scaledFont(11)
                    .foregroundStyle(theme.labelFaint)
            }
        }
    }
}
