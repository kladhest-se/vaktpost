import SwiftUI

/// View for reloading the firewall ruleset.
///
/// This screen is itself the review and confirmation step: it shows the
/// pending changes and provides one explicit action to load them.
struct FirewallReloadView: View {

    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore
    @Environment(\.dismiss) private var dismiss

    @State private var isReloading = false
    @State private var showErrorAlert = false
    @State private var writeError: WriteError?
    @State private var lastReloadTime: Date?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                statusCard

                pendingChangesSection

                AdministrationModeNotice()

                applyButton

                historySection
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationTitle("Apply firewall changes")
        .navigationBarTitleDisplayMode(.inline)
        .writeErrorAlert(isErrorPresented: $showErrorAlert, error: $writeError)
        .task { await store.refresh() }
        .refreshable {
            await store.refresh()
        }
    }

    // MARK: - Pending changes

    private var pendingVaktpostChanges: [AuditTrail.Entry] {
        guard store.firewallChangesPending else { return [] }
        return store.auditTrail.entries.filter { entry in
            isStagedFirewallChange(entry.action)
                && isSuccessful(entry)
                && entry.timestamp > latestSuccessfulApply
        }
    }

    private var latestSuccessfulApply: Date {
        store.auditTrail.entries
            .last(where: { $0.action == .reloadFirewall && isSuccessful($0) })
            .map { $0.completedAt ?? $0.timestamp }
            ?? .distantPast
    }

    private func isSuccessful(_ entry: AuditTrail.Entry) -> Bool {
        entry.verification == .verified || entry.verification == .readBack
    }

    private func isStagedFirewallChange(_ action: AuditAction) -> Bool {
        switch action {
        case .addRule, .editRule, .deleteRule, .reorderRules,
             .addSeparator, .editSeparator, .deleteSeparator,
             .addPortForward, .editPortForward, .deletePortForward,
             .addAlias, .editAlias, .deleteAlias, .quickBlock:
            return true
        default:
            return false
        }
    }

    @ViewBuilder
    private var pendingChangesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Changes to apply")
                    .scaledFont(12, weight: .semibold)
                    .foregroundStyle(theme.labelMuted)
                Spacer()
                if !pendingVaktpostChanges.isEmpty {
                    Text("\(pendingVaktpostChanges.count)")
                        .scaledFont(11, weight: .bold, design: .monospaced)
                        .foregroundStyle(theme.warn)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                if !store.firewallChangesPending {
                    pendingMessage(icon: "checkmark.circle.fill",
                                   title: "Everything is active",
                                   detail: "pfSense reports no filter, NAT, or alias changes waiting.",
                                   color: theme.ok)
                } else if pendingVaktpostChanges.isEmpty {
                    pendingMessage(icon: "questionmark.circle",
                                   title: "Pending pfSense changes",
                                   detail: "These changes were made in the pfSense web UI, by another administrator, or before Vaktpost's retained audit history. pfSense does not expose an itemised pending-change list.",
                                   color: theme.warn)
                } else {
                    ForEach(Array(pendingVaktpostChanges.enumerated()), id: \.element.id) { index, entry in
                        pendingChangeRow(entry)
                        if index < pendingVaktpostChanges.count - 1 {
                            Divider().overlay(theme.hairline)
                        }
                    }

                    Text("The pfSense pending marker is global. Additional web UI or administrator changes may be included when this ruleset is applied.")
                        .scaledFont(11)
                        .foregroundStyle(theme.labelFaint)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }
            }
            .background(theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func pendingChangeRow(_ entry: AuditTrail.Entry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon(for: entry.action))
                .scaledFont(12, weight: .semibold)
                .foregroundStyle(theme.warn)
                .frame(width: 20, height: 20)
                .background(theme.warn.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.summary)
                    .scaledFont(13, weight: .medium)
                    .foregroundStyle(theme.label)
                if let target = entry.target, !target.isEmpty {
                    Text(target)
                        .scaledFont(11, design: .monospaced)
                        .foregroundStyle(theme.labelMuted)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            Text(entry.timestamp, style: .time)
                .scaledFont(10, design: .monospaced)
                .foregroundStyle(theme.labelFaint)
        }
        .padding(12)
    }

    private func pendingMessage(icon: String, title: String, detail: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .scaledFont(15)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .scaledFont(13, weight: .semibold)
                Text(detail)
                    .scaledFont(12)
                    .foregroundStyle(theme.labelMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
    }

    private func icon(for action: AuditAction) -> String {
        switch action {
        case .addRule, .addPortForward, .addAlias, .quickBlock: return "plus"
        case .editRule, .editPortForward, .editAlias: return "pencil"
        case .deleteRule, .deletePortForward, .deleteAlias: return "trash"
        case .reorderRules: return "arrow.up.arrow.down"
        case .addSeparator, .editSeparator, .deleteSeparator: return "rectangle.split.1x2"
        default: return "circle"
        }
    }

    // MARK: - Status card

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "shield.checkered")
                    .scaledFont(16)
                    .foregroundStyle(theme.info)
                Text("Current ruleset")
                    .scaledFont(15, weight: .semibold)
            }

            HStack(spacing: 0) {
                rulesetMetric("Rules", store.rules.count)
                Divider().overlay(theme.hairline)
                rulesetMetric("Forwards", store.portForwards.count)
                Divider().overlay(theme.hairline)
                rulesetMetric("Aliases", store.aliases.count)
            }
        }
        .padding(16)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func rulesetMetric(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 3) {
            Text("\(value)")
                .scaledFont(16, weight: .semibold, design: .monospaced)
                .foregroundStyle(theme.label)
            Text(label)
                .scaledFont(10, weight: .medium)
                .foregroundStyle(theme.labelMuted)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Apply action

    private var applyButton: some View {
        VStack(spacing: 9) {
            Button {
                writeError = nil
                Task { await confirmReload() }
            } label: {
                HStack(spacing: 9) {
                    if isReloading {
                        ProgressView()
                            .progressViewStyle(.circular)
                        Text("Applying…")
                    } else {
                        Image(systemName: store.firewallChangesPending ? "arrow.clockwise" : "checkmark")
                        Text(store.firewallChangesPending ? "Apply Changes" : "No changes to apply")
                    }
                }
                .foregroundStyle(.white)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(theme.accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isReloading || !store.canAdminister || !store.firewallChangesPending)
            .opacity(store.canAdminister && store.firewallChangesPending ? 1 : 0.55)

            if let lastTime = lastReloadTime {
                HStack {
                    Image(systemName: "checkmark.circle")
                        .scaledFont(12)
                        .foregroundStyle(theme.ok)
                    Text("Last applied: \(formatDate(lastTime))")
                        .scaledFont(12)
                        .foregroundStyle(theme.labelMuted)
                }
            }
        }
    }

    // MARK: - History section

    @ViewBuilder
    private var historySection: some View {
        if !recentApplies.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Recent applies")
                    .scaledFont(12, weight: .semibold)
                    .foregroundStyle(theme.labelMuted)

                ForEach(recentApplies.reversed()) { entry in
                    auditRow(entry)
                }
            }
        }
    }

    private var recentApplies: [AuditTrail.Entry] {
        Array(store.auditTrail.entries.filter { $0.action == .reloadFirewall }.suffix(3))
    }

    private func auditRow(_ entry: AuditTrail.Entry) -> some View {
        HStack {
            Image(systemName: "arrow.clockwise")
                .scaledFont(12)
                .foregroundStyle(theme.labelMuted)
            Text(entry.summary)
                .scaledFont(13)
                .foregroundStyle(theme.label)
            Spacer()
            Text(entry.timestamp, style: .time)
                .scaledFont(11)
                .foregroundStyle(theme.labelMuted)
        }
        .padding(10)
        .background(theme.bgSunken, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Reload handler

    private func confirmReload() async {
        isReloading = true
        defer { isReloading = false }

        do {
            _ = try await store.writeCoordinator.execute(.reloadFirewall)
            lastReloadTime = Date()
            await store.refreshFirewallObjectsAfterWrite()
            // The review has served its purpose once pfSense confirms that
            // nothing remains staged. Keep it open if a concurrent WebUI or
            // administrator change left the global dirty marker set.
            if !store.firewallChangesPending {
                dismiss()
            }
        } catch {
            writeError = WriteError.from(error, operation: .reloadFirewall)
            showErrorAlert = true
        }
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
