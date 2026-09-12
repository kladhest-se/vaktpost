import SwiftUI

/// View for reviewing and applying staged write operations.
///
/// Shows all pending changes collected from quick-block, service restart,
/// firewall reload, and state flush operations. The user can review, discard
/// individual changes, discard all, or apply them in a single batch.
struct StagedChangesView: View {

    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore
    @Environment(\.dismiss) private var dismiss

    @State private var showApplyConfirmation = false
    @State private var isApplying = false
    @State private var showErrorAlert = false
    @State private var writeError: WriteError?
    @State private var lastApplyTime: Date?

    var body: some View {
        NavigationStack {
            Group {
                if store.stagedChanges.changes.isEmpty {
                    emptyState
                } else {
                    changeList
                }
            }
            .navigationTitle("Staged changes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if !isApplying {
                        Button("Done") { dismiss() }
                    } else {
                        ProgressView()
                    }
                }
                if !store.stagedChanges.changes.isEmpty {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Discard all") {
                            store.stagedChanges.discardAll()
                        }
                    }
                }
            }
            .confirmationSheet(
                isPresented: $showApplyConfirmation,
                title: "Apply staged changes",
                message: store.stagedChanges.summary,
                destructive: true,
                destructiveLabel: "Apply all",
                confirmLabel: "Cancel",
                onConfirm: applyStagedChanges,
                onCancel: {}
            )
            .writeErrorAlert(isErrorPresented: $showErrorAlert, error: $writeError)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal")
                .scaledFont(40)
                .foregroundStyle(theme.ok)
            Text("No staged changes")
                .scaledFont(15, weight: .semibold)
                .foregroundStyle(theme.label)
            Text("Use quick-block, service manager, or reload firewall to stage changes.")
                .scaledFont(13)
                .foregroundStyle(theme.labelMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Change list

    private var changeList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Change")
                            .scaledFont(12, weight: .semibold)
                            .foregroundStyle(theme.labelMuted)
                        Spacer()
                        Text("Time")
                            .scaledFont(12, weight: .semibold)
                            .foregroundStyle(theme.labelMuted)
                            .frame(width: 80, alignment: .trailing)
                    }

                    ForEach(store.stagedChanges.changes) { change in
                        changeRow(change)
                    }
                }
                .padding(16)
                .background(theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                applyButton
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 28)
        }
        .background(theme.bg.ignoresSafeArea())
    }

    private func changeRow(_ change: StagedChanges.Change) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(change.summary)
                    .scaledFont(14, weight: .medium)
                    .foregroundStyle(theme.label)
                Text(change.description)
                    .scaledFont(12)
                    .foregroundStyle(theme.labelMuted)
            }

            Spacer()

            Text(change.timestamp, style: .time)
                .scaledFont(11)
                .foregroundStyle(theme.labelMuted)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(10)
        .background(theme.bgSunken, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture {
            store.stagedChanges.discard(change)
        }
    }

    // MARK: - Apply button

    private var applyButton: some View {
        Button {
            writeError = nil
            isApplying = true
            defer { isApplying = false }

            if !store.rateLimiter.allowWrite() {
                writeError = WriteError(
                    title: "Rate limited",
                    message: "Please wait a few seconds between actions.",
                    suggestion: nil
                )
                showErrorAlert = true
                return
            }

            showApplyConfirmation = true
        } label: {
            HStack {
                Spacer()
                Text("Apply \(store.stagedChanges.count) change\(store.stagedChanges.count == 1 ? "" : "s")")
                Image(systemName: "checkmark.seal")
            }
            .foregroundStyle(theme.ok)
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(theme.ok.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    // MARK: - Apply handler

    private func applyStagedChanges() async {
        let changes = store.stagedChanges.changes
        var successes = 0
        var failures: [String] = []

        for change in changes {
            do {
                switch change.action {
                case "quick_block":
                    guard let target = change.target else { continue }
                    let parts = target.split(separator: " ")
                    guard parts.count >= 2 else { continue }
                    let address = String(parts[0])
                    let interface = String(parts[1])
                    let retrier = Retrier(maxAttempts: 2, baseDelay: 1.0)
                    _ = try await retrier.retry {
                        try await store.client.quickBlock(interface: interface, address: address, description: change.description)
                    }
                    successes += 1

                case "restart_service":
                    guard let service = change.target else { continue }
                    let retrier = Retrier(maxAttempts: 2, baseDelay: 1.0)
                    _ = try await retrier.retry {
                        try await store.client.restartService(named: service)
                    }
                    successes += 1

                case "reload_firewall":
                    let retrier = Retrier(maxAttempts: 2, baseDelay: 1.0)
                    _ = try await retrier.retry {
                        try await store.client.reloadFirewall()
                    }
                    successes += 1

                case "flush_states":
                    guard let interface = change.target else { continue }
                    let retrier = Retrier(maxAttempts: 2, baseDelay: 1.0)
                    _ = try await retrier.retry {
                        try await store.client.flushStates(interface: interface)
                    }
                    successes += 1

                default:
                    failures.append("Unknown action: \(change.action)")
                }
            } catch {
                let writeError = WriteError.from(error, operation: .other)
                failures.append("\(change.description): \(writeError.message)")
            }

            // Brief pause between operations to avoid overwhelming the firewall
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        // Log batch apply to audit trail
        let summary = "Applied \(successes) staged change\(successes == 1 ? "" : "s")"
        store.auditTrail.log(
            action: .other,
            summary: summary,
            target: nil,
            before: nil,
            after: failures.isEmpty ? "all success" : "\(successes) success, \(failures.count) failed"
        )

        // Record batch apply analytics
        store.analytics.record(operation: "batch_apply", success: failures.isEmpty)

        lastApplyTime = Date()

        if !failures.isEmpty {
            writeError = WriteError(
                title: "\(failures.count) change(s) failed",
                message: failures.joined(separator: "\n"),
                suggestion: "Check the firewall logs for details about the failed operations."
            )
            showErrorAlert = true
        }

        store.stagedChanges.clear()
        await store.refresh()
    }
}
