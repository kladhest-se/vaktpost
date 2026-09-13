import SwiftUI

struct FirewallView: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore

    enum Pane: String, CaseIterable, Identifiable {
        case rules = "Rules", nat = "NAT"
        var id: String { rawValue }
    }

    @State private var pane: Pane = .rules
    @State private var showFloating = false
    @State private var query = ""
    @State private var interfaceFilter: String?
    @State private var cachedInterfaceOptions: [String] = []

    @State private var selection: String?
    /// A new rule being drafted, if any. Nil closes the sheet.
    @State private var newRule: RuleEditForm?
    /// A new port forward being drafted.
    @State private var newForward: PortForwardEditForm?

    var body: some View {
        MasterDetail(
            selection: $selection,
            emptyMessage: "Choose a rule or a port forward to see what it matches.",
            list: { listColumn },
            detail: { id in
                // Looked up by id in both collections. Rules and forwards
                // share one selection because only one can be showing, and
                // the ids cannot collide: a rule's is its tracker.
                if let rule = store.rules.first(where: { $0.id == id }) {
                    RuleDetailView(rule: rule)
                } else if let pf = store.portForwards.first(where: { $0.id == id }) {
                    PortForwardDetailView(forward: pf)
                } else {
                    Notice(symbol: "questionmark.circle",
                           title: "That rule is no longer in the list")
                }
            }
        )
        .task { updateInterfaceOptions() }
        .onChange(of: store.rules.count) { updateInterfaceOptions() }
    }

    private func updateInterfaceOptions() {
        var seen = Set<String>()
        var result: [String] = []
        for rule in store.rules {
            for part in rule.interfaceName.split(separator: ",") {
                let trimmed = part.trimmingCharacters(in: .whitespaces)
                if seen.insert(trimmed).inserted {
                    result.append(trimmed)
                }
            }
        }
        cachedInterfaceOptions = result.sorted {
            (store.interfaceLabel(for: $0) ?? $0) < (store.interfaceLabel(for: $1) ?? $1)
        }
    }

    private var listColumn: some View {
        VStack(spacing: 0) {
            // In the content, not the navigation bar.
            //
            // `.searchable` puts its field in the nav bar, which animates
            // itself in and out on focus — the field jumped up the screen the
            // moment it was tapped. This one stays where it is drawn, like the
            // Logs and Network fields.
            InlineSearchField(text: $query, prompt: "Description, address or port")
                .padding(.horizontal, 16)
                .padding(.top, 8)

            Picker("", selection: $pane) {
                ForEach(Pane.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if pane == .rules {
                if !interfaceOptions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            // Floating sits with the interfaces because that is
                            // what it is: a rule set that belongs to no single
                            // one of them. "All" is gone — tapping the selected
                            // chip clears the filter, which is what All did and
                            // one chip fewer to read.
                            // First, where a list of filters starts.
                            //
                            // It was at the far end, which put the way back to
                            // "everything" past thirteen interfaces.
                            chip("All", selected: interfaceFilter == nil && !showFloating) {
                                interfaceFilter = nil
                                showFloating = false
                            }
                            chip("Floating", selected: showFloating) {
                                showFloating.toggle()
                                if showFloating { interfaceFilter = nil }
                            }
                            ForEach(interfaceOptions, id: \.self) { iface in
                                chip(store.interfaceLabel(for: iface) ?? iface,
                                     selected: interfaceFilter == iface) {
                                    interfaceFilter = interfaceFilter == iface ? nil : iface
                                    if interfaceFilter != nil { showFloating = false }
                                }
                            }


                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 8)
                }
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    switch pane {
                    case .rules: rulesPane
                    case .nat: natPane
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .refreshable { await store.refreshManually() }
        }
        .background(theme.bg.ignoresSafeArea())
        // Rules, NAT and aliases are fetched when this screen opens rather
        // than on the refresh timer — 98 rules is a large payload for a tab
        // most people never open. Nothing called this, so the tab was empty.
        .task { await store.loadFirewallObjects() }
        .navigationTitle("Firewall")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                // Only on the rules pane, and only once an interface is
                // chosen. A new rule has to land somewhere, and asking which
                // interface inside the editor would be a question with fifteen
                // answers in a sheet that is already long.
                if let interface = interfaceFilter {
                    switch pane {
                    case .rules:
                        Button {
                            newRule = RuleEditForm.blank(interface: interface)
                        } label: {
                            Label("New rule", systemImage: "plus")
                        }
                    case .nat:
                        Button {
                            newForward = PortForwardEditForm.blank(interface: interface)
                        } label: {
                            Label("New forward", systemImage: "plus")
                        }
                    }
                    // Exhaustive, with no `default`. A third pane added later
                    // has to decide what its plus button does rather than
                    // silently getting none.
                }
            }
        }
        // `item:` rather than `isPresented:` — the form is the reason the
        // sheet is open, so they cannot disagree about which rule is being
        // drafted.
        .sheet(item: $newRule) { form in
            RuleEditSheet(form: form,
                          interfaces: store.interfaces.map(\.internalName).compactMap { $0 },
                          aliases: Set(store.aliases.map(\.name)),
                          ruleset: store.rules,
                          subject: form.apply(to: FirewallRule(JSONDict([
                              "tracker": .string(""),
                              "interface": .string(form.interface)
                          ]))),
                          onSave: { saved in await createRule(saved) })
        }
        .sheet(item: $newForward) { form in
            PortForwardEditSheet(form: form,
                                 interfaces: store.interfaces.map(\.internalName).compactMap { $0 },
                                 aliases: Set(store.aliases.map(\.name)),
                                 onSave: { saved in await createForward(saved) })
        }
    }

    /// Write a new port forward and refresh.
    ///
    /// Through the same coordinator as an edit: rate limit, audit, read-back.
    private func createForward(_ form: PortForwardEditForm) async -> Bool {
        let dict = form.toDict(interface: form.interface)
        do {
            _ = try await store.writeCoordinator.execute(
                .saveNatRule(
                    rule: dict,
                    displayName: form.descr.isEmpty ? "new forward on \(form.interface)" : form.descr
                )
            )
            await store.refreshManually()
            return true
        } catch {
            return false
        }
    }

    /// Write a new rule and refresh.
    ///
    /// Goes through the same coordinator as an edit — rate limit, audit,
    /// read-back — because a create is a write like any other. The only
    /// difference is that the firewall assigns the tracker.
    private func createRule(_ form: RuleEditForm) async -> Bool {
        let dict = form.toDict(tracker: "", interface: form.interface)
        do {
            _ = try await store.writeCoordinator.execute(
                .saveRule(
                    rule: dict,
                    displayName: form.descr.isEmpty ? "new rule on \(form.interface)" : form.descr
                )
            )
            await store.refreshManually()
            return true
        } catch {
            return false
        }
    }

    // MARK: Rules

    /// The interfaces that have rules, labelled the way the firewall labels
    /// them. Rules reference pfSense's internal handle — "lan", "opt7" — which
    /// is not what anybody calls the VLAN.
    /// One chip per interface, not one per combination.
    ///
    /// A floating rule names every interface it applies to, so the raw values
    /// produced chips like "OPENVPN1, OPENVPN2 +11" — a filter for a set
    /// nobody thinks in. Splitting them means OPENVPN1 is a chip, and choosing
    /// it shows every rule that applies to OPENVPN1 including the floating
    /// ones.
    private var interfaceOptions: [String] {
        cachedInterfaceOptions
    }

    private var filteredRules: [FirewallRule] {
        // No selection shows everything, floating included: with the All chip
        // gone, "nothing selected" is the way to see the whole set.
        var list = showFloating
            ? store.rules.filter(\.isFloating)
            : store.rules
        if let iface = interfaceFilter {
            list = list.filter { rule in
                rule.interfaceName.split(separator: ",")
                    .contains { $0.trimmingCharacters(in: .whitespaces) == iface }
            }
        }
        guard !query.isEmpty else { return list }
        let q = query.lowercased()
        return list.filter { matches($0, q) }
    }

    /// Whether a rule matches, including through its aliases.
    ///
    /// The rows show addresses and ports, not alias names — so searching only
    /// the raw fields meant typing `443` or `172.16.1.43` found nothing while
    /// the rule showing exactly those numbers sat on screen. What is displayed
    /// has to be what is searched.
    private func matches(_ rule: FirewallRule, _ q: String) -> Bool {
        if rule.descr.lowercased().contains(q) { return true }
        if (rule.proto ?? "").lowercased().contains(q) { return true }
        if rule.interfaceName.lowercased().contains(q) { return true }

        // The name as written, and everything it stands for.
        for field in [rule.sourceSide.address, rule.destinationSide.address,
                      rule.sourceSide.port ?? "", rule.destinationSide.port ?? ""]
        where !field.isEmpty {
            if field.lowercased().contains(q) { return true }
            if let members = store.resolveAlias(field),
               members.contains(where: { $0.lowercased().contains(q) }) {
                return true
            }
        }
        return false
    }

    @ViewBuilder
    private var rulesPane: some View {
        if let err = store.errors[.firewall] {
            Notice(symbol: "exclamationmark.triangle", title: "Rules unavailable", detail: err, health: .warn)
        } else if filteredRules.isEmpty {
            let title = showFloating ? "No floating rules" : "No rules returned"
            Notice(symbol: "shield.slash", title: query.isEmpty ? title : "No matches")
        } else {
            countLine("\(filteredRules.count) rules")
            ForEach(filteredRules) { rule in
                Button { selection = rule.id } label: { RuleRow(rule: rule) }
                    .buttonStyle(.plain)
            }
        }
    }

    // MARK: NAT

    private var filteredForwards: [PortForward] {
        guard !query.isEmpty else { return store.portForwards }
        let q = query.lowercased()
        return store.portForwards.filter { matches($0, q) }
    }

    /// Whether a port forward matches, including through its aliases.
    private func matches(_ pf: PortForward, _ q: String) -> Bool {
        if pf.descr.lowercased().contains(q) { return true }
        if (pf.proto ?? "").lowercased().contains(q) { return true }
        if pf.interfaceName.lowercased().contains(q) { return true }

        for field in [pf.destinationSide.address, pf.target,
                      pf.destinationSide.port ?? "", pf.localPort ?? ""]
        where !field.isEmpty {
            if field.lowercased().contains(q) { return true }
            if let members = store.resolveAlias(field),
               members.contains(where: { $0.lowercased().contains(q) }) {
                return true
            }
        }
        return false
    }

    @ViewBuilder
    private var natPane: some View {
        if let err = store.errors[.portForwards] {
            Notice(symbol: "exclamationmark.triangle", title: "NAT unavailable", detail: err, health: .warn)
        } else if filteredForwards.isEmpty {
            Notice(symbol: "arrow.left.arrow.right", title: query.isEmpty ? "No port forwards" : "No matches")
        } else {
            countLine("\(filteredForwards.count) port forwards")
            ForEach(filteredForwards) { pf in
                Button { selection = pf.id } label: {
                    Slab(rail: pf.health, trailing: store.interfaceLabel(for: pf.interfaceName)) {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 8) {
                                Text((pf.proto ?? "any").uppercased())
                                    .scaledFont(10, weight: .semibold, design: .monospaced)
                                    .foregroundStyle(theme.labelFaint)
                                if pf.disabled { StatusPill(text: "disabled", health: .idle) }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .scaledFont(10, weight: .semibold)
                                    .foregroundStyle(theme.labelFaint)
                            }
                            // Same shape as a rule, because they are read the
                            // same way — the only difference is that a forward
                            // has somewhere it sends the traffic on to.
                            natField("TO", store.resolvedValue(pf.destinationSide.address))
                            natField("SENDS", store.resolvedValue(pf.target))
                            if let port = natPorts(pf) { natField("PORT", port) }
                            if !pf.descr.isEmpty {
                                natField("DESC", pf.descr, mono: false)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The port it arrives on, and the port it is sent to when they differ.
    private func natPorts(_ pf: PortForward) -> String? {
        let arriving = pf.destinationSide.port.map { store.resolvedValue($0) }
        let local = pf.localPort.map { store.resolvedValue($0) }
        switch (arriving, local) {
        case let (a?, l?) where a != l: return "\(a) → \(l)"
        case let (a?, _): return a
        case let (nil, l?): return l
        case (nil, nil): return nil
        }
    }

    private func natField(_ label: String, _ value: String, mono: Bool = true) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .scaledFont(9, weight: .semibold)
                .foregroundStyle(theme.labelFaint)
                .frame(width: 44, alignment: .leading)
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

    // MARK: Aliases

    // MARK: Bits

    private func countLine(_ text: String) -> some View {
        HStack {
            Text(text)
                .scaledFont(12, design: .monospaced)
                .foregroundStyle(theme.labelFaint)
            Spacer()
        }
    }

    private func chip(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .scaledFont(12, weight: .medium, design: .monospaced)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(selected ? theme.accentColor : theme.card)
                .foregroundStyle(selected ? theme.palette.crust : theme.labelMuted)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

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
struct RuleRow: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore
    let rule: FirewallRule

    var body: some View {
        Slab(rail: rule.health, trailing: store.interfaceLabel(for: rule.interfaceName)) {
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

                field("FROM", store.resolvedValue(rule.sourceSide.address))
                field("TO", store.resolvedValue(rule.destinationSide.address))

                if let port = ports {
                    field("PORT", port)
                }
                if !rule.descr.isEmpty {
                    field("DESC", rule.descr, mono: false)
                }
            }
        }
    }

    /// Both ports, if either is set. A source port is rare enough that
    /// labelling it separately in a list would waste a row on every rule that
    /// does not have one.
    private var ports: String? {
        let source = rule.sourceSide.port.map { store.resolvedValue($0) }
        let destination = rule.destinationSide.port.map { store.resolvedValue($0) }
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

    @State private var showDeleteConfirm = false
    @State private var showEditSheet = false
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

                GroupHeading(text: "Matches")
                Slab(rail: .info) {
                    VStack(alignment: .leading, spacing: 8) {
                        detailField("From", rule.sourceSide.address)
                        if let port = rule.sourceSide.port, !port.isEmpty {
                            detailField("Source port", port)
                        }
                        detailField("To", rule.destinationSide.address)
                        if let port = rule.destinationSide.port, !port.isEmpty {
                            detailField("Port", port)
                        }
                    }
                }

                GroupHeading(text: "Rule")
                Slab(rail: .idle) {
                    VStack(alignment: .leading, spacing: 4) {
                        FieldRow(key: "Interface",
                                 value: store.interfaceLabel(for: rule.interfaceName)
                                     ?? rule.interfaceName)
                        if let ipProtocol = rule.ipProtocol, !ipProtocol.isEmpty {
                            FieldRow(key: "IP version", value: ipProtocol)
                        }
                        FieldRow(key: "Logged", value: rule.logged ? "yes" : "no", mono: false)
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
                            showEditSheet = true
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
                            showDeleteConfirm = true
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
                // Duplicate rather than "new rule like this": the copy opens
                // in the editor and is not written until it is reviewed, so
                // this is a starting point rather than an action.
                Menu {
                    Button {
                        editorForm = RuleEditForm.duplicating(rule)
                        showEditSheet = true
                    } label: {
                        Label("Duplicate", systemImage: "plus.square.on.square")
                    }
                    // The simulation was reachable only from its own
                    // `#Preview` — an entire feature nobody could open.
                    Button {
                        showSimulation = true
                    } label: {
                        Label("Test against the log", systemImage: "waveform.badge.magnifyingglass")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .disabled(isSaving)
            }
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Close") { dismiss() }
                }
            }
        }
        .confirmationSheet(
            isPresented: $showDeleteConfirm,
            title: "Delete rule",
            message: store.writeCoordinator.preview(for: deleteOperation),
            destructive: true,
            destructiveLabel: "Delete",
            confirmLabel: "Cancel",
            onConfirm: confirmDelete,
            onCancel: {}
        )
        // Built here, at presentation, rather than in `onAppear`.
        //
        // This is why the editor felt slow. The form was assembled in the
        // detail view's `onAppear` and the sheet rendered "Loading…" until it
        // arrived — for a struct copied synchronously out of a rule the view
        // already held. There was never anything to load; the spinner was the
        // whole delay, and on a fast tap it was what you got.
        .sheet(isPresented: $showEditSheet) {
            RuleEditSheet(form: editorForm ?? RuleEditForm(from: rule),
                          interfaces: store.interfaces.map(\.internalName).compactMap { $0 },
                          aliases: Set(store.aliases.map(\.name)),
                          ruleset: store.rules,
                          subject: rule,
                          onSave: { saved in await save(changes: saved) })
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
            await store.refresh()
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
    @discardableResult
    private func save(changes: RuleEditForm) async -> Bool {
        do {
            // The interface comes from the form now. It was taken from the
            // rule, so moving a rule between interfaces in the editor
            // changed the screen and not the firewall.
            _ = try await store.writeCoordinator.execute(
                .saveRule(
                    rule: changes.toDict(tracker: rule.tracker, interface: changes.interface),
                    displayName: rule.descr.isEmpty ? rule.tracker : rule.descr
                )
            )

            // Refreshed but not dismissed. The rule that was just edited is
            // the thing somebody wants to look at to check it took.
            Task { await store.refresh() }
            return true
        } catch {
            writeError = WriteError.from(error, operation: .other)
            showErrorAlert = true
            return false
        }
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

/// One port forward, in full.
struct PortForwardDetailView: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore
    @Environment(\.dismiss) private var dismiss
    let forward: PortForward

    @State private var showDeleteConfirm = false
    @State private var showEditSheet = false
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
                        detailField("From", forward.sourceSide.address)
                        detailField("To", forward.destinationSide.address)
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
                            detailField("Local port", local)
                        }
                    }
                }

                AdministrationModeNotice()

                if !isSaving {
                    VStack(spacing: 8) {
                        Button {
                            editorForm = PortForwardEditForm(from: forward)
                            showEditSheet = true
                        } label: {
                            Label("Edit Forward", systemImage: "pencil")
                                .scaledFont(14, weight: .medium)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(theme.accentColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete Forward", systemImage: "trash")
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
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                // The copy opens in the editor and is not written until it is
                // reviewed. Its destination port is cleared: two forwards on
                // one interface sharing a port is a conflict pfSense accepts
                // and only one of them will work.
                Button {
                    editorForm = PortForwardEditForm.duplicating(forward)
                    showEditSheet = true
                } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                .disabled(isSaving)
            }
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Close") { dismiss() }
                }
            }
        }
        // Same as the rule editor: assembled at presentation, because there is
        // nothing to fetch and the spinner was the entire delay.
        .sheet(isPresented: $showEditSheet) {
            PortForwardEditSheet(form: editorForm ?? PortForwardEditForm(from: forward),
                                 interfaces: store.interfaces.map(\.internalName).compactMap { $0 },
                                 aliases: Set(store.aliases.map(\.name)),
                                 onSave: { saved in await save(changes: saved) })
        }
        .confirmationSheet(
            isPresented: $showDeleteConfirm,
            title: "Delete port forward",
            message: store.writeCoordinator.preview(for: deleteOperation),
            destructive: true,
            destructiveLabel: "Delete",
            confirmLabel: "Cancel",
            onConfirm: confirmDelete,
            onCancel: {}
        )
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
            await store.refresh()
        } catch {
            writeError = WriteError.from(error, operation: .other)
            showErrorAlert = true
        }
    }

    @discardableResult
    private func save(changes: PortForwardEditForm) async -> Bool {
        do {
            // From the form, not the forward: the editor offers an
            // interface field and it was being ignored on save.
            _ = try await store.writeCoordinator.execute(
                .saveNatRule(
                    rule: changes.toDict(interface: changes.interface),
                    displayName: forward.descr.isEmpty ? forward.id : forward.descr
                )
            )

            Task { await store.refresh() }
            return true
        } catch {
            writeError = WriteError.from(error, operation: .other)
            showErrorAlert = true
            return false
        }
    }

    /// Every address or port behind a value, one per line. Same as the rule
    /// screen's; both types need it and neither owns the other.
    private func expandedValues(_ value: String) -> [String] {
        store.resolveAlias(value) ?? [value]
    }
}

/// Editable representation of a firewall rule.
struct RuleEditForm: Equatable, Identifiable {
    /// Identity for `sheet(item:)`. A draft is one thing at a time, and the
    /// interface it is being written for is what distinguishes one draft from
    /// the next.
    var id: String { "\(isCreating ? "new" : "edit")-\(interface)-\(descr)" }

    var descr: String
    var type: String
    var proto: String
    var interface: String
    var sourceAddress: String
    var sourcePort: String
    var destinationAddress: String
    var destinationPort: String
    var disabled: Bool
    var logged: Bool
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
            "source": .object(["address": .string("any")]),
            "destination": .object(["address": .string("any")])
        ])))
        form.isCreating = true
        return form
    }

    /// A copy of an existing rule, ready to be saved as another one.
    ///
    /// The description is marked rather than left identical. Two rules with
    /// the same description in a list of ninety-eight is how somebody edits
    /// the wrong one later.
    static func duplicating(_ rule: FirewallRule) -> RuleEditForm {
        var form = RuleEditForm(from: rule)
        form.isCreating = true
        form.descr = rule.descr.isEmpty ? "Copy" : "\(rule.descr) (copy)"
        // A copy starts disabled for the same reason a new rule does.
        form.disabled = true
        return form
    }

    init(from rule: FirewallRule) {
        descr = rule.descr
        type = rule.type
        proto = rule.proto ?? ""
        interface = rule.interfaceName
        addressFamily = rule.ipProtocol ?? "inet"
        sourceAddress = rule.sourceSide.address
        sourcePort = rule.sourceSide.port ?? ""
        destinationAddress = rule.destinationSide.address
        destinationPort = rule.destinationSide.port ?? ""
        disabled = rule.disabled
        logged = rule.logged
    }

    func apply(to rule: FirewallRule) -> FirewallRule {
        FirewallRule(JSONDict([
            "tracker": .string(rule.tracker),
            "interface": .string(interface),
            "type": .string(type),
            "ipprotocol": .string(addressFamily),
            "protocol": proto.isEmpty ? .string("any") : .string(proto),
            "source": .object(["address": .string(sourceAddress)]),
            "source_port": sourcePort.isEmpty ? .null : .string(sourcePort),
            "destination": .object(["address": .string(destinationAddress)]),
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
            "source": .object(["address": .string(sourceAddress)]),
            "destination": .object(["address": .string(destinationAddress)]),
            "descr": .string(descr),
            "disabled": .bool(disabled),
            "log": .bool(logged)
        ]
        if !sourcePort.isEmpty {
            dict["source_port"] = .string(sourcePort)
        }
        if !destinationPort.isEmpty {
            dict["destination_port"] = .string(destinationPort)
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
    let interfaces: [String]
    /// Alias names this firewall has, so a field naming one that does not
    /// exist is caught here rather than by pfSense refusing to load the rule.
    let aliases: Set<String>
    /// The ruleset this rule lives in, for working out where it sits and what
    /// above it already catches the same traffic.
    let ruleset: [FirewallRule]
    /// The rule as the firewall currently has it, which is what gets placed —
    /// the edited copy is not in the ruleset yet.
    let subject: FirewallRule
    let onSave: (RuleEditForm) async -> Bool

    @State private var edited: RuleEditForm
    @State private var isSaving = false
    @State private var showSaveConfirmation = false

    init(form: RuleEditForm, interfaces: [String], aliases: Set<String>,
         ruleset: [FirewallRule], subject: FirewallRule,
         onSave: @escaping (RuleEditForm) async -> Bool) {
        self.interfaces = interfaces
        self.aliases = aliases
        self.ruleset = ruleset
        self.subject = subject
        self.onSave = onSave
        self.original = form
        _edited = State(initialValue: form)
    }

    private var problems: [FieldValidator.Problem] {
        FieldValidator.problems(inRule: edited, aliases: aliases)
    }

    /// Where this rule sits, computed against the rule as edited.
    ///
    /// Against the edited form rather than the stored rule: changing the
    /// interface or widening the source moves it and changes what precedes it,
    /// and a placement describing where it *used* to sit would be worse than
    /// none.
    private var placement: RulePlacement.Placement {
        RulePlacement.analyse(edited.apply(to: subject), in: ruleset)
    }

    /// What the rule looked like when the sheet opened.
    ///
    /// Kept so Save can be disabled until something actually changed. An
    /// unchanged save is a write to a firewall that alters nothing, spends the
    /// rate limit, and puts a line in the audit trail saying an edit happened.
    private let original: RuleEditForm

    private var isDirty: Bool { edited != original }

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
                            EditChoice(label: "Interface", options: interfaces,
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
                            EditField(label: "Address", text: $edited.sourceAddress,
                                      prompt: "any, an address, or an alias")
                            EditField(label: "Port", text: $edited.sourcePort,
                                      prompt: "blank for any")
                        }
                    }

                    Slab(rail: .info, title: "Destination") {
                        VStack(alignment: .leading, spacing: 12) {
                            EditField(label: "Address", text: $edited.destinationAddress,
                                      prompt: "any, an address, or an alias")
                            EditField(label: "Port", text: $edited.destinationPort,
                                      prompt: "blank for any")
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
                            showSaveConfirmation = true
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
            .confirmationSheet(
                isPresented: $showSaveConfirmation,
                title: edited.isCreating ? "Review new rule" : "Review rule changes",
                message: changePreview,
                destructive: false,
                destructiveLabel: "Save rule",
                confirmLabel: "Cancel",
                onConfirm: saveConfirmed,
                onCancel: {}
            )
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
            text += "\n\nAppended as rule \(place.total) of \(place.total)."
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
        Self.describe("Source port", original.sourcePort, edited.sourcePort, into: &changes)
        Self.describe("Destination", original.destinationAddress, edited.destinationAddress, into: &changes)
        Self.describe("Destination port", original.destinationPort, edited.destinationPort, into: &changes)
        Self.describe("Description", original.descr, edited.descr, into: &changes)
        if original.disabled != edited.disabled { changes.append("Disabled: \(original.disabled ? "yes" : "no") → \(edited.disabled ? "yes" : "no")") }
        if original.logged != edited.logged { changes.append("Logging: \(original.logged ? "on" : "off") → \(edited.logged ? "on" : "off")") }

        var text = "The coordinator will apply and read back:\n\n"
            + changes.map { "• \($0)" }.joined(separator: "\n")

        // Position belongs here as much as in the editor. A rule is only as
        // good as where it sits, and this sheet is the last thing read before
        // a firewall changes.
        let place = placement
        if let position = place.position {
            text += "\n\nPosition \(position) of \(place.total) on \(edited.interface)."
        } else {
            text += "\n\nAppended as rule \(place.total) of \(place.total) on \(edited.interface)."
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

    private func saveConfirmed() async {
        isSaving = true
        let saved = await onSave(edited)
        isSaving = false
        if saved { dismiss() }
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
    var destinationAddress: String
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
            "source": .object(["address": .string("any")]),
            "destination": .object(["address": .string("")]),
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
        destinationAddress = forward.destinationSide.address
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
            "source": .object(["address": .string(sourceAddress)]),
            "destination": .object(["address": .string(destinationAddress)]),
            "target": .string(targetAddress),
            "descr": .string(descr),
            "disabled": .bool(disabled)
        ]
        if !destinationPort.isEmpty {
            dict["destination_port"] = .string(destinationPort)
        }
        if !localPort.isEmpty {
            dict["local_port"] = .string(localPort)
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
                    Text("This will be appended to the end of the interface's rules, which is where new rules land and rarely where they are wanted.")
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
        placement.isNew ? "new" : "\(placement.position ?? 0) of \(placement.total)"
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

    let interfaces: [String]
    let aliases: Set<String>
    let onSave: (PortForwardEditForm) async -> Bool

    @State private var edited: PortForwardEditForm
    @State private var isSaving = false
    @State private var showSaveConfirmation = false

    private let original: PortForwardEditForm

    private var isDirty: Bool { edited != original }

    init(form: PortForwardEditForm, interfaces: [String], aliases: Set<String>,
         onSave: @escaping (PortForwardEditForm) async -> Bool) {
        self.interfaces = interfaces
        self.aliases = aliases
        self.onSave = onSave
        self.original = form
        _edited = State(initialValue: form)
    }

    private var problems: [FieldValidator.Problem] {
        FieldValidator.problems(inForward: edited, aliases: aliases)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Slab(rail: .info, title: "Forward") {
                        VStack(alignment: .leading, spacing: 12) {
                            EditField(label: "Description", text: $edited.descr,
                                      prompt: "What this forward is for", mono: false)
                            EditChoice(label: "Interface", options: interfaces,
                                       selection: $edited.interface)
                            EditChoice(label: "Protocol", options: FirewallVocabulary.protocols,
                                       selection: $edited.proto)
                            EditChoice(label: "IP version",
                                       options: FirewallVocabulary.addressFamilies,
                                       selection: $edited.addressFamily)
                        }
                    }

                    Slab(rail: .info, title: "Matched traffic") {
                        VStack(alignment: .leading, spacing: 12) {
                            EditField(label: "Source address", text: $edited.sourceAddress,
                                      prompt: "any, an address, or an alias")
                            EditField(label: "Destination address",
                                      text: $edited.destinationAddress,
                                      prompt: "usually this interface's address")
                            EditField(label: "Destination port",
                                      text: $edited.destinationPort,
                                      prompt: "the port on the outside")
                        }
                    }

                    Slab(rail: .info, title: "Sent to") {
                        VStack(alignment: .leading, spacing: 12) {
                            EditField(label: "Target address", text: $edited.targetAddress,
                                      prompt: "the host inside")
                            EditField(label: "Local port", text: $edited.localPort,
                                      prompt: "blank to keep the same port")
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
                            showSaveConfirmation = true
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
            .confirmationSheet(
                isPresented: $showSaveConfirmation,
                title: edited.isCreating ? "Review new port forward" : "Review port-forward changes",
                message: changePreview,
                destructive: false,
                destructiveLabel: "Save forward",
                confirmLabel: "Cancel",
                onConfirm: saveConfirmed,
                onCancel: {}
            )
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
        Self.describe("Destination", original.destinationAddress, edited.destinationAddress, into: &changes)
        Self.describe("Destination port", original.destinationPort, edited.destinationPort, into: &changes)
        Self.describe("Target", original.targetAddress, edited.targetAddress, into: &changes)
        Self.describe("Local port", original.localPort, edited.localPort, into: &changes)
        Self.describe("Description", original.descr, edited.descr, into: &changes)
        if original.disabled != edited.disabled { changes.append("Disabled: \(original.disabled ? "yes" : "no") → \(edited.disabled ? "yes" : "no")") }
        return "The coordinator will apply and read back:\n\n" + changes.map { "• \($0)" }.joined(separator: "\n")
    }

    private static func describe(_ label: String, _ before: String, _ after: String,
                                 into changes: inout [String]) {
        guard before != after else { return }
        changes.append("\(label): \(before.isEmpty ? "any" : before) → \(after.isEmpty ? "any" : after)")
    }

    private func saveConfirmed() async {
        isSaving = true
        let saved = await onSave(edited)
        isSaving = false
        if saved { dismiss() }
    }
}
