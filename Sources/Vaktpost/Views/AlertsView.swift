import SwiftUI

struct AlertsView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var store: DashboardStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if store.alerts.isEmpty {
                    Notice(symbol: "checkmark.seal", title: "Nothing to report",
                           detail: "No gateway, service, capacity, certificate, HA or VPN condition is currently outside its threshold.",
                           health: .ok)
                } else {
                    HStack {
                        Text("\(store.alerts.count) condition\(store.alerts.count == 1 ? "" : "s")")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(theme.labelFaint)
                        Spacer()
                    }
                    ForEach(store.alerts) { alert in
                        Slab(rail: alert.severity) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: alert.category.symbol)
                                    .font(.system(size: 15))
                                    .foregroundStyle(alert.severity.color(theme))
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(alert.title)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(theme.label)
                                    Text(alert.detail)
                                        .font(.system(size: 12))
                                        .foregroundStyle(theme.labelMuted)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }

                Slab(rail: .idle, title: "How these are produced") {
                    Text("pfSense has no alerts endpoint. Every item here is derived on-device from status the app already fetched, so the thresholds live in one file and change without touching the firewall.")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.labelFaint)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(theme.bg.ignoresSafeArea())
        .refreshable { await store.refresh() }
        .navigationTitle("Alerts")
    }
}
