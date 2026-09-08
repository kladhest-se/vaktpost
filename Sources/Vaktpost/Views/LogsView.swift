import SwiftUI

struct LogsView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var store: DashboardStore

    enum Source: String, CaseIterable, Identifiable {
        case firewall = "Filter", system = "System", auth = "Auth"
        case dhcp = "DHCP", openvpn = "VPN"
        var id: String { rawValue }
    }

    enum ActionFilter: String, CaseIterable, Identifiable {
        case all = "All", blocked = "Blocked", passed = "Passed"
        var id: String { rawValue }
    }

    @State private var source: Source = .firewall
    @State private var action: ActionFilter = .all
    @State private var query = ""

    private var lines: [LogLine] {
        var list: [LogLine]
        switch source {
        case .firewall: list = store.firewallLog
        case .system:   list = store.systemLog
        case .auth:     list = store.authLog
        case .dhcp:     list = store.dhcpLog
        case .openvpn:  list = store.openvpnLog
        }
        if showsActionFilter {
            switch action {
            case .all: break
            case .blocked: list = list.filter { $0.health == .bad }
            case .passed: list = list.filter { $0.action == "pass" }
            }
        }
        guard !query.isEmpty else { return list }
        let q = query.lowercased()
        return list.filter { $0.text.lowercased().contains(q) }
    }

    private var errorKey: DashboardStore.Section {
        switch source {
        case .firewall: return .firewallLog
        case .system:   return .systemLog
        case .auth:     return .authLog
        case .dhcp:     return .dhcpLog
        case .openvpn:  return .openvpnLog
        }
    }

    /// Only the filter log carries a pass/block action, so the second picker
    /// would be four inert buttons on the other four sources.
    private var showsActionFilter: Bool { source == .firewall }

    var body: some View {
        ScrollView {
            PageHeader(title: "Logs", subtitle: nil)
            VStack(spacing: 8) {
                Picker("", selection: $source) {
                    ForEach(Source.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if showsActionFilter {
                    Picker("", selection: $action) {
                        ForEach(ActionFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            LazyVStack(alignment: .leading, spacing: 8) {
                if let err = store.errors[errorKey] {
                    Notice(symbol: "exclamationmark.triangle",
                           title: "Log unavailable", detail: err, health: .warn)
                } else if lines.isEmpty {
                    Notice(
                        symbol: "doc.text.magnifyingglass",
                        title: query.isEmpty ? "No log lines" : "No matches",
                        detail: query.isEmpty && (source == .dhcp || source == .openvpn)
                            ? "This log is empty when the service isn't running."
                            : nil
                    )
                } else {
                    ForEach(lines) { line in
                        // Every line opens. A filter line becomes fields;
                        // anything else gets its syslog prefix split off
                        // and its message given room to wrap, which is all
                        // a long DHCP or OpenVPN line needs.
                        NavigationLink {
                            LogDetailView(line: line)
                        } label: {
                            LogRow(line: line)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .background(theme.bg.ignoresSafeArea())
        .refreshable { await store.refreshManually() }
        .searchable(text: $query, prompt: "Search log text")
        .task { await store.beginSecondaryLogs() }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                // One document, not one item per line.
                //
                // The old sheet handed `UIActivityViewController` an array of
                // a hundred-odd separate strings, which it renders as an empty
                // page with a placeholder icon — it is trying to preview a
                // hundred documents at once. A log excerpt is one thing you
                // are sharing, so it travels as one string.
                ShareLink(
                    item: formattedLines.joined(separator: "\n"),
                    preview: SharePreview(
                        "\(source.rawValue) log — \(lines.count) lines"
                    )
                ) {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(lines.isEmpty)
            }
        }
    }

    private var formattedLines: [String] {
        lines.map { line in
            var parts: [String] = []
            if let ts = line.timestamp { parts.append(ts) }
            if let a = line.action { parts.append(a) }
            if let iface = line.interfaceName, !iface.isEmpty { parts.append(iface) }
            parts.append(line.text)
            return parts.joined(separator: " · ")
        }
    }
}

struct LogRow: View {
    @EnvironmentObject private var theme: ThemeManager
    let line: LogLine
    var compact: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Rectangle()
                .fill(line.health.color(theme))
                .frame(width: 2)
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 3) {
                if !compact {
                    HStack(spacing: 6) {
                        if let a = line.action {
                            StatusPill(text: a, health: line.health)
                        }
                        if let iface = line.interfaceName, !iface.isEmpty {
                            Text(iface)
                                .scaledFont(10, weight: .semibold, design: .monospaced)
                                .foregroundStyle(theme.labelFaint)
                        }
                        Spacer()
                        if let ts = line.timestamp {
                            Text(ts)
                                .scaledFont(10, design: .monospaced)
                                .foregroundStyle(theme.labelFaint)
                                .lineLimit(1)
                        }
                    }
                }
                Text(line.text)
                    .scaledFont(compact ? 11 : 12, design: .monospaced)
                    .foregroundStyle(compact ? theme.labelMuted : theme.label)
                    .lineLimit(compact ? 1 : nil)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, compact ? 2 : 8)
        .padding(.horizontal, compact ? 0 : 10)
        .background(compact ? Color.clear : theme.card)
        .clipShape(RoundedRectangle(cornerRadius: compact ? 0 : 9, style: .continuous))
    }
}

/// One filter log line, as fields.
///
/// `filterlog` writes a documented CSV, and the list shows it raw — a wall of
/// commas where which rule, which direction and which ports are countable but
/// not readable. This names them.
///
/// The raw line stays at the bottom. Parsing is lenient and the tail varies by
/// protocol, so anything not recognised is still there to read.
struct LogDetailView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var store: DashboardStore
    let line: LogLine

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let f = line.filterFields {
                    filterDetail(f)
                } else {
                    plainDetail
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
            .readableWidth()
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationTitle("Log entry")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Anything that is not the filter log: a syslog line, split into its
    /// prefix and its message.
    @ViewBuilder
    private var plainDetail: some View {
        let f = line.syslogFields

        Slab(rail: line.health) {
            VStack(alignment: .leading, spacing: 6) {
                if let process = f?.process {
                    HStack {
                        Text(process)
                            .scaledFont(14, weight: .semibold, design: .monospaced)
                            .foregroundStyle(theme.label)
                        if let pid = f?.pid {
                            Text("pid \(pid)")
                                .scaledFont(11, design: .monospaced)
                                .foregroundStyle(theme.labelFaint)
                        }
                        Spacer()
                    }
                }
                if let ts = f?.timestamp ?? line.timestamp {
                    Text(ts)
                        .scaledFont(12, design: .monospaced)
                        .foregroundStyle(theme.labelMuted)
                }
                if let host = f?.host {
                    FieldRow(key: "Host", value: host)
                }
            }
        }

        GroupHeading(text: "Message")
        Slab(rail: .info) {
            // Wrapped, not truncated. The list shows two lines of a message
            // that may run to twenty; this screen exists for the rest of it.
            Text(f?.message ?? line.text)
                .scaledFont(13, design: .monospaced)
                .foregroundStyle(theme.label)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }

        // Any address in the message, named. A DHCP line saying a lease went
        // to 172.16.1.161 is more use when it also says which device that is.
        let addresses = line.addressesMentioned
        if !addresses.isEmpty {
            GroupHeading(text: "Addresses")
            Slab(rail: .idle) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(addresses, id: \.self) { address in
                        HStack {
                            Text(address)
                                .scaledFont(12, design: .monospaced)
                                .foregroundStyle(theme.label)
                                .textSelection(.enabled)
                            Spacer()
                            if let name = store.nameForAddress(address), name != address {
                                Text(name)
                                    .scaledFont(11)
                                    .foregroundStyle(theme.labelMuted)
                            }
                        }
                    }
                }
            }
        }
    }

    /// A filter log line, as fields.
    @ViewBuilder
    private func filterDetail(_ f: LogLine.FilterFields) -> some View {
        Slab(rail: line.health, trailing: f.direction) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    StatusPill(text: (f.action ?? "?").uppercased(), health: line.health)
                    Text(f.proto?.uppercased() ?? "")
                        .scaledFont(11, weight: .semibold, design: .monospaced)
                        .foregroundStyle(theme.labelMuted)
                    Spacer()
                    if let iface = f.interfaceName {
                        Text(store.interfaceLabel(for: iface) ?? iface)
                            .scaledFont(11, design: .monospaced)
                            .foregroundStyle(theme.labelFaint)
                    }
                }
                if let ts = line.timestamp {
                    Text(ts)
                        .scaledFont(12, design: .monospaced)
                        .foregroundStyle(theme.labelMuted)
                }
            }
        }

        GroupHeading(text: "Traffic")
        Slab(rail: .info) {
            VStack(alignment: .leading, spacing: 4) {
                endpoint("From", f.source, f.sourcePort)
                endpoint("To", f.destination, f.destinationPort)
                if let length = f.length { FieldRow(key: "Length", value: "\(length) bytes") }
                if let flags = f.tcpFlags { FieldRow(key: "TCP flags", value: flags) }
                if let version = f.ipVersion { FieldRow(key: "IP version", value: "IPv\(version)") }
            }
        }

        GroupHeading(text: "Rule")
        Slab(rail: .idle) {
            VStack(alignment: .leading, spacing: 4) {
                if let reason = f.reason { FieldRow(key: "Reason", value: reason) }
                if let tracker = f.tracker, tracker != "0" {
                    // The tracker is how you find the rule that made this
                    // decision, which is usually the next thing you want after
                    // reading the line.
                    FieldRow(key: "Tracker", value: tracker)
                    if let rule = store.rules.first(where: { $0.tracker == tracker }) {
                        FieldRow(key: "Rule",
                                 value: rule.descr.isEmpty ? "(no description)" : rule.descr,
                                 mono: false)
                    }
                }
            }
        }

        GroupHeading(text: "Raw")
        Slab(rail: .idle) {
            Text(line.text)
                .scaledFont(11, design: .monospaced)
                .foregroundStyle(theme.labelFaint)
                .textSelection(.enabled)
        }
    }

    /// An address and its port, or the name the firewall knows it by.
    @ViewBuilder
    private func endpoint(_ label: String, _ address: String?, _ port: String?) -> some View {
        if let address {
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .scaledFont(9, weight: .semibold)
                    .foregroundStyle(theme.labelFaint)
                HStack(spacing: 6) {
                    Text(port.map { "\(address):\($0)" } ?? address)
                        .scaledFont(13, weight: .medium, design: .monospaced)
                        .foregroundStyle(theme.label)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                }
                if let name = store.nameForAddress(address), name != address {
                    Text(name)
                        .scaledFont(11)
                        .foregroundStyle(theme.labelMuted)
                }
            }
        }
    }
}
