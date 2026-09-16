import SwiftUI

// Split out of FirewallView.swift on size alone (file length). Each type
// here is fully independent of FirewallView itself — nothing was
// restructured, only relocated.

/// One rule, as a row.
///
/// Two lines: what it does, and what it applies to. Everything else — the
/// tracker, the IP protocol, whether it logs, the full alias contents — is on
/// the detail screen. Ninety-eight rules at five lines each is a list nobody
/// scrolls; at two lines it is a list you can scan.
/// One rule, as a row.
///
/// Enough to judge a rule without opening it: what it does, on what interface,
/// over what protocol, from where to where and on which port. The kinds are
/// marked — host, network, alias, interface — because four rules that look
/// alike in a list can be doing very different things, and pfSense does not
/// say which is which anywhere you can see it.
///
/// The tracker, IP version and logging flag stay on the detail screen. They
/// matter when you are working on a rule, not when you are looking for one.
/// One rule, as a row.
///
/// Four labelled lines in a fixed order — FROM, TO, PORT, WHY — so a column of
/// rules can be read down rather than across. The port is its own row because
/// it belongs to neither side visually and squeezing it onto the right of one
/// of them made both wrap.
///
/// Addresses, never alias names: what a rule permits is the addresses. The
/// kind marker went too — with the names gone it was labelling an address as
/// "alias", which describes where the value came from rather than what it is.
/// A rule or a separator, treated as one thing for reordering.
///
/// The drag has to move both kinds through a single list, since dropping a
/// rule above or below a separator is exactly the interaction being asked
/// for — a list of only rules could not express that.
enum RuleListItem: Identifiable {
    case rule(FirewallRule)
    case separator(RuleSeparator)

    var id: String {
        switch self {
        case .rule(let rule): return "rule:\(rule.tracker)"
        case .separator(let separator): return "separator:\(separator.key)"
        }
    }

    var reorderItem: FirewallClient.ReorderItem {
        switch self {
        case .rule(let rule): return .rule(tracker: rule.tracker)
        case .separator(let separator): return .separator(key: separator.key)
        }
    }
}

/// Where a drag currently wants to drop, computed live as the drag moves
/// over other rows — the same "swap as you hover" feel `List`'s own reorder
/// handle has, built by hand because that handle cannot be moved to the
/// leading edge it was asked to appear on.
struct RuleReorderDropDelegate: DropDelegate {
    let target: RuleListItem
    @Binding var items: [RuleListItem]
    @Binding var draggingID: String?

    func dropEntered(info: DropInfo) {
        guard let draggingID, draggingID != target.id,
              let from = items.firstIndex(where: { $0.id == draggingID }),
              let to = items.firstIndex(where: { $0.id == target.id }) else { return }
        guard items[from].id != items[to].id else { return }
        withAnimation(.default) {
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

/// The handle itself — the only part of a row that starts a drag, so the
/// rest of the row keeps working as a normal tap target.
struct RuleDragHandle: View {
    @Environment(\.themeManager) private var theme: ThemeManager

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .scaledFont(13, weight: .semibold)
            .foregroundStyle(theme.labelFaint)
            .frame(width: 28, height: 36)
            .contentShape(Rectangle())
    }
}

struct RuleRow: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore
    let rule: FirewallRule

    var body: some View {
        Slab(rail: rule.health, muted: rule.disabled,
             trailing: store.interfaceLabel(for: rule.interfaceName)) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    StatusPill(text: rule.type.uppercased(), health: rule.health)
                    Text(rule.protoLabel)
                        .scaledFont(10, weight: .semibold, design: .monospaced)
                        .foregroundStyle(theme.labelFaint)
                    if rule.disabled { StatusPill(text: "disabled", health: .idle) }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .scaledFont(10, weight: .semibold)
                        .foregroundStyle(theme.labelFaint)
                }

                // The raw stored value, not what it resolves to. pfSense's
                // own rules list shows "alias_host_nas003" as a clickable
                // alias name, never the address it expands to — resolving it
                // here made the list disagree with the firewall's own about
                // what a rule literally says.
                field("FROM", rule.sourceSide.address)
                field("TO", rule.destinationSide.address)

                if let port = ports {
                    field("PORT", port)
                }
                if !rule.descr.isEmpty {
                    field("DESC", rule.descr, mono: false)
                }
            }
        }
        .opacity(rule.disabled ? 0.68 : 1)
    }

    /// Both ports, if either is set. A source port is rare enough that
    /// labelling it separately in a list would waste a row on every rule that
    /// does not have one.
    private var ports: String? {
        let source = rule.sourceSide.port
        let destination = rule.destinationSide.port
        switch (source, destination) {
        case let (s?, d?): return "\(s) → \(d)"
        case let (nil, d?): return d
        case let (s?, nil): return "from \(s)"
        default: return nil
        }
    }

    private func field(_ label: String, _ value: String, mono: Bool = true) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .scaledFont(9, weight: .semibold)
                .foregroundStyle(theme.labelFaint)
                .frame(width: 38, alignment: .leading)
            // One line, truncated.
            //
            // A rule whose source expands to twenty networks was four lines
            // tall in a list of ninety-eight, and the list exists to be
            // scanned. The full value is on the detail screen, which has room
            // for it.
            Text(value)
                .scaledFont(12, weight: mono ? .medium : .regular,
                            design: mono ? .monospaced : .default)
                .foregroundStyle(mono ? theme.label : theme.labelMuted)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
    }
}

/// One rule, in full.
struct RuleDetailView: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore
    @Environment(\.dismiss) private var dismiss
    let rule: FirewallRule
    @Binding var selection: String?

    /// The form the sheet opens with — an edit of this rule, or a copy of it.
    @State private var editorForm: RuleEditForm?
    @State private var showSimulation = false
    @State private var isSaving = false
    @State private var showErrorAlert = false
    @State private var writeError: WriteError?

    /// Every address or port behind a value, one per line.
    ///
    /// Uncapped, unlike the list: this is the screen you open precisely to see
    /// all twenty-two of them.
    private func expandedValues(_ value: String) -> [String] {
        store.resolveAlias(value) ?? [value]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Slab(rail: rule.health, trailing: store.interfaceLabel(for: rule.interfaceName)) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            StatusPill(text: rule.type.uppercased(), health: rule.health)
                            Text(rule.protoLabel)
                                .scaledFont(11, weight: .semibold, design: .monospaced)
                                .foregroundStyle(theme.labelMuted)
                            Spacer()
                            if rule.disabled { StatusPill(text: "disabled", health: .idle) }
                        }
                        if !rule.descr.isEmpty {
                            Text(rule.descr)
                                .scaledFont(14)
                                .foregroundStyle(theme.label)
                        }
                    }
                }

                GroupHeading(text: "Source and destination")
                Slab(rail: .info) {
                    VStack(alignment: .leading, spacing: 8) {
                        detailField("Source", rule.sourceSide.address)
                        if let port = rule.sourceSide.port, !port.isEmpty {
                            detailField("Source port", port)
                        }
                        detailField("Destination", rule.destinationSide.address)
                        if let port = rule.destinationSide.port, !port.isEmpty {
                            detailField("Destination port", port)
                        }
                    }
                }

                GroupHeading(text: "Rule")
                Slab(rail: .idle) {
                    VStack(alignment: .leading, spacing: 4) {
                        FieldRow(key: "Status", value: rule.disabled ? "Disabled" : "Enabled", mono: false)
                        FieldRow(key: "Action", value: rule.type.capitalized, mono: false)
                        FieldRow(key: "Protocol", value: rule.protoLabel, mono: false)
                        FieldRow(key: "Interface",
                                 value: store.interfaceLabel(for: rule.interfaceName)
                                     ?? rule.interfaceName)
                        if let ipProtocol = rule.ipProtocol, !ipProtocol.isEmpty {
                            FieldRow(key: "IP version", value: ipProtocol)
                        }
                        FieldRow(key: "Logged", value: rule.logged ? "yes" : "no", mono: false)
                        FieldRow(key: "Gateway", value: rule.gateway.isEmpty ? "default" : rule.gateway)
                        FieldRow(key: "Queue", value: rule.queueLabel)
                        FieldRow(key: "Schedule", value: rule.schedule.isEmpty ? "none" : rule.schedule)
                        FieldRow(key: "State type", value: rule.stateType.isEmpty ? "default" : rule.stateType)
                        if !rule.tracker.isEmpty {
                            FieldRow(key: "Tracker", value: rule.tracker)
                        }
                    }
                }

                AdministrationModeNotice()

                if !isSaving {
                    VStack(spacing: 8) {
                        Button {
                            editorForm = RuleEditForm(from: rule)
                        } label: {
                            Label("Edit Rule", systemImage: "pencil")
                                .scaledFont(14, weight: .medium)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(theme.accentColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            editorForm = RuleEditForm.duplicating(rule)
                        } label: {
                            Label("Duplicate Rule", systemImage: "plus.square.on.square")
                                .scaledFont(14, weight: .medium)
                                .foregroundStyle(theme.accentColor)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(theme.cardRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            Task { await confirmDelete() }
                        } label: {
                            Label("Delete Rule", systemImage: "trash")
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
        .navigationTitle(rule.descr.isEmpty ? "Rule" : rule.descr)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showSimulation = true
                } label: {
                    Label("Test", systemImage: "waveform.badge.magnifyingglass")
                }
                .disabled(isSaving)
            }
        }
        // Built here, at presentation, rather than in `onAppear`.
        //
        // This is why the editor felt slow. The form was assembled in the
        // detail view's `onAppear` and the sheet rendered "Loading…" until it
        // arrived — for a struct copied synchronously out of a rule the view
        // already held. There was never anything to load; the spinner was the
        // whole delay, and on a fast tap it was what you got.
        // Key the presentation by the actual draft. A Boolean sheet reused
        // the editor's @State between an edit and a later duplicate, turning
        // that duplicate back into an edit of the source rule.
        .sheet(item: $editorForm) { form in
            RuleEditSheet(form: form,
                          interfaces: store.interfaces,
                          aliases: store.aliases,
                          ruleset: store.rules,
                          subject: rule) { saved in try await save(changes: saved) }
        }
        .sheet(isPresented: $showSimulation) {
            RuleSimulationSheet(rule: rule)
        }
        .writeErrorAlert(isErrorPresented: $showErrorAlert, error: $writeError)
    }

    private var deleteOperation: AdministrativeWrite {
        .deleteRule(
            tracker: rule.tracker,
            displayName: rule.descr.isEmpty ? rule.tracker : rule.descr
        )
    }

    private func confirmDelete() async {
        isSaving = true
        defer { isSaving = false }

        do {
            _ = try await store.writeCoordinator.execute(deleteOperation)
            dismiss()
            await store.refreshFirewallObjectsAfterWrite()
        } catch {
            writeError = WriteError.from(error, operation: .other)
            showErrorAlert = true
        }
    }

    /// Save, and say whether it worked.
    ///
    /// Was synchronous, with `isSaving = true` and a `defer` that put it back
    /// before the `Task` inside had started — so the flag was never observed
    /// true, the spinner never appeared, and Save stayed tappable through the
    /// whole write. It returns a result now, and the sheet closes itself on
    /// success rather than the detail view dismissing out from under it.
    /// Rethrows rather than swallowing into a `Bool`.
    ///
    /// This view is still covered by the edit sheet when a save fails — the
    /// confirmation dismissing does not dismiss the sheet underneath it — so
    /// an error stashed here stayed invisible until something else happened
    /// to dismiss that sheet later. The sheet catches it now, where it is
    /// actually on screen.
    private func save(changes: RuleEditForm) async throws {
        // The interface comes from the form now. It was taken from the
        // rule, so moving a rule between interfaces in the editor
        // changed the screen and not the firewall.
        let outcome = try await store.writeCoordinator.execute(
            .saveRule(
                rule: changes.toDict(tracker: rule.tracker, interface: changes.interface),
                displayName: rule.descr.isEmpty ? rule.tracker : rule.descr
            )
        )

        // Re-read the exact objects that changed before reporting success.
        // The broad dashboard refresh can coalesce with an existing cycle and
        // leave this list stale for several seconds.
        await store.refreshFirewallObjectsAfterWrite()
        // Keep the open detail attached to the identity returned by pfSense.
        // A normal filter edit retains its tracker; a duplicate gets a new
        // one and should continue into the newly created rule.
        selection = outcome.objectID.flatMap { $0.isEmpty ? nil : $0 } ?? rule.id
    }

    /// A field, with the alias name kept above its contents.
    ///
    /// The list shows addresses because it has one line; here there is room
    /// for both, and the name is what you would search the Aliases screen for.
    @ViewBuilder
    private func detailField(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .scaledFont(9, weight: .semibold)
                .foregroundStyle(theme.labelFaint)
            // One address per line.
            //
            // A wrapped run of comma-separated networks breaks mid-address, so
            // `198.51.100.0/22` can end one line and start the next. A list
            // reads as a list, and each entry stays whole and selectable.
            ForEach(expandedValues(value), id: \.self) { entry in
                Text(entry)
                    .scaledFont(13, weight: .medium, design: .monospaced)
                    .foregroundStyle(theme.label)
                    .textSelection(.enabled)
            }
        }
    }
}

/// Editable representation of a firewall rule.
struct RuleEditForm: Equatable, Identifiable {
    enum LogPrefillError: LocalizedError, Equatable {
        case notFirewallEvent
        case outboundDirection
        case missingInterface
        case invalidAddress
        case mixedAddressFamilies
        case unsupportedProtocol
        case invalidPort

        var errorDescription: String? {
            switch self {
            case .notFirewallEvent: return "This log entry does not contain a complete firewall event."
            case .outboundDirection:
                return "Outbound events cannot be mapped safely to a normal interface rule. Create a floating rule manually instead."
            case .missingInterface: return "The event's interface could not be mapped to a configured pfSense interface."
            case .invalidAddress: return "The event does not contain two valid literal IP addresses."
            case .mixedAddressFamilies: return "The source and destination use different IP address families."
            case .unsupportedProtocol: return "The event protocol cannot be represented safely by the rule editor."
            case .invalidPort: return "The event contains an invalid transport port."
            }
        }
    }
    /// Identity for `sheet(item:)`. A draft is one thing at a time, and the
    /// interface it is being written for is what distinguishes one draft from
    /// the next.
    var id: String { "\(isCreating ? "new" : "edit")-\(interface)-\(descr)" }

    var descr: String
    var type: String
    var proto: String
    var interface: String
    var sourceAddress: String
    var sourceStorageKind: FilterAddress.StorageKind
    var sourcePort: String
    var destinationAddress: String
    var destinationStorageKind: FilterAddress.StorageKind
    var destinationPort: String
    var disabled: Bool
    var logged: Bool
    /// Stable placement request. Existing rules keep their position unless the
    /// person chooses a move; new rules default to the end as disabled drafts.
    var placementTarget: RulePlacement.Target = .keep
    /// True when this will add a rule rather than change one.
    ///
    /// Carried in the payload so the firewall knows not to match, and so it
    /// assigns the tracker itself. The app cannot pick one safely: it would be
    /// choosing against a ruleset fetched some seconds ago, and a collision
    /// does not append — it replaces whatever already had that tracker.
    var isCreating = false

    /// inet / inet6 / inet46, carried through rather than derived.
    ///
    /// `toDict` used to compute this from `proto`, comparing a transport
    /// protocol against the strings "inet" and "inet6" — so it was nil for
    /// every real rule, `ipprotocol` was left out of the payload, and saving
    /// an IPv6 rule silently dropped its address family. The value is the
    /// rule's own and is kept as one.
    var addressFamily: String

    /// A new rule on an interface, with the defaults somebody would type.
    ///
    /// Disabled to start with. A rule that appears at the bottom of a ruleset
    /// the moment it is saved, already active, is not what anybody wants from
    /// a first draft on a phone — and the one thing that cannot be undone from
    /// here is traffic that got through while it was being written.
    static func blank(interface: String) -> RuleEditForm {
        var form = RuleEditForm(from: FirewallRule(JSONDict([
            "tracker": .string(""),
            "interface": .string(interface),
            "type": .string("pass"),
            "ipprotocol": .string("inet"),
            "protocol": .string("any"),
            "disabled": .bool(true),
            "descr": .string(""),
            "source": .object(["any": .bool(true)]),
            "destination": .object(["any": .bool(true)])
        ])))
        form.isCreating = true
        form.placementTarget = .last
        return form
    }

    /// Builds a disabled, unsaved draft from one inbound filter event. This
    /// never calls the firewall. The editor, review dialog, write coordinator,
    /// stale-state checks, audit trail, and Apply Changes remain mandatory.
    static func prefilled(from line: LogLine, interface: String?) throws -> RuleEditForm {
        guard let fields = line.filterFields else { throw LogPrefillError.notFirewallEvent }
        guard (fields.direction ?? "").lowercased() == "in" else {
            throw LogPrefillError.outboundDirection
        }
        guard let interface, !interface.isEmpty else { throw LogPrefillError.missingInterface }
        guard let source = fields.source, let destination = fields.destination,
              FieldValidator.isAddress(source), FieldValidator.isAddress(destination) else {
            throw LogPrefillError.invalidAddress
        }

        let sourceV6 = FieldValidator.isIPv6(source)
        guard sourceV6 == FieldValidator.isIPv6(destination) else {
            throw LogPrefillError.mixedAddressFamilies
        }
        let proto = (fields.proto ?? "").lowercased()
        let supported = ["tcp", "udp", "icmp", "gre", "esp"]
        guard supported.contains(proto) else { throw LogPrefillError.unsupportedProtocol }
        if let sourcePort = fields.sourcePort, !sourcePort.isEmpty,
           !FieldValidator.isPortNumber(sourcePort) { throw LogPrefillError.invalidPort }
        if let destinationPort = fields.destinationPort, !destinationPort.isEmpty,
           !FieldValidator.isPortNumber(destinationPort) { throw LogPrefillError.invalidPort }

        var form = blank(interface: interface)
        form.descr = "From firewall log: \(source) to \(destination)"
        form.type = "pass"
        form.proto = proto
        form.addressFamily = sourceV6 ? "inet6" : "inet"
        form.sourceAddress = source
        form.sourceStorageKind = .address
        form.destinationAddress = destination
        form.destinationStorageKind = .address
        if proto == "tcp" || proto == "udp" {
            form.sourcePort = fields.sourcePort ?? ""
            form.destinationPort = fields.destinationPort ?? ""
        }
        form.disabled = true
        form.logged = true
        form.isCreating = true
        form.placementTarget = .last
        return form
    }

    /// An exact copy of an existing rule, ready to be saved as another one.
    /// Identity is the one field it must not copy: `isCreating` makes the
    /// payload omit the source tracker and pfSense assigns a new one.
    static func duplicating(_ rule: FirewallRule) -> RuleEditForm {
        var form = RuleEditForm(from: rule)
        form.isCreating = true
        form.placementTarget = .last
        return form
    }

    init(from rule: FirewallRule) {
        descr = rule.descr
        type = rule.type
        proto = rule.proto ?? ""
        interface = rule.interfaceName
        addressFamily = rule.ipProtocol ?? "inet"
        sourceAddress = rule.sourceSide.address
        sourceStorageKind = rule.sourceSide.storageKind
        sourcePort = rule.sourceSide.port ?? ""
        destinationAddress = rule.destinationSide.address
        destinationStorageKind = rule.destinationSide.storageKind
        destinationPort = rule.destinationSide.port ?? ""
        disabled = rule.disabled
        logged = rule.logged
        placementTarget = .keep
    }

    func apply(to rule: FirewallRule) -> FirewallRule {
        FirewallRule(JSONDict([
            "tracker": .string(rule.tracker),
            "interface": .string(interface),
            "type": .string(type),
            "ipprotocol": .string(addressFamily),
            "protocol": proto.isEmpty ? .string("any") : .string(proto),
            "source": FilterAddress.encoded(sourceAddress, as: sourceStorageKind),
            "source_port": sourcePort.isEmpty ? .null : .string(sourcePort),
            "destination": FilterAddress.encoded(destinationAddress, as: destinationStorageKind),
            "destination_port": destinationPort.isEmpty ? .null : .string(destinationPort),
            "descr": .string(descr),
            "disabled": .bool(disabled),
            "log": .bool(logged)
        ]))
    }

    func toDict(tracker: String, interface: String) -> JSONDict {
        var dict: [String: JSONValue] = [
            // Empty when creating: the firewall assigns it, and sending a
            // stale one would match an existing rule and replace it.
            "tracker": .string(isCreating ? "" : tracker),
            "create": .bool(isCreating),
            "interface": .string(interface),
            "type": .string(type),
            "protocol": .string(proto.isEmpty ? "any" : proto),
            "source": FilterAddress.encoded(sourceAddress, as: sourceStorageKind),
            "destination": FilterAddress.encoded(destinationAddress, as: destinationStorageKind),
            "descr": .string(descr),
            "disabled": .bool(disabled),
            "log": .bool(logged)
        ]
        if !sourcePort.isEmpty {
            dict["source_port"] = .string(sourcePort.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if !destinationPort.isEmpty {
            dict["destination_port"] = .string(destinationPort.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        switch placementTarget {
        case .keep:
            break
        case .last:
            dict["placement"] = .string("last")
        case .before(let tracker):
            dict["placement"] = .string("before")
            dict["before_tracker"] = .string(tracker)
        }
        // Always sent. Omitting it does not mean "unchanged" to pfSense.
        dict["ipprotocol"] = .string(addressFamily)
        return JSONDict(dict)
    }
}

/// Editing one rule.
///
/// Was a bare SwiftUI `Form`, which is where the theming went: `Form` brings
/// its own background, insets and typography, so the editor arrived in system
/// grey with system fonts in the middle of a Catppuccin dashboard, and nothing
/// in the theme could reach it. This is the app's own scroll view and slabs.
///
/// The closed vocabularies are pickers rather than text fields with the
/// accepted values written into the placeholder. "Type (pass/block/reject)"
/// puts the validation in the hint text, and a typo there is a malformed rule
/// that the firewall is the first to find out about.
struct RuleEditSheet: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dismiss) private var dismiss

    /// Interface handles this firewall actually has, so the field cannot name
    /// one that does not exist.
    let interfaces: [InterfaceStat]
    /// Full alias metadata: validation uses the names, while the editor can
    /// show type, description and member count in its searchable picker.
    let aliases: [FirewallAliasEntry]
    /// The ruleset this rule lives in, for working out where it sits and what
    /// above it already catches the same traffic.
    let ruleset: [FirewallRule]
    /// The rule as the firewall currently has it, which is what gets placed —
    /// the edited copy is not in the ruleset yet.
    let subject: FirewallRule
    let onSave: (RuleEditForm) async throws -> Void

    @State private var edited: RuleEditForm
    @State private var isSaving = false
    @State private var showSaveReview = false

    /// Shown by this sheet itself because it remains the visible screen while
    /// the save is in progress.
    @State private var writeError: WriteError?
    @State private var showErrorAlert = false

    init(form: RuleEditForm, interfaces: [InterfaceStat], aliases: [FirewallAliasEntry],
         ruleset: [FirewallRule], subject: FirewallRule,
         onSave: @escaping (RuleEditForm) async throws -> Void) {
        self.interfaces = interfaces
        self.aliases = aliases
        self.ruleset = ruleset
        self.subject = subject
        self.onSave = onSave
        self.original = form
        _edited = State(initialValue: form)
    }

    private var problems: [FieldValidator.Problem] {
        FieldValidator.problems(inRule: edited, aliases: Set(aliases.map(\.name)),
                                interfaces: Set(interfaceKeys))
    }

    private var interfaceKeys: [String] {
        interfaces.compactMap(\.internalName)
    }

    /// Where this rule sits, computed against the rule as edited.
    ///
    /// Against the edited form rather than the stored rule: changing the
    /// interface or widening the source moves it and changes what precedes it,
    /// and a placement describing where it *used* to sit would be worse than
    /// none.
    private var placement: RulePlacement.Placement {
        RulePlacement.analyse(
            edited.apply(to: subject), in: ruleset, target: edited.placementTarget
        )
    }

    private var placementTargets: [RulePlacement.Target] {
        var targets: [RulePlacement.Target] = edited.isCreating ? [] : [.keep]
        targets += ruleset
            .filter {
                $0.interfaceName == edited.interface
                    && $0.id != subject.id
                    && !$0.tracker.isEmpty
            }
            .map { .before(tracker: $0.tracker) }
        targets.append(.last)
        return targets
    }

    private func placementLabel(_ target: RulePlacement.Target) -> String {
        switch target {
        case .keep:
            return "Keep current position"
        case .last:
            return "Last on \(edited.interface)"
        case .before(let tracker):
            guard let anchor = ruleset.first(where: { $0.tracker == tracker }) else {
                return "Unavailable rule"
            }
            let name = anchor.descr.isEmpty ? "tracker \(tracker)" : anchor.descr
            return "Before \(name)"
        }
    }

    /// What the rule looked like when the sheet opened.
    ///
    /// Kept so Save can be disabled until something actually changed. An
    /// unchanged save is a write to a firewall that alters nothing, spends the
    /// rate limit, and puts a line in the audit trail saying an edit happened.
    private let original: RuleEditForm

    // A create is itself a change even when the duplicated fields are left
    // untouched. Requiring a text edit before Save made Duplicate look like a
    // rename operation instead of allowing an exact copy.
    private var isDirty: Bool { edited.isCreating || edited != original }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Slab(rail: .info, title: "Rule") {
                        VStack(alignment: .leading, spacing: 12) {
                            EditField(label: "Description", text: $edited.descr,
                                      prompt: "What this rule is for", mono: false)
                            EditChoice(label: "Action", options: FirewallVocabulary.ruleTypes,
                                       selection: $edited.type)
                            EditChoice(label: "Interface", options: interfaceKeys,
                                       selection: $edited.interface)
                            EditChoice(label: "Protocol", options: FirewallVocabulary.protocols,
                                       selection: $edited.proto)
                            EditChoice(label: "IP version",
                                       options: FirewallVocabulary.addressFamilies,
                                       selection: $edited.addressFamily)
                        }
                    }

                    Slab(rail: .info, title: "Source") {
                        VStack(alignment: .leading, spacing: 12) {
                            EditAddress(label: "Address", text: $edited.sourceAddress,
                                        storageKind: $edited.sourceStorageKind,
                                        interfaces: interfaces,
                                        aliases: aliases)
                            EditAliasField(label: "Port", text: $edited.sourcePort,
                                           prompt: "blank for any",
                                           aliases: aliases.filter(\.isPortAlias),
                                           aliasButtonTitle: "Choose port alias")
                        }
                    }

                    Slab(rail: .info, title: "Destination") {
                        VStack(alignment: .leading, spacing: 12) {
                            EditAddress(label: "Address", text: $edited.destinationAddress,
                                        storageKind: $edited.destinationStorageKind,
                                        interfaces: interfaces,
                                        aliases: aliases)
                            EditAliasField(label: "Port", text: $edited.destinationPort,
                                           prompt: "blank for any",
                                           aliases: aliases.filter(\.isPortAlias),
                                           aliasButtonTitle: "Choose port alias")
                        }
                    }

                    Slab(rail: .info, title: "Options") {
                        VStack(alignment: .leading, spacing: 12) {
                            EditToggle(label: "Disabled",
                                       detail: "Kept in the ruleset and not evaluated.",
                                       isOn: $edited.disabled)
                            EditToggle(label: "Log",
                                       detail: "Matches appear in the filter log.",
                                       isOn: $edited.logged)
                        }
                    }

                    Slab(rail: .info, title: "Position",
                         trailing: "\(placement.proposedPosition) of \(placement.total)") {
                        VStack(alignment: .leading, spacing: 8) {
                            Menu {
                                ForEach(placementTargets, id: \.self) { target in
                                    Button(placementLabel(target)) { edited.placementTarget = target }
                                }
                            } label: {
                                HStack(alignment: .top, spacing: 6) {
                                    Text(placementLabel(edited.placementTarget))
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .scaledFont(12)
                                        .padding(.top, 2)
                                }
                                .foregroundStyle(theme.accentColor)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Text("The selected rule is used as a stable anchor and rechecked on the firewall before saving.")
                                .scaledFont(10)
                                .foregroundStyle(theme.labelFaint)
                        }
                    }

                    PlacementCard(placement: placement, action: edited.type)
                    ProblemList(problems: problems)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(theme.bg.ignoresSafeArea())
            .navigationTitle(edited.isCreating ? "New rule" : "Edit rule")
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
                        // Awaits the write and closes on success. It used to
                        // set a flag and return, so the button stayed live
                        // through the whole save and a second tap sent a
                        // second write.
                        Button("Save") {
                            showSaveReview = true
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
            .confirmationDialog("Review staged rule",
                                isPresented: $showSaveReview,
                                titleVisibility: .visible) {
                Button("Save staged rule") { Task { await saveConfirmed() } }
                Button("Continue editing", role: .cancel) {}
            } message: {
                Text(changePreview + "\n\nThe rule remains inactive until Apply Changes is reviewed and confirmed.")
            }
            .onChange(of: edited.interface) {
                // A tracker from the previous interface is not a meaningful
                // anchor on the new one. Moving interfaces therefore lands at
                // the safe disabled-draft default until another place is chosen.
                edited.placementTarget = .last
            }
            // Attached here rather than on whatever presented this sheet.
            // This remains the topmost view if saving fails.
            .writeErrorAlert(isErrorPresented: $showErrorAlert, error: $writeError)
        }
    }

    private var changePreview: String {
        if edited.isCreating {
            // No diff. Every field is "new", and listing them all as changes
            // would bury the two things that matter: where it lands and what
            // above it already catches the traffic.
            var text = "A new rule will be added to \(edited.interface):\n\n"
            text += "• \(edited.type) \(edited.proto.isEmpty ? "any" : edited.proto)"
            text += " from \(edited.sourceAddress.isEmpty ? "any" : edited.sourceAddress)"
            text += " to \(edited.destinationAddress.isEmpty ? "any" : edited.destinationAddress)"
            if !edited.destinationPort.isEmpty { text += " port \(edited.destinationPort)" }
            text += "\n• \(edited.disabled ? "Disabled" : "Enabled") on creation"
            let place = placement
            text += "\n\nInserted as rule \(place.proposedPosition) of \(place.total)."
            for finding in place.findings {
                text += "\n\n\(finding.headline): \(finding.detail(action: edited.type))"
            }
            return text
        }

        var changes: [String] = []
        Self.describe("Action", original.type, edited.type, into: &changes)
        Self.describe("Interface", original.interface, edited.interface, into: &changes)
        Self.describe("Protocol", original.proto, edited.proto, into: &changes)
        Self.describe("IP version", original.addressFamily, edited.addressFamily, into: &changes)
        Self.describe("Source", original.sourceAddress, edited.sourceAddress, into: &changes)
        Self.describeAddressType("Source type", original.sourceStorageKind,
                                 edited.sourceStorageKind, into: &changes)
        Self.describe("Source port", original.sourcePort, edited.sourcePort, into: &changes)
        Self.describe("Destination", original.destinationAddress, edited.destinationAddress, into: &changes)
        Self.describeAddressType("Destination type", original.destinationStorageKind,
                                 edited.destinationStorageKind, into: &changes)
        Self.describe("Destination port", original.destinationPort, edited.destinationPort, into: &changes)
        Self.describe("Description", original.descr, edited.descr, into: &changes)
        if original.disabled != edited.disabled { changes.append("Disabled: \(original.disabled ? "yes" : "no") → \(edited.disabled ? "yes" : "no")") }
        if original.logged != edited.logged { changes.append("Logging: \(original.logged ? "on" : "off") → \(edited.logged ? "on" : "off")") }

        var text = "The coordinator will save and read back:\n\n"
            + changes.map { "• \($0)" }.joined(separator: "\n")

        // Position belongs here as much as in the editor. A rule is only as
        // good as where it sits, and this sheet is the last thing read before
        // a firewall changes.
        let place = placement
        if let position = place.position {
            if place.proposedPosition == position {
                text += "\n\nPosition \(position) of \(place.total) on \(edited.interface)."
            } else {
                text += "\n\nMoved from rule \(position) to rule \(place.proposedPosition)"
                    + " of \(place.total) on \(edited.interface)."
            }
        } else {
            text += "\n\nPlaced as rule \(place.proposedPosition) of \(place.total)"
                + " on \(edited.interface)."
        }
        for finding in place.findings {
            text += "\n\n\(finding.headline): \(finding.detail(action: edited.type))"
        }
        return text
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
