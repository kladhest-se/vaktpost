import SwiftUI

struct SystemView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var store: DashboardStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GroupHeading(text: "High availability")
                carpSlab

                GroupHeading(text: "Certificates")
                certificatesSlab

                GroupHeading(text: "Config history")
                configHistorySlab
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(theme.bg.ignoresSafeArea())
        .refreshable { await store.refresh() }
        .navigationTitle("System")
    }

    @ViewBuilder
    private var carpSlab: some View {
        if let carp = store.carp, carp.isConfigured {
            Slab(rail: carp.health, title: "CARP") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(carp.summary)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(theme.label)
                        Spacer()
                        if carp.maintenanceMode == true {
                            StatusPill(text: "maintenance", health: .warn)
                        }
                    }
                    if !carp.interfaces.isEmpty {
                        Hairline()
                        ForEach(carp.interfaces) { vip in
                            HStack {
                                Text("\(vip.interfaceName) · vhid \(vip.vhid)")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(theme.labelMuted)
                                Spacer()
                                StatusPill(text: vip.status, health: vip.health)
                            }
                        }
                    }
                }
            }
        } else {
            Slab(rail: .idle) {
                Text(store.errors[.carp] ?? "CARP is not configured on this firewall.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.labelMuted)
            }
        }
    }

    @ViewBuilder
    private var certificatesSlab: some View {
        if store.certificates.isEmpty {
            Slab(rail: .idle) {
                Text(store.errors[.certificates] ?? "No certificates returned.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.labelMuted)
            }
        } else {
            ForEach(store.certificates.sorted { ($0.daysRemaining ?? 99_999) < ($1.daysRemaining ?? 99_999) }) { cert in
                Slab(rail: cert.health, trailing: cert.isCA ? "CA" : nil) {
                    HStack {
                        Text(cert.descr)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(theme.label)
                            .lineLimit(1)
                        Spacer()
                        if let days = cert.daysRemaining {
                            StatusPill(
                                text: days < 0 ? "expired" : "\(days)d left",
                                health: cert.health
                            )
                        } else {
                            StatusPill(text: "no date", health: .idle)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var configHistorySlab: some View {
        if store.configHistory.isEmpty {
            Slab(rail: .idle) {
                Text(store.errors[.configHistory] ?? "No configuration revisions returned.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.labelMuted)
            }
        } else {
            ForEach(store.configHistory) { rev in
                Slab(rail: .info) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(rev.displayTime)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(theme.label)
                            Spacer()
                            if let u = rev.username, !u.isEmpty {
                                Text(u)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(theme.labelFaint)
                                    .lineLimit(1)
                            }
                        }
                        Text(rev.descr.isEmpty ? "(no description)" : rev.descr)
                            .font(.system(size: 12))
                            .foregroundStyle(rev.descr.isEmpty ? theme.labelFaint : theme.labelMuted)
                    }
                }
            }
        }
    }
}
