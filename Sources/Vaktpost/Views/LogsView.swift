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
    @State private var shareItems: [String] = []
    @State private var showingShareSheet = false

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
        VStack(spacing: 0) {
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

            ScrollView {
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
                        ForEach(lines) { LogRow(line: $0) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .refreshable { await store.refreshManually() }
        }
        .background(theme.bg.ignoresSafeArea())
        .searchable(text: $query, prompt: "Search log text")
        .task { await store.beginSecondaryLogs() }
        .navigationTitle("Logs")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    shareItems = formattedLines
                    showingShareSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(lines.isEmpty)
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheetAdapter(items: shareItems)
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

struct ShareSheetAdapter: UIViewControllerRepresentable {
    var items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
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
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(theme.labelFaint)
                        }
                        Spacer()
                        if let ts = line.timestamp {
                            Text(ts)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(theme.labelFaint)
                                .lineLimit(1)
                        }
                    }
                }
                Text(line.text)
                    .font(.system(size: compact ? 11 : 12, design: .monospaced))
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
