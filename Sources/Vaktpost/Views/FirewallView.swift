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

    var body: some View {
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
    private var interfaceOptions: [String] {
        Array(Set(store.rules.map(\.interfaceName))).sorted {
            (store.interfaceLabel(for: $0) ?? $0) < (store.interfaceLabel(for: $1) ?? $1)
        }
    }

    private var filteredRules: [FirewallRule] {
        var list = store.rules
        if let iface = interfaceFilter { list = list.filter { $0.interfaceName == iface } }
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
            ForEach(filteredRules) { RuleRow(rule: $0) }
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
                NavigationLink {
                    PortForwardDetailView(forward: pf)
                } label: {
                    Slab(rail: pf.health, trailing: store.interfaceLabel(for: pf.interfaceName)) {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 8) {
                                Text((pf.proto ?? "any").uppercased())
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(theme.labelFaint)
                                if pf.disabled { StatusPill(text: "disabled", health: .idle) }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(theme.labelFaint)
                            }
                            Text(pf.descr.isEmpty
                                 ? "\(pf.destinationSide.address) → \(pf.target)"
                                 : pf.descr)
                                .font(.system(size: 13))
                                .foregroundStyle(pf.descr.isEmpty ? theme.labelMuted : theme.label)
                                .lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Aliases

    // MARK: Bits

    private func countLine(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(theme.labelFaint)
            Spacer()
        }
    }

    private func chip(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
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
struct RuleRow: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var store: DashboardStore
    let rule: FirewallRule

    var body: some View {
        NavigationLink {
            RuleDetailView(rule: rule)
        } label: {
            Slab(rail: rule.health, trailing: store.interfaceLabel(for: rule.interfaceName)) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        StatusPill(text: rule.type.uppercased(), health: rule.health)
                        Text(rule.protoLabel)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(theme.labelFaint)
                        if rule.disabled {
                            StatusPill(text: "disabled", health: .idle)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(theme.labelFaint)
                    }

                    // The description if there is one, because that is what
                    // the person who wrote the rule meant it to say. Only when
                    // there is not does the row fall back to addresses.
                    if !rule.descr.isEmpty {
                        Text(rule.descr)
                            .font(.system(size: 13))
                            .foregroundStyle(theme.label)
                            .lineLimit(1)
                    } else {
                        Text(summary)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(theme.label)
                            .lineLimit(1)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// A one-line form for rules with no description. Alias names rather than
    /// their contents: a resolved list wraps, and this line must not.
    private var summary: String {
        let to = rule.destinationSide.port.map { "\(rule.destinationSide.address):\($0)" }
            ?? rule.destinationSide.address
        return "\(rule.sourceSide.address) → \(to)"
    }
}

/// One rule, in full.
struct RuleDetailView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var store: DashboardStore
    let rule: FirewallRule

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Slab(rail: rule.health, trailing: store.interfaceLabel(for: rule.interfaceName)) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            StatusPill(text: rule.type.uppercased(), health: rule.health)
                            Text(rule.protoLabel)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(theme.labelMuted)
                            Spacer()
                            if rule.disabled { StatusPill(text: "disabled", health: .idle) }
                        }
                        if !rule.descr.isEmpty {
                            Text(rule.descr)
                                .font(.system(size: 14))
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
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(theme.labelFaint)
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(theme.label)
                .textSelection(.enabled)
            if let members = store.resolveAlias(value), !members.isEmpty {
                Text(members.joined(separator: ", "))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(theme.labelMuted)
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
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(theme.labelMuted)
                            Spacer()
                            if forward.disabled { StatusPill(text: "disabled", health: .idle) }
                        }
                        if !forward.descr.isEmpty {
                            Text(forward.descr)
                                .font(.system(size: 14))
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

    @ViewBuilder
    private func aliasField(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(theme.labelFaint)
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(theme.label)
                .textSelection(.enabled)
            if let members = store.resolveAlias(value), !members.isEmpty {
                Text(members.joined(separator: ", "))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(theme.labelMuted)
            }
        }
    }
}
