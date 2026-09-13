import SwiftUI

struct AllFirewallsView: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.serverRegistry) private var registry: ServerRegistry
    @Environment(\.dashboardStore) private var dashboard: DashboardStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var fleet = FleetStore()
    @State private var managing = false

    private struct Poll: Hashable {
        let profiles: [ServerProfile]
        let active: Bool
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Connection, load, gateways, services, and certificates across your firewalls. "
                    + "Checks repeat while this screen is active. Pull down to refresh.")
                    .scaledFont(12)
                    .foregroundStyle(theme.labelMuted)
                if registry.servers.isEmpty {
                    Notice(symbol: "server.rack", title: "No firewalls yet",
                           detail: "Add a firewall to start monitoring.")
                }
                ForEach(registry.servers) { profile in
                    card(profile)
                }
                Button("Manage firewalls") { managing = true }
                    .foregroundStyle(theme.accentColor)
                    .padding(.vertical, 8)
            }
            .padding(16)
            .readableWidth()
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationTitle("All firewalls")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await fleet.refresh(registry.servers) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(fleet.isRefreshing)
                .accessibilityLabel("Refresh all firewalls")
            }
        }
        .sheet(isPresented: $managing) {
            NavigationStack {
                ServersView()
                    .toolbar { ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { managing = false }
                    } }
            }
        }
        .task(id: Poll(profiles: registry.servers, active: scenePhase == .active && !managing)) {
            guard scenePhase == .active, !managing else { fleet.stop(); return }
            await fleet.monitor(registry.servers)
        }
        .refreshable { await fleet.refresh(registry.servers) }
        .onDisappear { fleet.stop() }
    }

    private func card(_ profile: ServerProfile) -> some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let snapshot = fleet.snapshots[profile.id]
            let reading = snapshot?.reading
            let stale = snapshot?.lastSuccess.map { context.date.timeIntervalSince($0) > 120 } ?? false
            let health: Health = snapshot?.failure != nil ? .bad
                : stale || reading?.needsAttention == true ? .warn
                : reading != nil ? .ok : .idle
            Slab(rail: health) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(profile.displayName).scaledFont(16, weight: .semibold)
                        Spacer()
                        StatusPill(text: snapshot?.failure != nil ? "Check failed"
                            : stale ? "Stale" : reading?.needsAttention == true ? "Needs attention"
                            : reading != nil ? "Connected" : "Not checked", health: health)
                    }
                    Text(profile.baseURL)
                        .scaledFont(11, design: .monospaced)
                        .foregroundStyle(theme.labelFaint)
                        .lineLimit(2)
                    if let failure = snapshot?.failure {
                        Text(failure).scaledFont(12).foregroundStyle(theme.warn)
                        Text("Open this firewall to check its connection or approve its certificate.")
                            .scaledFont(11).foregroundStyle(theme.labelMuted)
                    }
                    if let reading {
                        HStack {
                            metric("CPU", reading.cpuUsage)
                            metric("Memory", reading.memoryUsage)
                            metric("Disk", reading.diskUsage)
                        }
                        if reading.cpuUsage == nil {
                            Text("CPU usage needs two successful checks.")
                                .scaledFont(10).foregroundStyle(theme.labelFaint)
                        }
                        if let uptime = reading.uptimeSeconds {
                            Text("Uptime: \(Fmt.uptime(uptime))")
                                .scaledFont(11).foregroundStyle(theme.labelMuted)
                        }
                        Text("\(reading.gatewayProblems) gateway issues · \(reading.stoppedServices) stopped services")
                            .scaledFont(12)
                        if reading.unknownGateways > 0 {
                            Text("\(reading.unknownGateways) gateways have no status yet.")
                                .scaledFont(11).foregroundStyle(theme.warn)
                        }
                        if let count = reading.certificateWarnings {
                            Text("\(count) certificates expired or due within 30 days")
                                .scaledFont(12)
                        } else {
                            Text("Certificate check unavailable")
                                .scaledFont(12).foregroundStyle(theme.warn)
                            if let error = reading.certificateError {
                                Text(error).scaledFont(10).foregroundStyle(theme.labelFaint)
                            }
                        }
                    }
                    HStack(spacing: 4) {
                        if let date = snapshot?.lastSuccess {
                            Text(snapshot?.failure != nil || stale ? "Last success" : "Updated")
                            Text(date, style: .relative)
                            Text("ago")
                        } else { Text("No successful check yet") }
                        if fleet.checkingID == profile.id { Text("· checking…") }
                    }
                    .scaledFont(10).foregroundStyle(theme.labelFaint)
                    Button(profile.id == registry.active?.id ? "Open current firewall" : "Open firewall") {
                        fleet.stop()
                        dismiss()
                        Task { await dashboard.switchTo(profile) }
                    }
                    .scaledFont(13, weight: .semibold)
                    .foregroundStyle(theme.accentColor)
                }
            }
        }
    }

    private func metric(_ title: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).scaledFont(10).foregroundStyle(theme.labelFaint)
            Text(value.map { String(format: "%.0f%%", $0) } ?? "—")
                .scaledFont(19, weight: .semibold, design: .monospaced)
                .foregroundStyle((value ?? 0) >= 90 ? theme.warn : theme.label)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
