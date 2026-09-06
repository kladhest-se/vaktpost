import SwiftUI

struct LogsView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var store: DashboardStore

    enum Source: String, CaseIterable, Identifiable {
        case firewall = "Firewall", system = "System"
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
        var list = source == .firewall ? store.firewallLog : store.systemLog
        if source == .firewall {
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
        source == .firewall ? .firewallLog : .systemLog
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Picker("", selection: $source) {
                    ForEach(Source.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if source == .firewall {
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
                        Notice(symbol: "doc.text.magnifyingglass",
                               title: query.isEmpty ? "No log lines" : "No matches")
                    } else {
                        ForEach(lines) { LogRow(line: $0) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .refreshable { await store.refresh() }
        }
        .background(theme.bg.ignoresSafeArea())
        .searchable(text: $query, prompt: "Search log text")
        .navigationTitle("Logs")
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
