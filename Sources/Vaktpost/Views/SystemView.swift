import SwiftUI

struct SystemView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var store: DashboardStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GroupHeading(text: "High availability")
                carpSlab

                GroupHeading(text: "Notices")
                noticesSlab

                GroupHeading(text: "Filesystems")
                filesystemsSlab

                GroupHeading(text: "Blocked hosts")
                blockedSlab

                GroupHeading(text: "Firmware")
                firmwareSlab

                GroupHeading(text: "Packages")
                packageCheckSlab
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

    /// The check is a button rather than automatic.
    ///
    /// It reaches the package repository over the network and takes seconds,
    /// which is fine when somebody asks and wrong on a thirty-second timer.
    /// Firmware, checked on demand like packages.
    ///
    /// The version comparison comes back with every refresh, but a person
    /// looking at this screen wants to know it is current *now*, not as of the
    /// last cycle — so the button forces a fresh read and says what it found.
    @ViewBuilder
    private var firmwareSlab: some View {
        Slab(rail: store.version?.updateAvailable == true ? .warn : .ok, title: "pfSense") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(store.version?.current ?? "unknown version")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.label)
                    Spacer()
                    if store.isCheckingFirmware {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Check") {
                            Task { await store.checkFirmware() }
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.accentColor)
                    }
                }
                if store.version?.updateAvailable == true, let latest = store.version?.latest {
                    Text("\(latest) is available.")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.warn)
                } else {
                    Text(store.firmwareCheckResult ?? "Up to date as of the last refresh.")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.labelFaint)
                }
            }
        }
    }

    @ViewBuilder
    private var packageCheckSlab: some View {
        Slab(rail: .info) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Check against the repository")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.label)
                    Spacer()
                    if store.isCheckingPackages {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Check") {
                            Task { await store.checkPackageUpdates() }
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.accentColor)
                    }
                }
                // The age of the answer matters as much as the answer: "no
                // updates" from a week ago is a different claim from "no
                // updates" from this morning.
                Text(store.packageCheckResult
                     ?? store.packageCheckAge.map { "Last checked \($0)." }
                     ?? "Not checked yet. Versions here come from the configuration; checking asks the repository and takes a few seconds.")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.labelFaint)
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

    /// pfSense's own notices — the bell icon in the webConfigurator.
    @ViewBuilder
    private var noticesSlab: some View {
        if store.notices.isEmpty {
            Slab(rail: .ok) {
                Text("No pending notices.")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.labelMuted)
            }
        } else {
            ForEach(store.notices) { notice in
                Slab(rail: notice.health, trailing: notice.displayTime) {
                    VStack(alignment: .leading, spacing: 4) {
                        NoticeText(notice: notice)
                        if let category = notice.category, !category.isEmpty {
                            Text(category)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(theme.labelFaint)
                        }
                    }
                }
            }
        }
    }

    /// Per-mount usage, rather than the single aggregate figure the REST
    /// transport reported. A full /var stops logging while / looks fine.
    @ViewBuilder
    private var filesystemsSlab: some View {
        if store.filesystems.isEmpty {
            Slab(rail: .idle) {
                Text(store.errors[.filesystems] ?? "No filesystem data.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.labelMuted)
            }
        } else {
            Slab(rail: store.fullFilesystems.isEmpty ? .ok : .warn) {
                VStack(spacing: 10) {
                    ForEach(store.filesystems) { fs in
                        Meter(
                            label: fs.mountpoint,
                            value: (fs.percentUsed ?? 0) / 100,
                            readout: Fmt.pct(fs.percentUsed ?? 0),
                            health: fs.health
                        )
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
