import SwiftUI

/// View for restarting firewall services.
///
/// Lists all services reported by the firewall, shows their health, and
/// allows restarting any of them after a confirmation step.
struct ServiceManagerView: View {

    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore
    @Environment(\.dismiss) private var dismiss

    @State private var showRestartSheet = false
    @State private var targetService: ServiceStatus?
    @State private var isRestarting = false
    @State private var showErrorAlert = false
    @State private var writeError: WriteError?
    @State private var lastRestartedService: String?
    @State private var useStaging = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if store.services.isEmpty {
                        placeholder
                    } else {
                        serviceList
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(theme.bg.ignoresSafeArea())
            .navigationTitle("Services")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if !isRestarting {
                        Button("Done") { dismiss() }
                    } else {
                        ProgressView()
                    }
                }
            }
            .confirmationSheet(
                isPresented: $showRestartSheet,
                title: useStaging ? "Stage service restart" : "Restart service",
                message: useStaging
                    ? "This will stage a restart of \(targetService?.descr ?? targetService?.name ?? "the service") for batch apply."
                    : "This will restart \(targetService?.descr ?? targetService?.name ?? "the service").",
                destructive: useStaging,
                destructiveLabel: "Stage",
                confirmLabel: "Cancel",
                onConfirm: confirmRestart,
                onCancel: {}
            )
            .writeErrorAlert(isErrorPresented: $showErrorAlert, error: $writeError)
            .task { await store.refresh() }
            .refreshable {
                await store.refresh()
            }
        }
    }

    // MARK: - Content

    private var placeholder: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading services…")
                .scaledFont(13)
                .foregroundStyle(theme.labelMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var serviceList: some View {
        VStack(alignment: .leading, spacing: 10) {
            serviceHeader

            ForEach(store.services) { service in
                serviceRow(service)
            }
        }
    }

    private var serviceHeader: some View {
        HStack {
            Text("Service")
                .scaledFont(12, weight: .semibold)
                .foregroundStyle(theme.labelMuted)
            Spacer()
            Text("Status")
                .scaledFont(12, weight: .semibold)
                .foregroundStyle(theme.labelMuted)
                .frame(width: 90, alignment: .trailing)
        }
    }

    private func serviceRow(_ service: ServiceStatus) -> some View {
        let isRunning = service.running
        let canRestart = !isRestarting

        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(service.descr ?? service.name)
                        .scaledFont(14, weight: .medium)
                        .foregroundStyle(theme.label)
                    if let enabled = service.enabled {
                        Text(enabled ? "Enabled" : "Disabled")
                            .scaledFont(11)
                            .foregroundStyle(theme.labelMuted)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    StatusPill(
                        text: isRunning ? "running" : "stopped",
                        health: service.health
                    )

                    if lastRestartedService == service.name {
                        Text("restarted")
                            .scaledFont(10, weight: .semibold)
                            .foregroundStyle(theme.ok)
                    }

                    if store.stagedChanges.changes.contains(where: { $0.target == service.name && $0.action == "restart_service" }) {
                        Text("staged")
                            .scaledFont(10, weight: .semibold)
                            .foregroundStyle(theme.info)
                    }
                }
                .frame(width: 90)
            }
            .padding(.vertical, 10)

            if let last = store.services.last, service.id == last.id {
                Hairline()
            }
        }
        .onTapGesture {
            guard canRestart else { return }
            targetService = service
            showRestartSheet = true
        }
        .background(theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .opacity(canRestart ? 1 : 0.6)
    }

    // MARK: - Restart handler

    private func confirmRestart() async {
        guard let service = targetService else { return }

        isRestarting = true
        defer { isRestarting = false }

        if useStaging {
            stageRestart(service: service)
            return
        }

        if !store.rateLimiter.allowWrite() {
            writeError = WriteError(
                title: "Rate limited",
                message: "Please wait a few seconds between actions.",
                suggestion: nil
            )
            showErrorAlert = true
            return
        }

        let retrier = Retrier(maxAttempts: 2, baseDelay: 1.0)

        do {
            let status = try await retrier.retry {
                try await store.client.restartService(named: service.name)
            }

            let summary = "Restarted service \(service.name)"
            store.auditTrail.log(
                action: .restartService,
                summary: summary,
                target: service.name,
                before: nil,
                after: status
            )

            store.analytics.record(operation: "restart_service", success: true)

            lastRestartedService = service.name

            await store.refresh()

        } catch {
            store.analytics.record(operation: "restart_service", success: false)
            writeError = WriteError.from(error, operation: .restartService)
            showErrorAlert = true
        }
    }

    private func stageRestart(service: ServiceStatus) {
        let op = FirewallClient.stageRestartService(named: service.name)

        store.stagedChanges.stage(
            action: op.action,
            target: op.target,
            description: op.description
        )

        writeError = nil
    }
}
