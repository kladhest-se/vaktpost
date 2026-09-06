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

                GroupHeading(text: "Blocked hosts")
                blockedSlab

                GroupHeading(text: "Packages")
                packagesSlab

                GroupHeading(text: "Config history")
                configHistorySlab
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(theme.bg.ignoresSafeArea())
        .refreshable {
            await store.refresh()
            await store.loadTables()
        }
        .task { await store.loadTables() }
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

    /// Addresses Login Protection and friends are currently blocking.
    ///
    /// Useful mostly when the person blocked is you: a few failed API attempts
    /// will put your own workstation in `sshguard`, and the symptom is a
    /// connection that times out rather than one that says why.
    @ViewBuilder
    private var blockedSlab: some View {
        if store.isLoadingTables && store.tables.isEmpty {
            Slab(rail: .idle) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading pf tables…")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.labelMuted)
                }
            }
        } else if let err = store.errors[.tables] {
            Slab(rail: .warn) {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.labelMuted)
            }
        } else if store.blockedHosts.isEmpty {
            Slab(rail: .ok) {
                Text("Nothing is currently blocked.")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.labelMuted)
            }
        } else {
            ForEach(store.blockedHosts) { table in
                Slab(rail: .warn, title: table.name, trailing: "\(table.entryCount)") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(table.entries.prefix(25), id: \.self) { entry in
                            Text(entry)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(theme.label)
                                .textSelection(.enabled)
                        }
                        if table.entryCount > 25 {
                            Text("+\(table.entryCount - 25) more")
                                .font(.system(size: 11))
                                .foregroundStyle(theme.labelFaint)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var packagesSlab: some View {
        if store.packages.isEmpty {
            Slab(rail: .idle) {
                Text(store.errors[.packages] ?? "No packages installed.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.labelMuted)
            }
        } else {
            let sorted = store.packages.sorted {
                if $0.updateAvailable != $1.updateAvailable { return $0.updateAvailable }
                return $0.shortName.localizedCaseInsensitiveCompare($1.shortName) == .orderedAscending
            }
            ForEach(sorted) { pkg in
                Slab(rail: pkg.health) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(pkg.shortName)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(theme.label)
                            Spacer()
                            Text(pkg.versionLine)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(pkg.updateAvailable ? theme.warn : theme.labelMuted)
                        }
                        if let d = pkg.descr, !d.isEmpty {
                            Text(d)
                                .font(.system(size: 11))
                                .foregroundStyle(theme.labelFaint)
                                .lineLimit(2)
                        }
                    }
                }
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
