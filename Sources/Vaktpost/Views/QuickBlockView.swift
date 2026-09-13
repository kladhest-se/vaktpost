import SwiftUI

/// Quick-block an IP address on a specific interface.
///
/// Presents a form that collects the target interface, address, and optional
/// description, then presents a confirmation sheet before writing the rule.
struct QuickBlockView: View {

    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedInterface: InterfaceStat?
    @State private var address = ""
    @State private var description = ""
    @State private var showConfirmation = false
    @State private var isExecuting = false
    @State private var showErrorAlert = false
    @State private var writeError: WriteError?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    GroupHeading(text: "Target")
                    Slab(rail: .info) {
                        VStack(alignment: .leading, spacing: 12) {
                            interfacePicker
                            addressField
                            descriptionField
                        }
                    }

                    GroupHeading(text: "Mode")
                    AdministrationModeNotice()

                    GroupHeading(text: "Action")
                    Slab(rail: .bad) { executeButton }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
                .readableWidth()
            }
            .background(theme.bg.ignoresSafeArea())
            .tint(theme.accentColor)
            .navigationTitle("Quick Block")
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
                title: "Block address",
                message: pendingOperation.map { store.writeCoordinator.preview(for: $0) },
                destructive: true,
                destructiveLabel: "Block",
                confirmLabel: "Cancel",
                onConfirm: confirmBlock,
                onCancel: {}
            )
            .writeErrorAlert(isErrorPresented: $showErrorAlert, error: $writeError)
            .onAppear {
                if let firstUp = store.overviewLayout.interfaces.first(where: {
                    $0.isUp && $0.internalName != nil
                }) {
                    selectedInterface = firstUp
                }
            }
        }
    }

    // MARK: - Form fields

    private var interfacePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldLabel("Interface")
            Menu {
                ForEach(store.overviewLayout.interfaces) { iface in
                    if let key = iface.internalName {
                        Button {
                            selectedInterface = iface
                        } label: {
                            if selectedInterface?.internalName == key {
                                Label("\(iface.name) (\(key))", systemImage: "checkmark")
                            } else {
                                Text("\(iface.name) (\(key))")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(selectedInterface.map {
                        "\($0.name) (\($0.internalName ?? "unknown"))"
                    } ?? "Select interface…")
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
            .disabled(store.overviewLayout.interfaces.allSatisfy { $0.internalName == nil })
        }
    }

    private var addressField: some View {
        VStack(alignment: .leading, spacing: 5) {
            LabelledField(title: "Address", text: $address,
                          placeholder: "IPv4, IPv6, or CIDR network",
                          keyboard: .asciiCapable, autocap: false)
            if let problem = addressProblem, !address.isEmpty {
                Text(problem.message)
                    .scaledFont(11)
                    .foregroundStyle(theme.bad)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var descriptionField: some View {
        LabelledField(title: "Description", text: $description,
                      placeholder: "Blocked by Vaktpost")
    }

    private var executeButton: some View {
        Button {
            writeError = nil
            guard addressProblem == nil, selectedInterface?.internalName != nil else { return }
            showConfirmation = true
        } label: {
            HStack {
                Spacer()
                Text("Add block rule")
                Image(systemName: "shield.slash")
            }
            .foregroundStyle(theme.bad)
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(theme.bad.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        }
        .disabled(!store.canAdminister || isExecuting || addressProblem != nil
                  || selectedInterface?.internalName == nil)
        .opacity(store.canAdminister && addressProblem == nil
                 && selectedInterface?.internalName != nil ? 1 : 0.55)
    }

    // MARK: - Confirmation handler

    private var pendingOperation: AdministrativeWrite? {
        guard let interface = selectedInterface?.internalName,
              addressProblem == nil else { return nil }
        let value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return .quickBlock(
            interface: interface,
            address: value,
            description: note.isEmpty ? "Blocked by Vaktpost" : note
        )
    }

    private var addressProblem: FieldValidator.Problem? {
        FieldValidator.quickBlockProblem(in: address)
    }

    private func confirmBlock() async {
        guard let operation = pendingOperation else { return }

        // Set around the write, not around opening the sheet.
        // It was set and cleared by a `defer` in the button's own
        // closure, which only raised the confirmation — so the flag
        // was never observed true and the button never showed that
        // anything was happening.
        isExecuting = true
        defer { isExecuting = false }

        do {
            _ = try await store.writeCoordinator.execute(operation)
            // Quick Block changes the ruleset. The ordinary lazy loader keeps
            // its cached result, so force the new rule into every screen
            // before this sheet closes.
            await store.loadFirewallObjects(force: true)
            await store.refresh()
            dismiss()
        } catch {
            writeError = WriteError.from(error, operation: .quickBlock)
            showErrorAlert = true
        }
    }


    private func fieldLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .scaledFont(11, weight: .semibold)
            .tracking(0.8)
            .foregroundStyle(theme.labelFaint)
    }
}
