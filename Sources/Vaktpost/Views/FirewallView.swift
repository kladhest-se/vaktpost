import SwiftUI

struct FirewallView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var store: DashboardStore

    enum Pane: String, CaseIterable, Identifiable {
        case rules = "Rules", nat = "NAT"
        var id: String { rawValue }
    }

    @State private var pane: Pane = .rules
    @State private var query = ""
    @State private var interfaceFilter: String?

    @State private var selection: String?

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
    }

    private var listColumn: some View {
        VStack(spacing: 0) {
            Picker("", selection: $pane) {
                ForEach(Pane.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if pane == .rules, !interfaceOptions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip("All", selected: interfaceFilter == nil) { interfaceFilter = nil }
                        ForEach(interfaceOptions, id: \.self) { iface in
                            chip(store.interfaceLabel(for: iface) ?? iface,
                                 selected: interfaceFilter == iface) {
                                interfaceFilter = interfaceFilter == iface ? nil : iface
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 8)
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
        .searchable(text: $query, prompt: "Search description, address or port")
        .navigationTitle("Firewall")
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
        var seen = Set<String>()
        for rule in store.rules {
            for part in rule.interfaceName.split(separator: ",") {
                seen.insert(part.trimmingCharacters(in: .whitespaces))
            }
        }
        return seen.sorted {
            (store.interfaceLabel(for: $0) ?? $0) < (store.interfaceLabel(for: $1) ?? $1)
        }
    }

    private var filteredRules: [FirewallRule] {
        var list = store.rules
        if let iface = interfaceFilter {
            // Contains, not equals: a floating rule applying to thirteen
            // interfaces belongs under each of them.
            list = list.filter { rule in
                rule.interfaceName.split(separator: ",")
                    .contains { $0.trimmingCharacters(in: .whitespaces) == iface }
            }
        }
        guard !query.isEmpty else { return list }
        let q = query.lowercased()
        return list.filter {
            $0.descr.lowercased().contains(q)
                || $0.source.lowercased().contains(q)
                || $0.destination.lowercased().contains(q)
                || ($0.proto ?? "").lowercased().contains(q)
        }
    }

    @ViewBuilder
    private var rulesPane: some View {
        if let err = store.errors[.firewall] {
            Notice(symbol: "exclamationmark.triangle", title: "Rules unavailable", detail: err, health: .warn)
        } else if filteredRules.isEmpty {
            Notice(symbol: "shield.slash", title: query.isEmpty ? "No rules returned" : "No matches")
        } else {
            countLine("\(filteredRules.count) of \(store.rules.count) rules")
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
        return store.portForwards.filter {
            $0.descr.lowercased().contains(q)
                || $0.destination.lowercased().contains(q)
                || $0.target.lowercased().contains(q)
        }
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
        default: return nil
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
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var store: DashboardStore
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
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var store: DashboardStore
    let rule: FirewallRule

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
                            // The tracker is how you find this exact rule in
                            // the webConfigurator, which is where you would go
                            // to change it.
                            FieldRow(key: "Tracker", value: rule.tracker)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationTitle(rule.descr.isEmpty ? "Rule" : rule.descr)
        .navigationBarTitleDisplayMode(.inline)
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
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var store: DashboardStore
    let forward: PortForward

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
                        aliasField("From", forward.sourceSide.address)
                        aliasField("To", forward.destinationSide.address)
                        if let port = forward.destinationSide.port, !port.isEmpty {
                            aliasField("Port", port)
                        }
                    }
                }

                GroupHeading(text: "Forwards to")
                Slab(rail: .ok) {
                    VStack(alignment: .leading, spacing: 8) {
                        aliasField("Target", forward.target)
                        if let local = forward.localPort, !local.isEmpty {
                            aliasField("Local port", local)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationTitle(forward.descr.isEmpty ? "Port forward" : forward.descr)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Every address or port behind a value, one per line. Same as the rule
    /// screen's; both types need it and neither owns the other.
    private func expandedValues(_ value: String) -> [String] {
        store.resolveAlias(value) ?? [value]
    }

    @ViewBuilder
    private func aliasField(_ label: String, _ value: String) -> some View {
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
