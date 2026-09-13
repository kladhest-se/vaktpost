import SwiftUI

struct SystemView: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GroupHeading(text: "High availability")
                carpSlab.sectionFreshness([.carp])

                GroupHeading(text: "Notices")
                noticesSlab.sectionFreshness([.notices])

                GroupHeading(text: "Filesystems")
                filesystemsSlab.sectionFreshness([.filesystems])

                GroupHeading(text: "Blocked hosts")
                blockedSlab.sectionFreshness([.tables])

                GroupHeading(text: "Updates")
                updatesLinkSlab.sectionFreshness([.version, .packageUpdates, .packages])

                GroupHeading(text: "Config history")
                configHistorySlab.sectionFreshness([.configHistory])
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
            .readableWidth()
        }
        .background(theme.bg.ignoresSafeArea())
        .refreshable {
            await store.refresh()
            await store.loadFirewallObjects(force: true)
            await store.loadTables()
        }
        .task {
            await store.loadFirewallObjects()
            await store.loadTables()
        }
        .navigationTitle("System")
    }

    @ViewBuilder
    private var carpSlab: some View {
        if let carp = store.carp, carp.isConfigured {
            Slab(rail: carp.health, title: "CARP") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(carp.summary)
                            .scaledFont(14, weight: .medium)
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
                                    .scaledFont(12, design: .monospaced)
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
                    .scaledFont(12)
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
        if (store.isLoadingTables || store.isLoadingFirewallObjects)
            && store.tables.isEmpty && store.rules.isEmpty {
            Slab(rail: .idle) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading block rules and pf tables…")
                        .scaledFont(12)
                        .foregroundStyle(theme.labelMuted)
                }
            }
        } else {
            if let err = store.errors[.firewall] {
                Slab(rail: .warn, title: "Configured block rules") {
                    Text(err)
                        .scaledFont(12)
                        .foregroundStyle(theme.labelMuted)
                }
            }

            if !store.configuredHostBlocks.isEmpty {
                Slab(rail: .bad, title: "Configured block rules",
                     trailing: "\(store.configuredHostBlocks.count)") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(store.configuredHostBlocks.prefix(25)) { rule in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(rule.sourceSide.address)
                                        .scaledFont(12, weight: .semibold, design: .monospaced)
                                        .foregroundStyle(theme.label)
                                    Spacer()
                                    Text(store.interfaceLabel(for: rule.interfaceName)
                                         ?? rule.interfaceName)
                                        .scaledFont(10, design: .monospaced)
                                        .foregroundStyle(theme.labelFaint)
                                }
                                if !rule.descr.isEmpty {
                                    Text(rule.descr)
                                        .scaledFont(11)
                                        .foregroundStyle(theme.labelMuted)
                                }
                            }
                        }
                        if store.configuredHostBlocks.count > 25 {
                            Text("+\(store.configuredHostBlocks.count - 25) more")
                                .scaledFont(11)
                                .foregroundStyle(theme.labelFaint)
                        }
                    }
                }
            }

            ForEach(store.blockedHosts) { table in
                Slab(rail: .warn, title: table.name, trailing: "\(table.entryCount)") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(table.entries.prefix(25), id: \.self) { entry in
                            Text(entry)
                                .scaledFont(12, design: .monospaced)
                                .foregroundStyle(theme.label)
                                .textSelection(.enabled)
                        }
                        if table.entryCount > 25 {
                            Text("+\(table.entryCount - 25) more")
                                .scaledFont(11)
                                .foregroundStyle(theme.labelFaint)
                        }
                    }
                }
            }

            if let err = store.errors[.tables] {
                Slab(rail: .warn, title: "Dynamic blocks") {
                    Text(err)
                        .scaledFont(12)
                        .foregroundStyle(theme.labelMuted)
                }
            } else if store.tableReadState == .unavailable {
                Slab(rail: .info, title: "Dynamic blocks") {
                    Text(dynamicBlocksUnavailableMessage)
                        .scaledFont(12)
                        .foregroundStyle(theme.labelMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if store.blockedHosts.isEmpty && store.configuredHostBlocks.isEmpty {
                Slab(rail: .ok) {
                    Text("No configured host blocks or dynamic blocked hosts were found.")
                        .scaledFont(13)
                        .foregroundStyle(theme.labelMuted)
                }
            } else if store.blockedHosts.isEmpty {
                Slab(rail: .info, title: "Dynamic blocks") {
                    Text("No Login Protection or IDS table entries are currently blocked.")
                        .scaledFont(12)
                        .foregroundStyle(theme.labelMuted)
                }
            }
        }
    }

    private var dynamicBlocksUnavailableMessage: String {
        let configured = store.configuredHostBlocks.isEmpty
            ? "No enabled literal-source block rules were found in the configuration."
            : "Configured block rules are shown above."
        return "This pfSense build does not expose live pf-table entries to PHP. \(configured) "
            + "Login Protection and IDS tables require Diagnostics → Tables in the webConfigurator."
    }

    /// A single row summarising both update surfaces, linking to the
    /// combined page. The status logic mirrors Overview's Updates tile
    /// exactly, so the two never disagree about what "up to date" means.
    @ViewBuilder
    private var updatesLinkSlab: some View {
        NavigationLink {
            UpdatesView()
        } label: {
            Slab(rail: (store.version?.updateAvailable == true || !store.packagesNeedingUpdate.isEmpty) ? .warn : .ok) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        if store.version?.updateAvailable == true, let latest = store.version?.latest {
                            Text("pfSense \(latest) available")
                                .scaledFont(14, weight: .semibold)
                                .foregroundStyle(theme.warn)
                        } else if !store.packagesNeedingUpdate.isEmpty {
                            Text("\(store.packagesNeedingUpdate.count) package update\(store.packagesNeedingUpdate.count > 1 ? "s" : "") available")
                                .scaledFont(14, weight: .semibold)
                                .foregroundStyle(theme.warn)
                        } else {
                            Text("Up to date")
                                .scaledFont(14, weight: .semibold)
                                .foregroundStyle(theme.ok)
                        }
                        Text("pfSense firmware and \(store.packages.count) package\(store.packages.count == 1 ? "" : "s")")
                            .scaledFont(11)
                            .foregroundStyle(theme.labelFaint)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .scaledFont(12, weight: .semibold)
                        .foregroundStyle(theme.labelFaint)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// pfSense's own notices — the bell icon in the webConfigurator.
    @ViewBuilder
    private var noticesSlab: some View {
        if store.notices.isEmpty {
            Slab(rail: .ok) {
                Text("No pending notices.")
                    .scaledFont(13)
                    .foregroundStyle(theme.labelMuted)
            }
        } else {
            ForEach(store.notices) { notice in
                Slab(rail: notice.health, trailing: notice.displayTime) {
                    VStack(alignment: .leading, spacing: 4) {
                        NoticeText(notice: notice)
                        if let category = notice.category, !category.isEmpty {
                            Text(category)
                                .scaledFont(11, design: .monospaced)
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
                    .scaledFont(12)
                    .foregroundStyle(theme.labelMuted)
            }
        } else {
            Slab(rail: store.overviewLayout.fullFilesystems.isEmpty ? .ok : .warn) {
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
                    .scaledFont(12)
                    .foregroundStyle(theme.labelMuted)
            }
        } else {
            ForEach(store.configHistory) { rev in
                Slab(rail: .info) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(rev.displayTime)
                                .scaledFont(12, weight: .semibold, design: .monospaced)
                                .foregroundStyle(theme.label)
                            Spacer()
                            if let u = rev.username, !u.isEmpty {
                                Text(u)
                                    .scaledFont(11, design: .monospaced)
                                    .foregroundStyle(theme.labelFaint)
                                    .lineLimit(2)
                            }
                        }
                        Text(rev.descr.isEmpty ? "(no description)" : rev.descr)
                            .scaledFont(12)
                            .foregroundStyle(rev.descr.isEmpty ? theme.labelFaint : theme.labelMuted)
                    }
                }
            }
        }
    }
}
