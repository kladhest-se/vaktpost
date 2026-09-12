import SwiftUI

/// View for flushing the firewall state table.
///
/// Allows flushing all states or states on a specific interface. The user
/// must explicitly confirm before the operation is executed, and the action
/// is logged to the audit trail. Supports staging for batch apply.
struct FlushStatesView: View {

    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedInterface: InterfaceStat?
    @State private var flushAll = true
    @State private var showConfirmation = false
    @State private var isExecuting = false
    @State private var showErrorAlert = false
    @State private var writeError: WriteError?
    @State private var lastFlushTime: Date?
    @State private var useStaging = false

    var body: some View {
        NavigationStack {
            Form {
                sectionHeader("Target")

                flushScopePicker

                interfacePicker

                sectionHeader("Mode")

                stagingToggle

                sectionHeader("Action")

                executeButton
            }
            .navigationTitle("Flush states")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if !isExecuting {
                        Button("Done") { dismiss() }
                    } else {
                        ProgressView()
                    }
                }
            }
            .confirmationSheet(
                isPresented: $showConfirmation,
                title: "Flush state table",
                message: flushMessage,
                destructive: true,
                destructiveLabel: "Flush",
                confirmLabel: "Cancel",
                onConfirm: confirmFlush,
                onCancel: {}
            )
            .writeErrorAlert(isErrorPresented: $showErrorAlert, error: $writeError)
            .onAppear {
                if let firstUp = store.overviewLayout.interfaces.first(where: { $0.isUp }) {
                    selectedInterface = firstUp
                }
            }
        }
    }

    // MARK: - Form fields

    private var flushScopePicker: some View {
        LabeledContent("Flush scope") {
            Picker("", selection: $flushAll) {
                Text("All interfaces").tag(true)
                Text("Specific interface").tag(false)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: .infinity)
        }
    }

    private var interfacePicker: some View {
        Group {
            if !flushAll {
                LabeledContent("Interface") {
                    Picker("", selection: Binding(
                        get: { selectedInterface?.device ?? "" },
                        set: { newValue in selectedInterface = store.overviewLayout.interfaces.first(where: { $0.device == newValue }) }
                    )) {
                        Text("Select interface...").tag("")
                        ForEach(store.overviewLayout.interfaces) { iface in
                            Text("\(iface.name) (\(iface.device))")
                                .tag(iface.device)
                                .foregroundStyle(iface.isUp ? theme.label : theme.labelMuted)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var stagingToggle: some View {
        LabeledContent("Staging") {
            Toggle("", isOn: $useStaging)
                .labelsHidden()
        }
        .help(useStaging ? "Changes will be staged for batch apply" : "Tap to enable staging mode")
    }

    private var executeButton: some View {
        Button {
            writeError = nil
            isExecuting = true
            defer { isExecuting = false }

            if !flushAll && selectedInterface == nil {
                writeError = WriteError(
                    title: "Invalid selection",
                    message: "Select an interface or flush all.",
                    suggestion: nil
                )
                showErrorAlert = true
                return
            }

            if useStaging {
                stageFlush()
            } else {
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
            }
        } label: {
            HStack {
                Spacer()
                Text(useStaging ? "Stage flush" : "Flush states")
                Image(systemName: useStaging ? "square.badge.plus" : "trash")
            }
            .foregroundStyle(useStaging ? theme.info : theme.bad)
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(useStaging ? theme.info.opacity(0.1) : theme.bad.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var flushMessage: String {
        if flushAll {
            return "This will flush all firewall state entries. All active connections will be dropped."
        } else {
            return "This will flush firewall states on \(selectedInterface?.device ?? "the interface"). Active connections on this interface will be dropped."
        }
    }

    // MARK: - Flush handler

    private func confirmFlush() async {
        let interface = flushAll ? "" : (selectedInterface?.device ?? "")

        let retrier = Retrier(maxAttempts: 2, baseDelay: 1.0)

        do {
            let status = try await retrier.retry {
                try await store.client.flushStates(interface: interface)
            }

            let target = flushAll ? "all interfaces" : (selectedInterface?.device ?? "unknown")
            let summary = "Flushed states on \(target) (status: \(status))"

            store.auditTrail.log(
                action: .flushStates,
                summary: summary,
                target: target,
                before: nil,
                after: status
            )

            store.analytics.record(operation: "flush_states", success: true)

            lastFlushTime = Date()

        } catch {
            store.analytics.record(operation: "flush_states", success: false)
            writeError = WriteError.from(error, operation: .flushStates)
            showErrorAlert = true
        }
    }

    private func stageFlush() {
        let interface = flushAll ? "" : (selectedInterface?.device ?? "")

        let op = FirewallClient.stageFlushStates(interface: interface)

        store.stagedChanges.stage(
            action: op.action,
            target: op.target,
            description: op.description
        )

        writeError = nil
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .scaledFont(12, weight: .semibold)
            .foregroundStyle(theme.labelFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }
}
