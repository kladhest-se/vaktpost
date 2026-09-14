import SwiftUI

// Split out of FirewallView.swift on size alone (file length). Each type
// here is fully independent of FirewallView itself — nothing was
// restructured, only relocated.

/// The four separator colours pfSense stores, mapped once to the exact colours
/// used by both the list bars and the editor swatches.
enum SeparatorDisplayColor: String, CaseIterable, Identifiable {
    case info, success, warning, danger

    var id: String { rawValue }
    var accessibilityName: String { rawValue.capitalized }

    static func canonical(_ stored: String) -> SeparatorDisplayColor {
        let value = stored.lowercased()
        if value.contains("success") { return .success }
        if value.contains("warning") { return .warning }
        if value.contains("danger") { return .danger }
        return .info
    }

    @MainActor
    func tint(in theme: ThemeManager) -> Color {
        switch self {
        case .info: return theme.info
        case .success: return theme.ok
        case .warning: return theme.warn
        case .danger: return theme.bad
        }
    }
}

/// One of pfSense's own grouping bars, drawn the way its list draws them.
struct SeparatorBar: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    let separator: RuleSeparator
    var showsDisclosure = false

    private var tint: Color {
        SeparatorDisplayColor.canonical(separator.colorName).tint(in: theme)
    }

    var body: some View {
        HStack {
            Text(separator.text.isEmpty ? "Separator" : separator.text)
                .scaledFont(12, weight: .semibold)
                .foregroundStyle(theme.label)
            Spacer()
            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .scaledFont(10, weight: .semibold)
                    .foregroundStyle(theme.labelFaint)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(tint.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// Editable representation of a filter-rule separator.
struct SeparatorEditForm: Equatable, Identifiable {
    var id: String { "\(isCreating ? "new" : "edit")-\(interface)-\(key)" }

    var interface: String
    var key: String
    var text: String
    var color: String
    /// Number of rules before the separator. Zero means before the first.
    var position: Int
    var isCreating: Bool

    static func blank(interface: String, position: Int) -> SeparatorEditForm {
        SeparatorEditForm(
            interface: interface,
            key: "",
            text: "",
            color: "info",
            position: max(0, position),
            isCreating: true
        )
    }

    init(from separator: RuleSeparator) {
        interface = separator.interfaceName ?? ""
        key = separator.key
        text = separator.text
        color = Self.canonicalColor(separator.colorName)
        position = max(0, separator.precedingRuleCount ?? 0)
        isCreating = false
    }

    private init(interface: String, key: String, text: String, color: String,
                 position: Int, isCreating: Bool) {
        self.interface = interface
        self.key = key
        self.text = text
        self.color = color
        self.position = position
        self.isCreating = isCreating
    }

    func toDict() -> JSONDict {
        JSONDict([
            "interface": .string(interface),
            "key": .string(key),
            "text": .string(text.trimmingCharacters(in: .whitespacesAndNewlines)),
            "color": .string(color),
            "position": .number(Double(position)),
            "create": .bool(isCreating)
        ])
    }

    private static func canonicalColor(_ stored: String) -> String {
        SeparatorDisplayColor.canonical(stored).rawValue
    }
}

enum SeparatorScope: Equatable {
    case filter
    case nat
}

/// One filter or NAT separator, with the same edit/delete flow as a rule.
struct SeparatorDetailView: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore
    @Environment(\.dismiss) private var dismiss

    let separator: RuleSeparator
    let scope: SeparatorScope

    @State private var editorForm: SeparatorEditForm?
    @State private var isSaving = false
    @State private var showErrorAlert = false
    @State private var writeError: WriteError?

    private var separatorInterface: String { separator.interfaceName ?? "" }

    private var separatorInterfaceRules: [FirewallRule] {
        store.rules.filter { !$0.isFloating && $0.interfaceName == separatorInterface }
    }

    private var positionLabel: String {
        let position = separator.precedingRuleCount ?? 0
        guard position > 0 else { return "Before the first rule" }
        switch scope {
        case .filter:
            guard separatorInterfaceRules.indices.contains(position - 1) else {
                return "After rule \(position)"
            }
            let preceding = separatorInterfaceRules[position - 1]
            let name = preceding.descr.isEmpty ? "rule \(position)" : preceding.descr
            return "After \(name)"
        case .nat:
            guard store.portForwards.indices.contains(position - 1) else {
                return "After port forward \(position)"
            }
            let preceding = store.portForwards[position - 1]
            let name = preceding.descr.isEmpty ? "port forward \(position)" : preceding.descr
            return "After \(name)"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SeparatorBar(separator: separator)

                GroupHeading(text: "Separator")
                Slab(rail: .info) {
                    VStack(alignment: .leading, spacing: 4) {
                        FieldRow(key: "Label", value: separator.text, mono: false)
                        FieldRow(key: "Color", value: separator.colorName.capitalized, mono: false)
                        if scope == .filter {
                            FieldRow(
                                key: "Interface",
                                value: store.interfaceLabel(for: separatorInterface) ?? separatorInterface
                            )
                        } else {
                            FieldRow(key: "Table", value: "NAT port forwards", mono: false)
                        }
                        FieldRow(key: "Position", value: positionLabel, mono: false)
                        FieldRow(key: "Key", value: separator.key)
                    }
                }

                AdministrationModeNotice()

                if !isSaving {
                    VStack(spacing: 8) {
                        Button {
                            editorForm = SeparatorEditForm(from: separator)
                        } label: {
                            Label("Edit Separator", systemImage: "pencil")
                                .scaledFont(14, weight: .medium)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(theme.accentColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            Task { await deleteSeparator() }
                        } label: {
                            Label("Delete Separator", systemImage: "trash")
                                .scaledFont(14, weight: .medium)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.red, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .disabled(!store.canAdminister)
                    .opacity(store.canAdminister ? 1 : 0.55)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationTitle(separator.text.isEmpty ? "Separator" : separator.text)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editorForm) { form in
            if scope == .filter {
                SeparatorEditSheet(
                    form: form,
                    rules: separatorInterfaceRules
                ) { saved in try await save(changes: saved) }
            } else {
                SeparatorEditSheet(
                    form: form,
                    forwards: store.portForwards
                ) { saved in try await save(changes: saved) }
            }
        }
        .writeErrorAlert(isErrorPresented: $showErrorAlert, error: $writeError)
    }

    private func save(changes: SeparatorEditForm) async throws {
        switch scope {
        case .filter:
            _ = try await store.writeCoordinator.execute(
                .saveFilterSeparator(separator: changes.toDict(), displayName: separator.text)
            )
        case .nat:
            _ = try await store.writeCoordinator.execute(
                .saveNatSeparator(separator: changes.toDict(), displayName: separator.text)
            )
        }
        await store.refreshFirewallObjectsAfterWrite()
    }

    private func deleteSeparator() async {
        isSaving = true
        defer { isSaving = false }

        do {
            switch scope {
            case .filter:
                _ = try await store.writeCoordinator.execute(
                    .deleteFilterSeparator(
                        interface: separatorInterface,
                        key: separator.key,
                        displayName: separator.text.isEmpty ? separator.key : separator.text
                    )
                )
            case .nat:
                _ = try await store.writeCoordinator.execute(
                    .deleteNatSeparator(
                        key: separator.key,
                        displayName: separator.text.isEmpty ? separator.key : separator.text
                    )
                )
            }
            dismiss()
            await store.refreshFirewallObjectsAfterWrite()
        } catch {
            writeError = WriteError.from(error, operation: .other)
            showErrorAlert = true
        }
    }
}

/// Add or edit a filter separator without activating the pending ruleset.
struct SeparatorEditSheet: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dismiss) private var dismiss

    let positionLabels: [String]
    let firstPositionLabel: String
    let onSave: (SeparatorEditForm) async throws -> Void
    /// Filter separators belong to one interface; NAT separators belong to
    /// the global NAT table and legitimately have no interface value.
    let requiresInterface: Bool

    @State private var edited: SeparatorEditForm
    @State private var isSaving = false
    @State private var showErrorAlert = false
    @State private var writeError: WriteError?

    private let original: SeparatorEditForm
    private let colors = SeparatorDisplayColor.allCases

    init(form: SeparatorEditForm, rules: [FirewallRule],
         onSave: @escaping (SeparatorEditForm) async throws -> Void) {
        requiresInterface = true
        firstPositionLabel = "Before the first rule"
        positionLabels = rules.enumerated().map { index, rule in
            let name = rule.descr.isEmpty ? "rule \(index + 1)" : rule.descr
            return index + 1 == rules.count ? "After \(name) (last)" : "After \(name)"
        }
        self.onSave = onSave
        var available = form
        available.position = min(max(0, form.position), rules.count)
        original = available
        _edited = State(initialValue: available)
    }

    init(form: SeparatorEditForm, forwards: [PortForward],
         onSave: @escaping (SeparatorEditForm) async throws -> Void) {
        requiresInterface = false
        firstPositionLabel = "Before the first port forward"
        positionLabels = forwards.enumerated().map { index, forward in
            let name = forward.descr.isEmpty ? "port forward \(index + 1)" : forward.descr
            return index + 1 == forwards.count ? "After \(name) (last)" : "After \(name)"
        }
        self.onSave = onSave
        var available = form
        available.position = min(max(0, form.position), forwards.count)
        original = available
        _edited = State(initialValue: available)
    }

    private var isDirty: Bool { edited.isCreating || edited != original }

    private var isValid: Bool {
        (!requiresInterface || !edited.interface.isEmpty)
            && !edited.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && colors.map(\.rawValue).contains(edited.color)
            && (0...positionLabels.count).contains(edited.position)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Slab(rail: .info, title: "Separator") {
                        VStack(alignment: .leading, spacing: 12) {
                            EditField(
                                label: "Label",
                                text: $edited.text,
                                prompt: "Name shown between rules",
                                mono: false
                            )
                            separatorColorSwatches
                        }
                    }

                    Slab(rail: .info, title: "Position") {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("", selection: $edited.position) {
                                Text(firstPositionLabel).tag(0)
                                ForEach(Array(positionLabels.enumerated()), id: \.offset) { index, label in
                                    Text(label)
                                        .tag(index + 1)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(theme.accentColor)
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Text("The position is checked against the current rules before saving.")
                                .scaledFont(10)
                                .foregroundStyle(theme.labelFaint)
                        }
                    }

                    Notice(
                        symbol: "clock.badge.checkmark",
                        title: "Saved as a pending firewall change",
                        detail: "Use Apply Changes on the Firewall screen when the complete ruleset is ready.",
                        health: .warn
                    )
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(theme.bg.ignoresSafeArea())
            .navigationTitle(edited.isCreating ? "New separator" : "Edit separator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task { await save() }
                        }
                        .disabled(!isDirty || !isValid)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
            .writeErrorAlert(isErrorPresented: $showErrorAlert, error: $writeError)
        }
    }

    /// A separator colour is a visual choice, so show the actual rendered
    /// colour instead of asking the user to translate pfSense's CSS names in
    /// a text menu. The fill opacity is deliberately identical to
    /// `SeparatorBar`; the selected outline and check are selection chrome,
    /// not a different preview colour.
    private var separatorColorSwatches: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("COLOR")
                .scaledFont(9, weight: .semibold)
                .foregroundStyle(theme.labelFaint)

            HStack(spacing: 12) {
                ForEach(colors) { option in
                    let tint = option.tint(in: theme)
                    let isSelected = edited.color == option.rawValue
                    Button {
                        edited.color = option.rawValue
                    } label: {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(tint.opacity(0.18))
                            .frame(width: 52, height: 52)
                            .overlay {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .stroke(tint, lineWidth: isSelected ? 3 : 1)
                            }
                            .overlay {
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .scaledFont(17, weight: .bold)
                                        .foregroundStyle(tint)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(option.accessibilityName) separator color")
                    .accessibilityValue(isSelected ? "Selected" : "Not selected")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func save() async {
        guard !isSaving, isDirty, isValid else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            try await onSave(edited)
            dismiss()
        } catch {
            writeError = WriteError.from(error, operation: .other)
            showErrorAlert = true
        }
    }
}
