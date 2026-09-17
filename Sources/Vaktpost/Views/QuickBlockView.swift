import SwiftUI

/// Quick-block an IP address on a specific interface.
///
/// Presents a form that collects the target interface, address, and optional
/// description, then saves a staged rule for the Apply Changes screen.
struct QuickBlockView: View {

    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedInterface: InterfaceStat?
    @State private var address = ""
    @State private var description = ""
    @State private var isExecuting = false
    @State private var showErrorAlert = false
    @State private var writeError: WriteError?

    /// `prefillDescription` exists alongside `prefillAddress` so a caller
    /// that already knows *why* it's suggesting a block — a repeated
    /// source in the incident timeline, say — can leave that reason on the
    /// rule itself, rather than the description defaulting to blank and
    /// the context only existing in whatever screen suggested this in the
    /// first place.
    /// Whether this screen closes itself with Done. True when a caller
    /// presents it as a sheet; false when it is pushed, where the back button
    /// does that job and a Done button would just be a second back button.
    private let showsDoneButton: Bool

    init(prefillAddress: String? = nil, prefillDescription: String? = nil,
         showsDoneButton: Bool = false) {
        self.showsDoneButton = showsDoneButton
        _address = State(initialValue: prefillAddress ?? "")
        _description = State(initialValue: prefillDescription ?? "")
    }

    var body: some View {
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
        .navigationTitle("Quick Block")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isExecuting)
        .interactiveDismissDisabled(isExecuting)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isExecuting {
                    ProgressView()
                } else if showsDoneButton {
                    Button("Done") { dismiss() }
                }
            }
        }
        .writeErrorAlert(isErrorPresented: $showErrorAlert, error: $writeError)
        .onAppear {
            if let firstUp = store.overviewLayout.interfaces.first(where: {
                $0.isUp && $0.internalName != nil
            }) {
                selectedInterface = firstUp
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
            Task { await confirmBlock() }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "shield.slash")
                Text("Add block rule")
            }
            .foregroundStyle(.white)
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(theme.bad, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!store.canAdminister || isExecuting || addressProblem != nil
                  || selectedInterface?.internalName == nil)
        .opacity(store.canAdminister && addressProblem == nil
                 && selectedInterface?.internalName != nil ? 1 : 0.55)
    }

    // MARK: - Save handler

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
            await store.refreshFirewallObjectsAfterWrite()
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
