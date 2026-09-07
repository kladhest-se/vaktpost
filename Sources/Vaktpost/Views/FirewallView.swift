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
                Slab(rail: pf.health, trailing: store.interfaceLabel(for: pf.interfaceName)) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(pf.descr.isEmpty ? "(no description)" : pf.descr)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(pf.descr.isEmpty ? theme.labelFaint : theme.label)
                            Spacer()
                            if pf.disabled { StatusPill(text: "disabled", health: .idle) }
                        }
                        natField("Protocol", (pf.proto ?? "any").uppercased())
                        // Shown only when it narrows anything. "From any" on
                        // every forward is a row that never varies, which is a
                        // row nobody reads.
                        if pf.sourceSide.address != "any" {
                            natField("From", store.resolvedValue(pf.sourceSide.address))
                        }
                        natField("To", store.resolvedValue(pf.destinationSide.address))
                        if let port = pf.destinationSide.port, !port.isEmpty {
                            natField("Port", store.resolvedValue(port))
                        }
                        natField("Forwards to", store.resolvedValue(pf.target))
                        if let local = pf.localPort, !local.isEmpty {
                            natField("Local port", store.resolvedValue(local))
                        }
                    }
                }
            }
        }
    }

    private func natField(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(theme.labelFaint)
                .frame(width: 74, alignment: .leading)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(theme.label)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
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

struct RuleRow: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var store: DashboardStore
    let rule: FirewallRule

    /// A fixed-width label and a value that wraps under itself.
    ///
    /// The label column is narrow and constant so the values line up down the
    /// card; addresses are the thing being compared between rules, and ragged
    /// left edges make that harder than it needs to be.
    private func ruleField(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(theme.labelFaint)
                .frame(width: 58, alignment: .leading)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(theme.label)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    var body: some View {
        Slab(rail: rule.health, trailing: store.interfaceLabel(for: rule.interfaceName)) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    StatusPill(text: rule.type.isEmpty ? "rule" : rule.type, health: rule.health)
                    Text(rule.protoLabel)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(theme.labelFaint)
                    Spacer()
                    if rule.disabled { StatusPill(text: "disabled", health: .idle) }
                    if rule.logged {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.labelFaint)
                    }
                }
                // Labelled fields rather than one line of arrows.
                //
                // A resolved alias list followed by `→ wanip:80, 443` is a
                // wall: it wraps mid-address, and which
                // side is the source depends on spotting the arrow. Four short
                // rows say the same thing and can be read a line at a time.
                ruleField("From", store.resolvedValue(rule.sourceSide.address))
                if let port = rule.sourceSide.port, !port.isEmpty {
                    ruleField("Src port", store.resolvedValue(port))
                }
                ruleField("To", store.resolvedValue(rule.destinationSide.address))
                if let port = rule.destinationSide.port, !port.isEmpty {
                    ruleField("Port", store.resolvedValue(port))
                }

                if !rule.descr.isEmpty {
                    Text(rule.descr)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.labelMuted)
                }
            }
        }
    }
}

