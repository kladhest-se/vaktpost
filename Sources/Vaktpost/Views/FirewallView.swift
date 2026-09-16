import SwiftUI
import UniformTypeIdentifiers

struct FirewallView: View {
    @Environment(\.themeManager) var theme: ThemeManager
    @Environment(\.dashboardStore) var store: DashboardStore

    enum Pane: String, CaseIterable, Identifiable {
        case rules = "Rules", nat = "NAT"
        var id: String { rawValue }
    }

    @State var pane: Pane = .rules
    @State var showFloating = false
    @State var query = ""
    @State var interfaceFilter: String?
    @State private var cachedInterfaceOptions: [String] = []

    @State var selection: String?
    /// A new rule being drafted, if any. Nil closes the sheet.
    @State private var newRule: RuleEditForm?
    /// A new filter separator being drafted for the selected interface.
    @State private var newSeparator: SeparatorEditForm?
    /// A new separator in pfSense's flat NAT port-forward table.
    @State private var newNatSeparator: SeparatorEditForm?
    /// A new port forward being drafted.
    @State private var newForward: PortForwardEditForm?
    // No writeError/showErrorAlert here any more. createRule and
    // createForward used to catch here and stash an error on this view — the
    // view still covered by the edit sheet at the moment of failure, so the
    // alert could never actually show. They now rethrow and the sheet catches
    // it, since the sheet is what is on screen. Keeping dead state and a dead
    // alert modifier here would tell the next person reading this that errors
    // are handled at this level, which they no longer are.

    /// A drag's result, kept separate from the live data until it is saved.
    /// Nil means "show what the firewall actually has."
    @State var rulePendingOrder: [RuleListItem]?
    @State var ruleDraggingID: String?
    /// NAT uses its own complete flat order. The item remembers the original
    /// pfSense array position so trackerless WebUI-created forwards remain
    /// safely identifiable during the write.
    @State var natPendingOrder: [NatListItem]?
    @State var natDraggingID: String?
    @State var isSavingOrder = false
    /// This alert belongs directly on this view rather than a sheet it
    /// presents: the confirmation here is a single, unnested sheet, so this
    /// is already the topmost view when it dismisses — unlike the editor,
    /// nothing here is covering it.
    @State var reorderError: WriteError?
    @State var showReorderErrorAlert = false

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
                    RuleDetailView(rule: rule, selection: $selection)
                } else if let separator = store.filterSeparators.first(where: { $0.id == id }) {
                    SeparatorDetailView(separator: separator, scope: .filter)
                } else if let separator = store.natSeparators.first(where: { $0.id == id }) {
                    SeparatorDetailView(separator: separator, scope: .nat)
                } else if let pf = store.portForwards.first(where: { $0.id == id }) {
                    PortForwardDetailView(forward: pf, selection: $selection)
                } else {
                    Notice(symbol: "questionmark.circle",
                           title: "That rule is no longer in the list")
                }
            }
        )
        .task(id: store.activeProfile?.id) { updateInterfaceOptions() }
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

            if store.firewallChangesPending {
                NavigationLink {
                    FirewallReloadView()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(theme.warn)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Firewall changes are waiting")
                                .scaledFont(13, weight: .semibold)
                                .foregroundStyle(theme.label)
                            Text("Saved, but not active. Review and apply changes.")
                                .scaledFont(11)
                                .foregroundStyle(theme.labelMuted)
                        }
                        Spacer()
                        Text("Apply Changes")
                            .scaledFont(12, weight: .semibold)
                            .foregroundStyle(theme.warn)
                        Image(systemName: "chevron.right")
                            .scaledFont(10, weight: .semibold)
                            .foregroundStyle(theme.labelFaint)
                    }
                    .padding(12)
                    .background(theme.warn.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

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
        .task(id: store.activeProfile?.id) { await store.loadFirewallObjects() }
        .navigationTitle("Firewall")
        // Not on `orderChangedBar`, where this used to live. That bar exists
        // only `if ruleOrderIsDirty`, and `rulePendingOrder = nil` — which
        // runs in both the success AND the failure branch of
        // `saveRuleOrder()` — makes `ruleOrderIsDirty` false immediately.
        // On failure specifically, that removed the bar, and with it this
        // alert, at the exact moment the alert was needed: a SwiftUI alert
        // cannot present on a view that is no longer part of the hierarchy.
        // This is the identical shape of bug `RuleEditSheet` and
        // `PortForwardEditSheet` were already fixed for — an error caught on
        // a view that is not the one left on screen when it happens — and
        // this feature was built without carrying that lesson over. Anchored
        // here instead: the same stable, always-present container `.task`
        // and `.navigationTitle` already live on, so it exists whether or
        // not a reorder is in progress.
        .writeErrorAlert(isErrorPresented: $showReorderErrorAlert, error: $reorderError)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                // Keep one real toolbar item mounted at all times. When this
                // was an `if` inside ToolbarItem, opening Firewall on All or
                // Floating created an empty item; SwiftUI could keep that
                // empty navigation-bar snapshot after switching to NAT, so
                // its add action never appeared.
                Menu {
                    switch pane {
                    case .rules:
                        if let interface = interfaceFilter {
                            Button {
                                newRule = RuleEditForm.blank(interface: interface)
                            } label: {
                                Label("Rule", systemImage: "shield")
                            }
                            Button {
                                let ruleCount = store.rules.filter {
                                    !$0.isFloating && $0.interfaceName == interface
                                }.count
                                newSeparator = SeparatorEditForm.blank(
                                    interface: interface,
                                    position: ruleCount
                                )
                            } label: {
                                Label("Separator", systemImage: "rectangle.split.1x2")
                            }
                        }
                    case .nat:
                        // NAT is one flat table. This choice is independent
                        // of whichever Rules chip was previously selected.
                        Button {
                            newForward = PortForwardEditForm.blank(interface: defaultNatInterface)
                        } label: {
                            Label("Port Forward Rule", systemImage: "arrow.right.square")
                        }
                        Button {
                            newNatSeparator = SeparatorEditForm.blank(
                                interface: "nat",
                                position: store.portForwards.count
                            )
                        } label: {
                            Label("Separator", systemImage: "rectangle.split.1x2")
                        }
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                // Filter rules and separators need one concrete interface.
                // NAT does not, so moving from All/Floating to NAT enables
                // this same persistent item immediately.
                .disabled(pane == .rules && interfaceFilter == nil)
            }
        }
        // `item:` rather than `isPresented:` — the form is the reason the
        // sheet is open, so they cannot disagree about which rule is being
        // drafted.
        .sheet(item: $newRule) { form in
            RuleEditSheet(form: form,
                          interfaces: store.interfaces,
                          aliases: store.aliases,
                          ruleset: store.rules,
                          subject: form.apply(to: FirewallRule(JSONDict([
                              "tracker": .string(""),
                              "interface": .string(form.interface)
                          ])))) { saved in try await createRule(saved) }
        }
        .sheet(item: $newSeparator) { form in
            SeparatorEditSheet(
                form: form,
                rules: store.rules.filter {
                    !$0.isFloating && $0.interfaceName == form.interface
                }
            ) { saved in try await createSeparator(saved) }
        }
        .sheet(item: $newNatSeparator) { form in
            SeparatorEditSheet(
                form: form,
                forwards: store.portForwards
            ) { saved in try await createNatSeparator(saved) }
        }
        .sheet(item: $newForward) { form in
            PortForwardEditSheet(form: form,
                                 interfaces: store.interfaces,
                                 aliases: store.aliases) { saved in try await createForward(saved) }
        }
    }

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

    /// Best initial interface for a new NAT rule. The editor still exposes
    /// the interface picker; this is only its pfSense-like starting value.
    private var defaultNatInterface: String {
        if let selected = interfaceFilter,
           store.interfaces.contains(where: { $0.internalName == selected }) {
            return selected
        }
        if let wan = store.interfaces.first(where: { $0.internalName?.lowercased() == "wan" })?.internalName {
            return wan
        }
        return store.interfaces.compactMap(\.internalName).first
            ?? store.portForwards.first?.interfaceName
            ?? "wan"
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
