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
                                Text("LAST REFRESH")
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
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
            .readableWidth()
        }
        .refreshable { await store.refreshManually() }
        .background(theme.bg.ignoresSafeArea())
        .navigationTitle("Diagnostics")
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
