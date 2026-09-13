import SwiftUI

/// View for reloading the firewall ruleset.
///
/// Provides a single action to reload the pf ruleset in place without
/// restarting services. The user must explicitly confirm before the
/// operation is executed, and the action is logged to the audit trail.
struct FirewallReloadView: View {

    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore
    @Environment(\.dismiss) private var dismiss

    @State private var showConfirmation = false
    @State private var isReloading = false
    @State private var showErrorAlert = false
    @State private var writeError: WriteError?
    @State private var lastReloadTime: Date?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    statusCard

                    AdministrationModeNotice()

                    pendingChangesSection

                    reloadCard

                    historySection
                }
                .padding(.horizontal, 16)
                .padding(.top, 24)
                .padding(.bottom, 28)
            }
            .background(theme.bg.ignoresSafeArea())
            .navigationTitle("Apply firewall changes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if !isReloading {
                        Button("Done") { dismiss() }
                    } else {
                        ProgressView()
                    }
                }
            }
            .confirmationSheet(
                isPresented: $showConfirmation,
                title: "Apply firewall changes",
                message: applyPreview,
                destructive: true,
                destructiveLabel: "Apply Changes",
                confirmLabel: "Cancel",
                onConfirm: confirmReload,
                onCancel: {}
            )
            .writeErrorAlert(isErrorPresented: $showErrorAlert, error: $writeError)
            .task { await store.refresh() }
            .refreshable {
                await store.refresh()
            }
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
             .addPortForward, .editPortForward, .deletePortForward, .quickBlock:
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
                                   detail: "pfSense reports no filter or NAT changes waiting.",
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
        case .addRule, .addPortForward, .quickBlock: return "plus"
        case .editRule, .editPortForward: return "pencil"
        case .deleteRule, .deletePortForward: return "trash"
        case .reorderRules: return "arrow.up.arrow.down"
        default: return "circle"
        }
    }

    private var applyPreview: String {
        var text = store.writeCoordinator.preview(for: .reloadFirewall)
        if !pendingVaktpostChanges.isEmpty {
            text += "\n\nVaktpost changes since the last apply:"
            for entry in pendingVaktpostChanges {
                text += "\n• \(entry.summary)"
            }
        }
        text += "\n\nThis applies pfSense's complete pending ruleset, which may also contain changes made outside Vaktpost."
        return text
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

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Loaded rules")
                        .scaledFont(13)
                        .foregroundStyle(theme.labelMuted)
                    Spacer()
                    Text("\(store.rules.count)")
                        .scaledFont(13, weight: .semibold)
                        .foregroundStyle(theme.label)
                }

                HStack {
                    Text("Port forwards")
                        .scaledFont(13)
                        .foregroundStyle(theme.labelMuted)
                    Spacer()
                    Text("\(store.portForwards.count)")
                        .scaledFont(13, weight: .semibold)
                        .foregroundStyle(theme.label)
                }

                HStack {
                    Text("Aliases")
                        .scaledFont(13)
                        .foregroundStyle(theme.labelMuted)
                    Spacer()
                    Text("\(store.aliases.count)")
                        .scaledFont(13, weight: .semibold)
                        .foregroundStyle(theme.label)
                }

                HStack {
                    Text("Pending changes")
                        .scaledFont(13)
                        .foregroundStyle(theme.labelMuted)
                    Spacer()
                    Text(store.firewallChangesPending ? "Waiting to be applied" : "None")
                        .scaledFont(13, weight: .semibold)
                        .foregroundStyle(store.firewallChangesPending ? theme.warn : theme.ok)
                }
            }
        }
        .padding(16)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Reload action card

    private var reloadCard: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                        .scaledFont(14)
                        .foregroundStyle(theme.warn)
                    Text("Apply Changes")
                        .scaledFont(14, weight: .semibold)
                }

                Text("Apply all pending filter and NAT changes saved on pfSense, including changes made in the web UI or by another administrator.")
                    .scaledFont(13)
                    .foregroundStyle(theme.labelMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                writeError = nil
                showConfirmation = true
            } label: {
                HStack {
                    if isReloading {
                        ProgressView()
                            .progressViewStyle(.circular)
                        Text("Applying…")
                    } else {
                        Spacer()
                        Text(store.firewallChangesPending ? "Apply Changes" : "No changes to apply")
                        Image(systemName: store.firewallChangesPending ? "arrow.clockwise" : "checkmark")
                    }
                }
                .foregroundStyle(theme.warn)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(theme.warn.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
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
        .padding(16)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        Array(store.auditTrail.entries.filter { $0.action == .reloadFirewall }.suffix(5))
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
