import SwiftUI

/// A visible explanation beside mutation controls. The transport enforces the
/// same boundary; this view makes the reason disabled controls are disabled
/// understandable before somebody taps them.
struct AdministrationModeNotice: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore

    var body: some View {
        if !store.canAdminister {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "eye.fill")
                    .scaledFont(13)
                    .foregroundStyle(theme.ok)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Monitor-only mode")
                        .scaledFont(13, weight: .semibold)
                        .foregroundStyle(theme.label)
                    Text("No firewall change can be sent. To enable administration, open Firewalls, edit this firewall, and authenticate with Face ID or Touch ID.")
                        .scaledFont(11)
                        .foregroundStyle(theme.labelMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.ok.opacity(0.08), in: RoundedRectangle(cornerRadius: 10,
                                                                     style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }
}
