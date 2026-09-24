import SwiftUI

// Split out of FirewallView.swift on size alone (file length). Each type
// here is fully independent of FirewallView itself — nothing was
// restructured, only relocated.

/// A port forward paired with its position in the freshly fetched flat NAT
/// table. The position is part of the transport identity, not the displayed
/// rule identity, so trackerless rules and otherwise identical rows can still
/// be moved without one being mistaken for another.
struct NatRuleListItem: Identifiable {
    let originalIndex: Int
    let forward: PortForward

    var id: String { "nat:\(originalIndex):\(forward.id)" }
    var reorderItem: FirewallClient.NatReorderItem {
        FirewallClient.NatReorderItem(originalIndex: originalIndex, forward: forward)
    }
}

/// A port forward or separator in pfSense's single flat NAT ordering.
enum NatListItem: Identifiable {
    case forward(NatRuleListItem)
    case separator(RuleSeparator)

    var id: String {
        switch self {
        case .forward(let item): return item.id
        case .separator(let separator): return "nat-separator:\(separator.key)"
        }
    }

    var reorderItem: FirewallClient.NatReorderItem {
        switch self {
        case .forward(let item): return item.reorderItem
        case .separator(let separator): return FirewallClient.NatReorderItem(separator: separator)
        }
    }
}

/// Builds the same mixed order pfSense renders: each separator position is
/// the count of port-forward rows preceding it.
func mergedNatList(forwards: [PortForward], separators: [RuleSeparator]) -> [NatListItem] {
    var items: [NatListItem] = []
    for (index, forward) in forwards.enumerated() {
        for separator in separators where separator.precedingRuleCount == index {
            items.append(.separator(separator))
        }
        items.append(.forward(NatRuleListItem(originalIndex: index, forward: forward)))
    }
    for separator in separators where (separator.precedingRuleCount ?? Int.max) >= forwards.count {
        items.append(.separator(separator))
    }
    return items
}

/// Rules and separators, in reading order, for one interface.
///
/// The one function both the live display and a drag's starting point build
/// from, so the two can never show a different order from each other. This
/// mirrors `WriteCoordinator.reorderTokens` on the write side — one on-disk
/// order, walked the same way wherever it needs to be read.
func mergedRuleList(rules: [FirewallRule], separators: [RuleSeparator]) -> [RuleListItem] {
    var items: [RuleListItem] = []
    for (index, rule) in rules.enumerated() {
        for separator in separators where separator.precedingRuleCount == index {
            items.append(.separator(separator))
        }
        items.append(.rule(rule))
    }
    for separator in separators where (separator.precedingRuleCount ?? Int.max) >= rules.count {
        items.append(.separator(separator))
    }
    return items
}

struct NatReorderDropDelegate: DropDelegate {
    let target: NatListItem
    @Binding var items: [NatListItem]
    @Binding var draggingID: String?

    func dropEntered(info: DropInfo) {
        guard let draggingID, draggingID != target.id,
              let from = items.firstIndex(where: { $0.id == draggingID }),
              let to = items.firstIndex(where: { $0.id == target.id }) else { return }
        withAnimation(Motion.animation(.default)) {
            items.move(fromOffsets: IndexSet(integer: from),
                       toOffset: to > from ? to + 1 : to)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

/// One port forward, in full.
struct PortForwardDetailView: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore
    @Environment(\.dismiss) private var dismiss
    let forward: PortForward
    @Binding var selection: String?

    /// The form the sheet opens with — an edit of this forward, or a copy.
    @State private var editorForm: PortForwardEditForm?
    @State private var isSaving = false
    @State private var showErrorAlert = false
    @State private var writeError: WriteError?

    @ViewBuilder
    private func detailField(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .scaledFont(9, weight: .semibold)
                .foregroundStyle(theme.labelFaint)
            ForEach(expandedValues(value), id: \.self) { entry in
                Text(entry)
                    .scaledFont(13, weight: .medium, design: .monospaced)
                    .foregroundStyle(theme.label)
                    .textSelection(.enabled)
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Slab(rail: forward.health,
                     trailing: store.interfaceLabel(for: forward.interfaceName)) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text((forward.proto ?? "any").uppercased())
                                .scaledFont(11, weight: .semibold, design: .monospaced)
                                .foregroundStyle(theme.labelMuted)
                            Spacer()
                            if forward.disabled { StatusPill(text: "disabled", health: .idle) }
                        }
                        if !forward.descr.isEmpty {
                            Text(forward.descr)
                                .scaledFont(14)
                                .foregroundStyle(theme.label)
                        }
                    }
                }

                GroupHeading(text: "Matches")
                Slab(rail: .info) {
                    VStack(alignment: .leading, spacing: 8) {
                        // Source is usually `any`; shown here regardless,
                        // because on a detail screen a field that is always
                        // the same is still worth confirming.
                        detailField("From", store.addressLabel(for: forward.sourceSide))
                        detailField("To", store.addressLabel(for: forward.destinationSide))
                        if let port = forward.destinationSide.port, !port.isEmpty {
                            detailField("Port", port)
                        }
                    }
                }

                GroupHeading(text: "Forwards to")
                Slab(rail: .ok) {
                    VStack(alignment: .leading, spacing: 8) {
                        detailField("Target", forward.target)
                        if let local = forward.localPort, !local.isEmpty {
                            detailField("Redirect target port", local)
                        }
                    }
                }

                AdministrationModeNotice()

                if !isSaving {
                    VStack(spacing: 8) {
                        Button {
                            editorForm = PortForwardEditForm(from: forward)
                        } label: {
                            Label("Edit Forward Rule", systemImage: "pencil")
                                .scaledFont(14, weight: .medium)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(theme.accentColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        // The copy opens in the editor and is not written
                        // until reviewed. Its destination port is cleared so
                        // it cannot accidentally conflict with the original.
                        Button {
                            editorForm = PortForwardEditForm.duplicating(forward)
                        } label: {
                            Label("Duplicate Forward Rule", systemImage: "plus.square.on.square")
                                .scaledFont(14, weight: .medium)
                                .foregroundStyle(theme.accentColor)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(theme.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            Task { await confirmDelete() }
                        } label: {
                            Label("Delete Forward Rule", systemImage: "trash")
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
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationTitle(forward.descr.isEmpty ? "Port forward" : forward.descr)
        .navigationBarTitleDisplayMode(.inline)
        // Same as the rule editor: assembled at presentation, because there is
        // nothing to fetch and the spinner was the entire delay.
        .sheet(item: $editorForm) { form in
            PortForwardEditSheet(form: form,
                                 interfaces: store.interfaces,
                                 aliases: store.aliases) { saved in try await save(changes: saved) }
        }
        .writeErrorAlert(isErrorPresented: $showErrorAlert, error: $writeError)
    }

    private var deleteOperation: AdministrativeWrite {
        .deleteNatRule(
            tracker: forward.tracker,
            displayName: forward.descr.isEmpty ? forward.tracker : forward.descr
        )
    }

    private func confirmDelete() async {
        isSaving = true
        defer { isSaving = false }

        guard !forward.tracker.isEmpty else {
            writeError = WriteError(
                title: "Cannot identify port forward",
                message: "The firewall did not provide a tracker ID, so Vaktpost will not risk deleting a different rule.",
                suggestion: "Refresh the firewall data and try again."
            )
            showErrorAlert = true
            return
        }

        do {
            _ = try await store.writeCoordinator.execute(deleteOperation)
            dismiss()
            await store.refreshFirewallObjectsAfterWrite()
        } catch {
            writeError = WriteError.from(error, operation: .other)
            showErrorAlert = true
        }
    }

    /// Rethrows rather than swallowing into a `Bool`, for the same reason as
    /// the rule detail's `save(changes:)`.
    private func save(changes: PortForwardEditForm) async throws {
        // From the form, not the forward: the editor offers an
        // interface field and it was being ignored on save.
        var dict = changes.toDict(interface: changes.interface).raw

        // The forward's identity as it was fetched, before any of the edits
        // in `changes` were applied. Real pfSense NAT rules carry no tracker
        // at all -- only filter rules get one -- so this is what the save
        // matches an existing, never-yet-adopted forward by. It has to come
        // from `forward`, the untouched value this screen was opened with,
        // never from `changes`: matching against the NEW values would fail
        // exactly when the edit changes one of these fields, which is an
        // ordinary thing to want to do.
        dict["original_interface"] = .string(forward.interfaceName)
        dict["original_destination"] = FilterAddress.encoded(
            forward.destinationSide.address, as: forward.destinationSide.storageKind)
        dict["original_destination_port"] = .string(forward.destinationSide.port ?? "")
        dict["original_target"] = .string(forward.target)

        let outcome = try await store.writeCoordinator.execute(
            .saveNatRule(
                rule: JSONDict(dict),
                displayName: forward.descr.isEmpty ? forward.id : forward.descr
            )
        )

        await store.refreshFirewallObjectsAfterWrite()
        // WebUI-created NAT rules have no tracker. Their first Vaktpost save
        // assigns one, changing `PortForward.id`; without retargeting this
        // selection the successful edit resolved its old id to “That rule is
        // no longer in the list.”
        selection = outcome.objectID.flatMap { $0.isEmpty ? nil : $0 } ?? forward.id
    }

    /// Every address or port behind a value, one per line. Same as the rule
    /// screen's; both types need it and neither owns the other.
    private func expandedValues(_ value: String) -> [String] {
        store.resolveAlias(value) ?? [value]
    }
}

struct PortForwardEditForm: Equatable, Identifiable {
    /// Identity for `sheet(item:)`, so a draft and an edit cannot be mistaken
    /// for the same sheet.
    var id: String { "\(isCreating ? "new" : "edit")-\(interface)-\(descr)-\(destinationPort)" }

    var tracker: String
    /// True when this will add a forward rather than change one.
    ///
    /// It matters more here than for a filter rule. A forward with no tracker
    /// is matched back by interface, destination, port and target — and a copy
    /// is identical to its original in all four, so without this a duplicate
    /// would match what it was copied from and replace it. Duplicate would
    /// delete the thing it duplicated.
    var isCreating = false
    var descr: String
    var proto: String
    var interface: String
    var sourceAddress: String
    var sourceStorageKind: FilterAddress.StorageKind
    var destinationAddress: String
    var destinationStorageKind: FilterAddress.StorageKind
    var destinationPort: String
    var targetAddress: String
    var localPort: String
    var disabled: Bool
    var addressFamily: String

    /// A new forward on an interface.
    ///
    /// Disabled to start with, for the same reason a new rule is: the thing
    /// that cannot be undone from a phone is traffic that reached somewhere it
    /// should not while the forward was being written.
    ///
    /// The destination defaults to the interface address, which is what a port
    /// forward on a WAN almost always means and what pfSense's own form
    /// prefills.
    static func blank(interface: String) -> PortForwardEditForm {
        var form = PortForwardEditForm(from: PortForward(JSONDict([
            "interface": .string(interface),
            "protocol": .string("tcp"),
            "ipprotocol": .string("inet"),
            "disabled": .bool(true),
            "descr": .string(""),
            "source": .object(["any": .bool(true)]),
            "destination": .object(["network": .string("\(interface)ip")]),
            "target": .string("")
        ])))
        form.isCreating = true
        return form
    }

    /// A copy, ready to be saved as another forward.
    ///
    /// The port is cleared as well as the description being marked. Two
    /// forwards on one interface with the same destination port is a conflict
    /// pfSense will take and only one of them will work — and a copy that
    /// keeps its original's port is exactly that, made by accident.
    static func duplicating(_ forward: PortForward) -> PortForwardEditForm {
        var form = PortForwardEditForm(from: forward)
        form.isCreating = true
        form.tracker = ""
        form.destinationPort = ""
        form.descr = forward.descr.isEmpty ? "Copy" : "\(forward.descr) (copy)"
        form.disabled = true
        return form
    }

    init(from forward: PortForward) {
        tracker = forward.tracker
        descr = forward.descr
        proto = forward.proto ?? ""
        interface = forward.interfaceName
        sourceAddress = forward.sourceSide.address
        sourceStorageKind = forward.sourceSide.storageKind
        destinationAddress = forward.destinationSide.address
        destinationStorageKind = forward.destinationSide.storageKind
        destinationPort = forward.destinationSide.port ?? ""
        targetAddress = forward.target
        localPort = forward.localPort ?? ""
        disabled = forward.disabled
        // The forward's own field, not a guess from its protocol.
        addressFamily = forward.ipProtocol ?? "inet"
    }

    func toDict(interface: String) -> JSONDict {
        var dict: [String: JSONValue] = [
            // Empty when creating, so the firewall appends rather than
            // matching. See `isCreating`.
            "tracker": .string(isCreating ? "" : tracker),
            "create": .bool(isCreating),
            "interface": .string(interface),
            "protocol": .string(proto.isEmpty ? "any" : proto),
            "ipprotocol": .string(addressFamily),
            "source": FilterAddress.encoded(sourceAddress, as: sourceStorageKind),
            "destination": FilterAddress.encoded(destinationAddress, as: destinationStorageKind),
            "target": .string(targetAddress.trimmingCharacters(in: .whitespacesAndNewlines)),
            "descr": .string(descr),
            "disabled": .bool(disabled)
        ]
        if !destinationPort.isEmpty {
            dict["destination_port"] = .string(destinationPort.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if !localPort.isEmpty {
            dict["local_port"] = .string(localPort.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return JSONDict(dict)
    }
}

/// Where this rule sits, and what above it already catches its traffic.
///
/// Shown in the editor rather than only in the confirmation, because position
/// changes what somebody writes — a rule that will never be reached is one to
/// reconsider, not one to review at the last moment and save anyway.
struct PlacementCard: View {
    @Environment(\.themeManager) private var theme: ThemeManager

    let placement: RulePlacement.Placement
    let action: String

    var body: some View {
        Slab(rail: placement.findings.isEmpty ? .info : .warn,
             title: "Placement",
             trailing: positionText) {
            VStack(alignment: .leading, spacing: 8) {
                if placement.isNew {
                    Text("This disabled draft will be inserted at the selected position. Review every rule above it before enabling it.")
                        .scaledFont(12)
                        .foregroundStyle(theme.labelMuted)
                }

                if placement.findings.isEmpty {
                    Text("Nothing above it on this interface matches the same traffic.")
                        .scaledFont(12)
                        .foregroundStyle(theme.labelFaint)
                } else {
                    ForEach(placement.findings) { finding in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(finding.headline)
                                .scaledFont(12, weight: .semibold)
                                .foregroundStyle(theme.warn)
                            Text(finding.detail(action: action))
                                .scaledFont(11)
                                .foregroundStyle(theme.labelMuted)
                            if !finding.other.descr.isEmpty {
                                Text(finding.other.descr)
                                    .scaledFont(10, design: .monospaced)
                                    .foregroundStyle(theme.labelFaint)
                            }
                        }
                    }

                    // The limit, said where the claim is made. This compares
                    // literal values; it does no subnet arithmetic and does not
                    // resolve aliases, so silence here is not proof.
                    Text("Only exact matches and \"any\" are compared. A wider network or an alias above this rule may still catch it.")
                        .scaledFont(10)
                        .foregroundStyle(theme.labelFaint)
                }
            }
        }
    }

    private var positionText: String {
        "\(placement.proposedPosition) of \(placement.total)"
    }
}

/// What is wrong with the form, if anything.
///
/// Listed at the bottom rather than beside each field: the fields are short and
/// a message under one of them pushes the rest of the form around as somebody
/// types, which is worse than reading a few lines in one place.
struct ProblemList: View {
    @Environment(\.themeManager) private var theme: ThemeManager

    let problems: [FieldValidator.Problem]

    var body: some View {
        if !problems.isEmpty {
            Slab(rail: .warn,
                 title: problems.count == 1 ? "One problem" : "\(problems.count) problems") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(problems, id: \.field) { problem in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(problem.field.uppercased())
                                .scaledFont(9, weight: .semibold)
                                .foregroundStyle(theme.labelFaint)
                            Text(problem.message)
                                .scaledFont(12)
                                .foregroundStyle(theme.label)
                        }
                    }
                }
            }
        }
    }
}

/// Editing one port forward.
///
/// Same treatment as the rule editor, and the same reasons. The `interface`
/// field here was worse than untidy: it was a text field the save path
/// ignored, so moving a forward to another interface appeared to work and
/// changed nothing on the firewall.
struct PortForwardEditSheet: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dismiss) private var dismiss

    let interfaces: [InterfaceStat]
    let aliases: [FirewallAliasEntry]
    let onSave: (PortForwardEditForm) async throws -> Void

    @State private var edited: PortForwardEditForm
    @State private var isSaving = false

    /// Shown by this sheet, for the same reason as `RuleEditSheet`: it remains
    /// the topmost view while its save runs.
    @State private var writeError: WriteError?
    @State private var showErrorAlert = false

    private let original: PortForwardEditForm

    private var isDirty: Bool { edited.isCreating || edited != original }

    init(form: PortForwardEditForm, interfaces: [InterfaceStat],
         aliases: [FirewallAliasEntry],
         onSave: @escaping (PortForwardEditForm) async throws -> Void) {
        self.interfaces = interfaces
        self.aliases = aliases
        self.onSave = onSave
        self.original = form
        _edited = State(initialValue: form)
    }

    private var problems: [FieldValidator.Problem] {
        FieldValidator.problems(inForward: edited, aliases: Set(aliases.map(\.name)),
                                interfaces: Set(interfaceKeys))
    }

    private var interfaceKeys: [String] {
        interfaces.compactMap(\.internalName)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Slab(rail: .info, title: "Forward") {
                        VStack(alignment: .leading, spacing: 12) {
                            EditField(label: "Description", text: $edited.descr,
                                      prompt: "What this forward is for", mono: false)
                            EditChoice(label: "Interface", options: interfaceKeys,
                                       selection: $edited.interface) { key in
                                interfaces.first { $0.internalName == key }?.name ?? key
                            }
                            EditChoice(label: "Protocol", options: FirewallVocabulary.protocols,
                                       selection: $edited.proto)
                            EditChoice(label: "IP version",
                                       options: FirewallVocabulary.addressFamilies,
                                       selection: $edited.addressFamily)
                        }
                    }

                    Slab(rail: .info, title: "Matched traffic") {
                        VStack(alignment: .leading, spacing: 12) {
                            EditAddress(label: "Source address", text: $edited.sourceAddress,
                                        storageKind: $edited.sourceStorageKind,
                                        interfaces: interfaces,
                                        aliases: aliases)
                            EditAddress(label: "Destination address",
                                        text: $edited.destinationAddress,
                                        storageKind: $edited.destinationStorageKind,
                                        interfaces: interfaces,
                                        aliases: aliases)
                            EditAliasField(label: "Destination port",
                                           text: $edited.destinationPort,
                                           prompt: "the port on the outside",
                                           aliases: aliases.filter(\.isPortAlias),
                                           aliasButtonTitle: "Choose port alias")
                        }
                    }

                    Slab(rail: .info, title: "Sent to") {
                        VStack(alignment: .leading, spacing: 12) {
                            EditAliasField(label: "Target address",
                                           text: $edited.targetAddress,
                                           prompt: "the host inside",
                                           aliases: aliases.filter(\.isAddressAlias),
                                           aliasButtonTitle: "Choose address alias")
                            EditAliasField(label: "Redirect target port", text: $edited.localPort,
                                           prompt: "blank to keep the same port",
                                           aliases: aliases.filter(\.isPortAlias),
                                           aliasButtonTitle: "Choose port alias")
                        }
                    }

                    Slab(rail: .info, title: "Options") {
                        EditToggle(label: "Disabled",
                                   detail: "Kept in the NAT table and not applied.",
                                   isOn: $edited.disabled)
                    }

                    ProblemList(problems: problems)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(theme.bg.ignoresSafeArea())
            .navigationTitle(edited.isCreating ? "New port forward" : "Edit port forward")
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
                            Task { await saveConfirmed() }
                        }
                        // Nothing invalid leaves this screen. pfSense takes
                        // most of it and then quietly fails to load the
                        // rule, which is a rule enforcing nothing while
                        // the app says "saved".
                        .disabled(!isDirty || !problems.isEmpty)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
            .writeErrorAlert(isErrorPresented: $showErrorAlert, error: $writeError)
        }
    }

    private var changePreview: String {
        if edited.isCreating {
            // Against nothing, every field is a change. What matters is what
            // the forward will do and that it is not live yet.
            var text = "A new port forward will be added to \(edited.interface):\n\n"
            text += "• \(edited.proto.isEmpty ? "any" : edited.proto)"
            text += " to \(edited.destinationAddress.isEmpty ? "this interface" : edited.destinationAddress)"
            if !edited.destinationPort.isEmpty { text += " port \(edited.destinationPort)" }
            text += "\n• forwarded to \(edited.targetAddress.isEmpty ? "nowhere yet" : edited.targetAddress)"
            if !edited.localPort.isEmpty { text += " port \(edited.localPort)" }
            text += "\n• \(edited.disabled ? "Disabled" : "Enabled") on creation"
            text += "\n\nAppended to the end of the NAT table."
            return text
        }

        var changes: [String] = []
        Self.describe("Interface", original.interface, edited.interface, into: &changes)
        Self.describe("Protocol", original.proto, edited.proto, into: &changes)
        Self.describe("IP version", original.addressFamily, edited.addressFamily, into: &changes)
        Self.describe("Source", original.sourceAddress, edited.sourceAddress, into: &changes)
        Self.describeAddressType("Source type", original.sourceStorageKind,
                                 edited.sourceStorageKind, into: &changes)
        Self.describe("Destination", original.destinationAddress, edited.destinationAddress, into: &changes)
        Self.describeAddressType("Destination type", original.destinationStorageKind,
                                 edited.destinationStorageKind, into: &changes)
        Self.describe("Destination port", original.destinationPort, edited.destinationPort, into: &changes)
        Self.describe("Target", original.targetAddress, edited.targetAddress, into: &changes)
        Self.describe("Redirect target port", original.localPort, edited.localPort, into: &changes)
        Self.describe("Description", original.descr, edited.descr, into: &changes)
        if original.disabled != edited.disabled { changes.append("Disabled: \(original.disabled ? "yes" : "no") → \(edited.disabled ? "yes" : "no")") }
        return "The coordinator will save and read back:\n\n" + changes.map { "• \($0)" }.joined(separator: "\n")
    }

    private static func describe(_ label: String, _ before: String, _ after: String,
                                 into changes: inout [String]) {
        guard before != after else { return }
        changes.append("\(label): \(before.isEmpty ? "any" : before) → \(after.isEmpty ? "any" : after)")
    }

    private static func describeAddressType(_ label: String,
                                            _ before: FilterAddress.StorageKind,
                                            _ after: FilterAddress.StorageKind,
                                            into changes: inout [String]) {
        guard before != after else { return }
        changes.append("\(label): \(addressTypeLabel(before)) → \(addressTypeLabel(after))")
    }

    private static func addressTypeLabel(_ kind: FilterAddress.StorageKind) -> String {
        switch kind {
        case .any: return "Any"
        case .network: return "System selector"
        case .address: return "Address, network or alias"
        }
    }

    private func saveConfirmed() async {
        isSaving = true
        do {
            try await onSave(edited)
            isSaving = false
            dismiss()
        } catch {
            // Caught and shown here, on the view that is actually on screen —
            // not passed back to a presenter this sheet is still covering.
            isSaving = false
            writeError = WriteError.from(error, operation: .other)
            showErrorAlert = true
        }
    }
}
