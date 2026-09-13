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

                    AdministrationModeNotice()

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
                message: store.writeCoordinator.preview(for: .reloadFirewall),
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
                        Text("Apply Changes")
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .foregroundStyle(theme.warn)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(theme.warn.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .disabled(isReloading || !store.canAdminister)
            .opacity(store.canAdminister ? 1 : 0.55)

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
        isReloading = true
        defer { isReloading = false }

        do {
            _ = try await store.writeCoordinator.execute(.reloadFirewall)
            lastReloadTime = Date()
            reloadCount += 1

            await store.refresh()
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
