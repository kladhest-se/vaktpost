import SwiftUI

/// Five tabs is the practical ceiling before iOS collapses the bar into its own
/// "More" list, so the less-frequent destinations live behind one here instead.
struct MoreView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var store: DashboardStore
    @EnvironmentObject private var registry: ServerRegistry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                activeServerCard

                GroupHeading(text: "Sections")
                link("Alerts", "bell.badge", badge: store.criticalAlertCount) { AlertsView() }
                link("VPN", "lock.shield", badge: 0) { VPNView() }
                link("Firewall", "shield.lefthalf.filled", badge: 0) { FirewallView() }
                link("System", "server.rack", badge: 0) { SystemView() }

                GroupHeading(text: "Setup")
                link("Firewalls", "externaldrive.connected.to.line.below", badge: 0) { ServersView() }
                link("Settings", "slider.horizontal.3", badge: 0) { SettingsView() }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationTitle("More")
    }

    private var activeServerCard: some View {
        Slab(rail: store.overallHealth, title: "Active firewall") {
            VStack(alignment: .leading, spacing: 6) {
                Text(store.profile.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.label)
                Text(store.profile.baseURL)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(theme.labelFaint)
                if registry.servers.count > 1 {
                    Hairline()
                    ServerSwitcher(
                        servers: registry.servers,
                        activeID: registry.active?.id
                    ) { server in
                        Task { await store.switchTo(server) }
                    }
                }
            }
        }
    }

    private func link<Destination: View>(
        _ title: String,
        _ symbol: String,
        badge: Int,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15))
                    .foregroundStyle(theme.accentColor)
                    .frame(width: 24)
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(theme.label)
                Spacer()
                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.palette.crust)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(theme.bad)
                        .clipShape(Capsule())
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.labelFaint)
            }
            .padding(14)
            .background(theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
