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
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    GroupHeading(text: "Target")
                    Slab(rail: .info) {
                        VStack(alignment: .leading, spacing: 12) {
                            flushScopePicker
                            interfacePicker
                        }
                    }

                    if !store.canAdminister {
                        GroupHeading(text: "Mode")
                        AdministrationModeNotice()
                    }

                    GroupHeading(text: "Action")
                    executeButton
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
                .readableWidth()
            }
            .background(theme.bg.ignoresSafeArea())
            .tint(theme.accentColor)
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
                onConfirm: confirmFlush
            ) {}
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
        VStack(alignment: .leading, spacing: 4) {
            fieldLabel("Flush scope")
            Picker("", selection: $flushAll) {
                Text("All interfaces").tag(true)
                Text("Specific interface").tag(false)
            }
            .pickerStyle(.segmented)
        }
    }

    private var interfacePicker: some View {
        Group {
            if !flushAll {
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("Interface")
                    Menu {
                        ForEach(store.overviewLayout.interfaces) { iface in
                            Button {
                                selectedInterface = iface
                            } label: {
                                if selectedInterface?.device == iface.device {
                                    Label("\(iface.name) (\(iface.device))", systemImage: "checkmark")
                                } else {
                                    Text("\(iface.name) (\(iface.device))")
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text(selectedInterface.map { "\($0.name) (\($0.device))" } ?? "Select interface…")
                                .scaledFont(14, design: .monospaced)
                                .foregroundStyle(selectedInterface == nil ? theme.labelFaint : theme.label)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .scaledFont(11, weight: .semibold)
                                .foregroundStyle(theme.accentColor)
                        }
                        .padding(10)
                        .background(theme.cardRaised)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
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
            HStack(spacing: 9) {
                Image(systemName: "trash")
                Text("Flush states")
            }
            .foregroundStyle(.white)
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(theme.bad, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!store.canAdminister || isExecuting)
        .opacity(store.canAdminister ? 1 : 0.55)
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

    private func fieldLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .scaledFont(11, weight: .semibold)
            .tracking(0.8)
            .foregroundStyle(theme.labelFaint)
    }
}
