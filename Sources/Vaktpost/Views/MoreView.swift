import SwiftUI

/// Five tabs is the practical ceiling before iOS collapses the bar into its own
/// "More" list, so the less-frequent destinations live behind one here instead.
struct MoreView: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore
    @Environment(\.serverRegistry) private var registry: ServerRegistry

    var body: some View {
        ScrollView {
            PageHeader(title: "More", subtitle: nil)
            // No headings.
            //
            // "Sections" labelled the only group on the screen, and "Setup"
            // was left standing over nothing once Settings and Firewalls moved
            // to the toolbar and the server menu. A heading that names
            // everything below it names nothing.
            VStack(alignment: .leading, spacing: 10) {
                link("Diagnostics", "stethoscope", badge: store.errors.isEmpty ? 0 : store.errors.count) { DiagnosticsView() }
                link("Quick Block", "shield.slash", badge: 0) { QuickBlockView() }
                link("Analytics", "chart.bar", badge: 0) { AnalyticsView() }
                link("Service manager", "power", badge: store.overviewLayout.servicesDown.isEmpty ? 0 : store.overviewLayout.servicesDown.count) { ServiceManagerView() }
                link("Reload firewall", "arrow.clockwise", badge: 0) { FirewallReloadView() }
                link("Flush states", "trash", badge: 0) { FlushStatesView() }
                link("Incident timeline", "point.3.connected.trianglepath.dotted", badge: 0) { IncidentTimelineView() }
                link("Alerts", "bell.badge", badge: store.alertManager.criticalAlertCount) { AlertsView() }
                link("VPN", "lock.shield", badge: 0) { VPNView() }
                link("Firewall", "shield.lefthalf.filled", badge: 0) { FirewallView() }
                link("Dynamic DNS", "globe", badge: store.overviewLayout.staleDyndns.count) { DyndnsView() }
                link("HAProxy", "arrow.triangle.swap", badge: store.unmonitoredBackends.count) { HAProxyView() }
                link("Investigate", "magnifyingglass", badge: 0) { InvestigateView() }
                link("Conflicts", "exclamationmark.triangle", badge: store.conflictCount) { ConflictsView() }
                link("pfBlockerNG", "shield.lefthalf.filled.badge.checkmark", badge: 0) { PFBlockerView() }
                link("Aliases", "tag", badge: 0) { AliasesView() }
                link("System Certificates", "lock.doc", badge: store.expiringCertificateCount) { CertificatesView() }
                link("ACME Certificates", "checkmark.seal", badge: store.stalledACME.count) { ACMEView() }
                link("System", "server.rack", badge: 0) { SystemView() }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(theme.bg.ignoresSafeArea())
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
