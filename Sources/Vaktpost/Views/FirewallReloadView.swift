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
    @State private var reloadCount = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    statusCard

                    reloadCard

                    historySection
                }
                .padding(.horizontal, 16)
                .padding(.top, 24)
                .padding(.bottom, 28)
            }
            .background(theme.bg.ignoresSafeArea())
            .navigationTitle("Reload firewall")
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
                title: "Reload firewall rules",
                message: "This will reload the firewall ruleset in place without restarting services. Active connections may be briefly interrupted.",
                destructive: true,
                destructiveLabel: "Reload",
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
                    Text("Reload ruleset")
                        .scaledFont(14, weight: .semibold)
                }

                Text("Apply pending configuration changes without restarting services. This reloads the pf ruleset in place.")
                    .scaledFont(13)
                    .foregroundStyle(theme.labelMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                writeError = nil
                isReloading = true
                defer { isReloading = false }

                if !store.rateLimiter.allowWrite() {
                    writeError = WriteError(
                        title: "Rate limited",
                        message: "Please wait a few seconds between actions.",
                        suggestion: nil
                    )
                    showErrorAlert = true
                    return
                }

                showConfirmation = true
            } label: {
                HStack {
                    if isReloading {
                        ProgressView()
                            .progressViewStyle(.circular)
                        Text("Reloading…")
                    } else {
                        Spacer()
                        Text("Reload now")
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .foregroundStyle(theme.warn)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(theme.warn.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .disabled(isReloading)

            if let lastTime = lastReloadTime {
                HStack {
                    Image(systemName: "checkmark.circle")
                        .scaledFont(12)
                        .foregroundStyle(theme.ok)
                    Text("Last reload: \(formatDate(lastTime))")
                        .scaledFont(12)
                        .foregroundStyle(theme.labelMuted)
                }
            }
        }
        .padding(16)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - History section

    private var historySection: some View {
        guard !store.auditTrail.entries.isEmpty else { return AnyView(Text("")) }

        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                Text("Recent reloads")
                    .scaledFont(12, weight: .semibold)
                    .foregroundStyle(theme.labelMuted)

                ForEach(store.auditTrail.entries.prefix(10).reversed()) { entry in
                    if entry.action == .reloadFirewall {
                        auditRow(entry)
                    }
                }
            }
        )
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
        let retrier = Retrier(maxAttempts: 2, baseDelay: 1.0)

        do {
            let status = try await retrier.retry {
                try await store.client.reloadFirewall()
            }

            let summary = "Reloaded firewall ruleset (status: \(status))"
            store.auditTrail.log(
                action: .reloadFirewall,
                summary: summary,
                target: nil,
                before: nil,
                after: status
            )

            store.analytics.record(operation: "reload_firewall", success: true)

            lastReloadTime = Date()
            reloadCount += 1

            await store.refresh()

        } catch {
            store.analytics.record(operation: "reload_firewall", success: false)
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
