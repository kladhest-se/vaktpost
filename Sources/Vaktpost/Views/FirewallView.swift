import SwiftUI

struct FirewallView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var store: DashboardStore

    enum Pane: String, CaseIterable, Identifiable {
        case rules = "Rules", nat = "NAT", aliases = "Aliases"
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
                            chip(iface, selected: interfaceFilter == iface) {
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
                    case .aliases: aliasesPane
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .refreshable { await store.refresh() }
        }
        .background(theme.bg.ignoresSafeArea())
        .searchable(text: $query, prompt: "Search description, address or port")
        .navigationTitle("Firewall")
    }

    // MARK: Rules

    private var interfaceOptions: [String] {
        Array(Set(store.rules.map(\.interfaceName))).sorted()
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
        if let err = store.errors[.rules] {
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
                Slab(rail: pf.health, trailing: pf.interfaceName) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(pf.descr.isEmpty ? "(no description)" : pf.descr)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(pf.descr.isEmpty ? theme.labelFaint : theme.label)
                            Spacer()
                            if pf.disabled { StatusPill(text: "disabled", health: .idle) }
                        }
                        FieldRow(key: (pf.proto ?? "any").uppercased(), value: "\(pf.destination) → \(pf.targetLabel)")
                    }
                }
            }
        }
    }

    // MARK: Aliases

    private var filteredAliases: [FirewallAliasEntry] {
        guard !query.isEmpty else { return store.aliases }
        let q = query.lowercased()
        return store.aliases.filter {
            $0.name.lowercased().contains(q)
                || ($0.descr ?? "").lowercased().contains(q)
                || $0.addresses.contains { $0.lowercased().contains(q) }
        }
    }

    @ViewBuilder
    private var aliasesPane: some View {
        if let err = store.errors[.aliases] {
            Notice(symbol: "exclamationmark.triangle", title: "Aliases unavailable", detail: err, health: .warn)
        } else if filteredAliases.isEmpty {
            Notice(symbol: "tag.slash", title: query.isEmpty ? "No aliases" : "No matches")
        } else {
            countLine("\(filteredAliases.count) aliases")
            ForEach(filteredAliases) { AliasRow(alias: $0) }
        }
    }

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
    let rule: FirewallRule

    var body: some View {
        Slab(rail: rule.health, trailing: rule.interfaceName) {
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
                Text("\(rule.source)  →  \(rule.destination)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.label)
                if !rule.descr.isEmpty {
                    Text(rule.descr)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.labelMuted)
                }
            }
        }
    }
}

struct AliasRow: View {
    @EnvironmentObject private var theme: ThemeManager
    let alias: FirewallAliasEntry
    @State private var expanded = false

    var body: some View {
        Slab(rail: .info, trailing: alias.type) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(alias.name)
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.label)
                    Spacer()
                    Text("\(alias.addresses.count)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(theme.labelFaint)
                }
                if let d = alias.descr, !d.isEmpty {
                    Text(d)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.labelMuted)
                }
                if !alias.addresses.isEmpty {
                    let shown = expanded ? alias.addresses : Array(alias.addresses.prefix(5))
                    ForEach(Array(shown.enumerated()), id: \.offset) { idx, addr in
                        HStack {
                            Text(addr)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(theme.label)
                            Spacer()
                            if idx < alias.details.count {
                                Text(alias.details[idx])
                                    .font(.system(size: 11))
                                    .foregroundStyle(theme.labelFaint)
                                    .lineLimit(1)
                            }
                        }
                    }
                    if alias.addresses.count > 5 {
                        Button {
                            withAnimation { expanded.toggle() }
                        } label: {
                            Text(expanded ? "Show less" : "Show all \(alias.addresses.count)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(theme.accentColor)
                        }
                    }
                }
            }
        }
    }
}
