import SwiftUI

/// Five tabs is the practical ceiling before iOS collapses the bar into its own
/// "More" list, so the less-frequent destinations live behind one here instead.
struct MoreView: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore

    var body: some View {
        ScrollView {
            PageHeader(title: "More", subtitle: "Monitoring and administration")
            VStack(alignment: .leading, spacing: 20) {
                group("Firewall") {
                    link("Firewall Rules and NAT", "shield.lefthalf.filled", badge: 0) { FirewallView() }
                    link("Aliases", "tag", badge: 0) { AliasesView() }
                    // Apply Changes, Quick Block, and Flush States are pure
                    // action screens -- nothing left to look at once the one
                    // control on each is disabled. Monitor-only sees why
                    // instead of tapping through to find out.
                    if store.canAdminister {
                        link("Apply Firewall Changes", "arrow.clockwise",
                             badge: store.firewallChangesPending ? 1 : 0) { FirewallReloadView() }
                        link("Quick Block", "shield.slash", badge: 0) { QuickBlockView() }
                        link("Flush States", "trash", badge: 0) { FlushStatesView() }
                    } else {
                        AdministrationModeNotice()
                    }
                }

                group("Monitoring") {
                    link("VPN", "lock.shield", badge: 0) { VPNView() }
                    link("Incident Timeline", "point.3.connected.trianglepath.dotted", badge: 0) { IncidentTimelineView() }
                    link("Analytics", "chart.bar", badge: 0) { AnalyticsView() }
                    link("Investigate", "magnifyingglass", badge: 0) { InvestigateView() }
                    link("Network Tools", "dot.radiowaves.left.and.right", badge: 0) { NetworkToolsView() }
                    link("Speed Test", "gauge.with.dots.needle.67percent", badge: 0) { SpeedtestView() }
                    link("Conflicts", "exclamationmark.triangle", badge: store.conflictCount) { ConflictsView() }
                }

                group("Services") {
                    link("Service Manager", "power",
                         badge: store.overviewLayout.servicesDown.count) { ServiceManagerView() }
                    link("Dynamic DNS", "globe", badge: store.overviewLayout.staleDyndns.count) { DyndnsView() }
                    link("HAProxy", "arrow.triangle.swap", badge: store.unmonitoredBackends.count) { HAProxyView() }
                    link("pfBlockerNG", "shield.lefthalf.filled.badge.checkmark", badge: 0) { PFBlockerView() }
                }

                group("System") {
                    link("System Status", "server.rack", badge: 0) { SystemView() }
                    link("Certificates", "lock.doc", badge: store.expiringCertificateCount) { CertificatesView() }
                    link("ACME", "checkmark.seal", badge: store.stalledACME.count) { ACMEView() }
                    // Configuration backup is intentionally hidden for the
                    // first release. The implementation remains available for
                    // later hardening without exposing its sensitive export in
                    // the current navigation.
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(theme.bg.ignoresSafeArea())
    }

    private func group<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupHeading(text: title)
            content()
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
                    .scaledFont(15)
                    .foregroundStyle(theme.accentColor)
                    .scaledFrame(width: 24)
                Text(title)
                    .scaledFont(15, weight: .medium)
                    .foregroundStyle(theme.label)
                Spacer()
                if badge > 0 {
                    Text("\(badge)")
                        .scaledFont(11, weight: .bold, design: .rounded)
                        .foregroundStyle(theme.palette.crust)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(theme.bad)
                        .clipShape(Capsule())
                }
                Image(systemName: "chevron.right")
                    .scaledFont(12, weight: .semibold)
                    .foregroundStyle(theme.labelFaint)
            }
            .padding(14)
            .background(theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
