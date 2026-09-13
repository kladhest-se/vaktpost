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
            Form {
                sectionHeader("Target")

                interfacePicker

                addressField

                descriptionField

                sectionHeader("Mode")

                AdministrationModeNotice()

                sectionHeader("Action")

                executeButton
            }
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
        LabeledContent("Interface") {
            Picker("", selection: Binding(
                get: { selectedInterface?.internalName ?? "" },
                set: { newValue in
                    selectedInterface = store.overviewLayout.interfaces.first {
                        $0.internalName == newValue
                    }
                }
            )) {
                Text("Select interface...").tag("")
                ForEach(store.overviewLayout.interfaces) { iface in
                    if let key = iface.internalName {
                        Text("\(iface.name) (\(key))")
                            .tag(key)
                            .foregroundStyle(iface.isUp ? theme.label : theme.labelMuted)
                    }
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity)
        }
    }

    private var addressField: some View {
        VStack(alignment: .leading, spacing: 5) {
            LabeledContent("Address") {
                TextField("IPv4, IPv6, or CIDR network", text: $address)
                    .keyboardType(.asciiCapable)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
            }
            if let problem = addressProblem, !address.isEmpty {
                Text(problem.message)
                    .scaledFont(11)
                    .foregroundStyle(theme.bad)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var descriptionField: some View {
        LabeledContent("Description") {
            TextField("Blocked by Vaktpost", text: $description)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
        }
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
            await store.refresh()
            dismiss()
        } catch {
            writeError = WriteError.from(error, operation: .quickBlock)
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
