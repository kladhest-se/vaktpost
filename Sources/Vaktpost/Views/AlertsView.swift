import SwiftUI

struct AlertsView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var store: DashboardStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if !store.acknowledgedButPresent.isEmpty {
                    Slab(rail: .idle) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("\(store.acknowledgedButPresent.count) acknowledged")
                                    .scaledFont(13, weight: .semibold)
                                    .foregroundStyle(theme.labelMuted)
                                Spacer()
                                Button("Show again") { store.unacknowledgeAll() }
                                    .scaledFont(13, weight: .medium)
                                    .foregroundStyle(theme.accentColor)
                            }
                            // Named rather than counted: "3 acknowledged" tells
                            // you nothing about whether you would still stand
                            // by having acknowledged them.
                            ForEach(store.acknowledgedButPresent) { alert in
                                Text(alert.title)
                                    .scaledFont(11)
                                    .foregroundStyle(theme.labelFaint)
                            }
                        }
                    }
                }

                if store.silencedAlertCount > 0 {
                    // Said plainly. A silenced alert that vanishes without
                    // trace is indistinguishable from a condition that cleared.
                    Text(store.alertsSilenced
                         ? "All alerts are silenced in Settings."
                         : "\(store.silencedAlertCount) hidden by silenced categories.")
                        .scaledFont(12)
                        .foregroundStyle(theme.labelFaint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if store.visibleAlerts.isEmpty {
                    Notice(symbol: "checkmark.seal", title: "Nothing to report",
                           detail: "No gateway, service, capacity, certificate, HA or VPN condition is currently outside its threshold.",
                           health: .ok)
                } else {
                    HStack {
                        Text("\(store.visibleAlerts.count) condition\(store.visibleAlerts.count == 1 ? "" : "s")")
                            .scaledFont(12, design: .monospaced)
                            .foregroundStyle(theme.labelFaint)
                        Spacer()
                    }
                    // Long press to silence the kind. Settings has the same
                    // switches, but nobody goes looking in Settings for a way
                    // to stop something they are looking at right now.
                    ForEach(store.visibleAlerts) { alert in
                        alertRow(alert)
                    }

                }

                Slab(rail: .idle, title: "How these are produced") {
                    Text("pfSense has no alerts endpoint. Every item here is derived on-device from status the app already fetched, so the thresholds live in one file and change without touching the firewall.")
                        .scaledFont(12)
                        .foregroundStyle(theme.labelFaint)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(theme.bg.ignoresSafeArea())
        .refreshable { await store.refreshManually() }
        .navigationTitle("Alerts")
    }

    /// One alert, with a way to stop seeing its kind.
    ///
    /// Long press rather than a visible control: silencing is a rare action and
    /// a button on every row would compete with the alert itself. Settings has
    /// the same switches, but nobody goes to Settings looking for a way to
    /// quiet something they are staring at.
    @ViewBuilder
    private func alertRow(_ alert: VaktpostAlert) -> some View {
        Slab(rail: alert.severity) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: alert.category.symbol)
                    .scaledFont(15)
                    .foregroundStyle(alert.severity.color(theme))
                    .scaledFrame(width: 22)
                VStack(alignment: .leading, spacing: 4) {
                    Text(alert.title)
                        .scaledFont(14, weight: .semibold)
                        .foregroundStyle(theme.label)
                    Text(alert.detail)
                        .scaledFont(12)
                        .foregroundStyle(theme.labelMuted)
                }
                Spacer(minLength: 0)
            }
        }
        .contextMenu {
            // Acknowledging one condition first, because it is what people
            // usually want: "I have seen this" rather than "never tell me
            // about certificates again".
            Button {
                store.acknowledge(alert)
            } label: {
                Label("Acknowledge this", systemImage: "checkmark.circle")
            }
            Button {
                store.mutedAlertCategories.insert(alert.category.rawValue)
            } label: {
                Label("Silence all \(alert.category.displayName.lowercased())",
                      systemImage: "bell.slash")
            }
        }
    }

}
