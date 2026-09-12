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

    var body: some View {
        NavigationStack {
            Form {
                sectionHeader("Target")

                flushScopePicker

                interfacePicker

                sectionHeader("Mode")

                AdministrationModeNotice()

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
                message: store.writeCoordinator.preview(for: pendingOperation),
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

    private var executeButton: some View {
        Button {
            writeError = nil

            if !flushAll && selectedInterface == nil {
                writeError = WriteError(
                    title: "Invalid selection",
                    message: "Select an interface or flush all.",
                    suggestion: nil
                )
                showErrorAlert = true
                return
            }

            showConfirmation = true
        } label: {
            HStack {
                Spacer()
                Text("Flush states")
                Image(systemName: "trash")
            }
            .foregroundStyle(theme.bad)
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(theme.bad.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        }
        .disabled(!store.canAdminister || isExecuting)
        .opacity(store.canAdminister ? 1 : 0.55)
    }

    private var flushMessage: String {
        if flushAll {
            return "This will flush all firewall state entries. All active connections will be dropped."
        } else {
            return "This will flush firewall states on \(selectedInterface?.device ?? "the interface"). Active connections on this interface will be dropped."
        }
    }

    private var pendingOperation: AdministrativeWrite {
        .flushStates(interface: flushAll ? "" : (selectedInterface?.device ?? ""))
    }

    // MARK: - Flush handler

    private func confirmFlush() async {
        // Set around the write, not around opening the sheet.
        // It was set and cleared by a `defer` in the button's own
        // closure, which only raised the confirmation — so the flag
        // was never observed true and the button never showed that
        // anything was happening.
        isExecuting = true
        defer { isExecuting = false }

        do {
            _ = try await store.writeCoordinator.execute(pendingOperation)
            lastFlushTime = Date()
            await store.refresh()
        } catch {
            writeError = WriteError.from(error, operation: .flushStates)
            showErrorAlert = true
        }
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
