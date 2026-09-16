import SwiftUI

struct IncidentTimelineView: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore

    enum Scope: String, CaseIterable, Identifiable {
        case incidents = "Incidents"
        case attention = "Attention"
        case all = "All"
        var id: String { rawValue }
    }

    enum SourceFilter: String, CaseIterable, Identifiable {
        case all = "All sources"
        case firewall = "Firewall"
        case system = "System"
        case authentication = "Authentication"
        case dhcp = "DHCP"
        case vpn = "VPN"
        var id: String { rawValue }

        var source: IncidentSource? {
            switch self {
            case .all: return nil
            case .firewall: return .firewall
            case .system: return .system
            case .authentication: return .authentication
            case .dhcp: return .dhcp
            case .vpn: return .vpn
            }
        }
    }

    @State private var scope: Scope = .incidents
    @State private var source: SourceFilter = .all
    @State private var query = ""
    @State private var refreshing = false
    @State private var allEvents: [IncidentEvent] = []
    @State private var filteredEvents: [IncidentEvent] = []
    @State private var groups: [IncidentGroup] = []
    @State private var incidentCount: Int = 0
    @State private var selection: String?

    private let sections: [DashboardStore.Section] = [
        .firewallLog, .systemLog, .authLog, .dhcpLog, .openvpnLog
    ]

    var body: some View {
        // Scanning a run of events and checking several log lines in
        // sequence is most of what this screen is for, and comparing them
        // is exactly what a push-and-lose-the-list phone layout gets in the
        // way of.
        MasterDetail(
            selection: $selection,
            emptyMessage: "Choose an event to see its full log line.",
            list: { listColumn },
            detail: { id in
                if let event = (filteredEvents + allEvents).first(where: { $0.id == id }) {
                    LogDetailView(line: event.line).id(store.bindingID)
                } else {
                    Notice(symbol: "questionmark.circle", title: "That event is no longer in the timeline")
                }
            }
        )
        .background(theme.bg.ignoresSafeArea())
        .navigationTitle("Incident timeline")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(store.activeProfile?.id.uuidString ?? "")|\(store.lastRefresh?.timeIntervalSince1970 ?? 0)") {
            allEvents = IncidentTimeline.build([
                (.firewall, store.firewallLog),
                (.system, store.systemLog),
                (.authentication, store.authLog),
                (.dhcp, store.dhcpLog),
                (.vpn, store.openvpnLog)
            ])
            filterEvents()
        }
        .onChange(of: scope) { filterEvents() }
        .onChange(of: source) { filterEvents() }
        .onChange(of: query) { filterEvents() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(refreshing)
                .accessibilityLabel("Refresh incident timeline")
            }
        }
        // An event selected before a firewall switch belongs to the old
        // firewall's logs. The id would not even collide by coincidence —
        // it is source plus the line's own UUID — it is just meaningless
        // once the list beside it is a different firewall's timeline.
        .onChange(of: store.bindingID) { _, _ in selection = nil }
    }

    private var listColumn: some View {
        ScrollView {
            PageHeader(
                title: "Incident timeline",
                subtitle: allEvents.isEmpty ? nil : "\(incidentCount) incidents · \(allEvents.count) events fetched"
            )
            VStack(alignment: .leading, spacing: 12) {
                FreshnessView(sections: sections, showNames: true)

                InlineSearchField(text: $query, prompt: "Search timeline")

                Picker("Severity", selection: $scope) {
                    ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                HStack {
                    Label("Source", systemImage: "line.3.horizontal.decrease.circle")
                        .scaledFont(12, weight: .medium)
                        .foregroundStyle(theme.labelMuted)
                    Spacer()
                    Picker("Source", selection: $source) {
                        ForEach(SourceFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                if sections.contains(where: { store.errors[$0] != nil }) {
                    Notice(
                        symbol: "exclamationmark.triangle",
                        title: "Some sources could not be refreshed",
                        detail: "Available events are still shown. Data freshness identifies the affected log.",
                        health: .warn
                    )
                }

                if filteredEvents.isEmpty {
                    Notice(
                        symbol: scope == .all ? "clock" : "checkmark.seal",
                        title: emptyTitle,
                        detail: self.allEvents.isEmpty
                            ? "Refresh to retrieve the firewall, system, authentication, DHCP and VPN logs."
                            : "Change the source, severity or search filter to widen the timeline.",
                        health: self.allEvents.isEmpty ? .idle : .ok
                    )
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(groups) { group in
                            IncidentGroupRow(group: group) { eventID in
                                selection = eventID
                            }
                        }
                    }
                }

                Slab(rail: .idle, title: "About this timeline") {
                    Text("Incidents are identified on this device from blocked or rejected firewall entries "
                        + "and explicit failure or warning terms in the fetched logs. "
                        + "The original log entry remains the source of truth.")
                        .scaledFont(12)
                        .foregroundStyle(theme.labelMuted)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .refreshable { await refresh() }
    }

    private var emptyTitle: String {
        if !query.isEmpty { return "No matching events" }
        return scope == .all ? "No events fetched" : "No incidents found"
    }

    private func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        await store.refreshIncidentTimeline()
    }

    private func filterEvents() {
        var count = 0
        var result: [IncidentEvent] = []
        for event in allEvents {
            let severityMatches: Bool
            switch scope {
            case .incidents: severityMatches = event.severity != .information
            case .attention: severityMatches = event.severity == .attention
            case .all: severityMatches = true
            }
            let sourceMatches = source.source == nil || source.source == event.source
            let queryMatches = query.isEmpty
                || event.line.text.localizedCaseInsensitiveContains(query)
                || event.source.rawValue.localizedCaseInsensitiveContains(query)
            if severityMatches && sourceMatches && queryMatches {
                result.append(event)
                if event.severity != .information {
                    count += 1
                }
            }
        }
        filteredEvents = result
        groups = IncidentGrouping.group(result)
        incidentCount = count
    }
}

private struct IncidentGroupRow: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore
    let group: IncidentGroup
    let onSelect: (String) -> Void
    @State private var isExpanded = false
    @State private var showQuickBlock = false

    private var health: Health {
        switch group.severity {
        case .attention: return .bad
        case .warning: return .warn
        case .information: return .info
        }
    }

    private var sourceAddress: String? {
        guard let key = group.groupKey, case .sourceAddress(let address) = key else { return nil }
        return address
    }

    var body: some View {
        // A group nothing else joined is shown exactly as a single event
        // always has been — there's no pattern here to summarize, so no
        // summary chrome to show for it.
        if group.count == 1, let event = group.events.first {
            Button {
                onSelect(event.id)
            } label: {
                IncidentTimelineRow(event: event)
            }
            .buttonStyle(.plain)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    isExpanded.toggle()
                } label: {
                    summaryRow
                }
                .buttonStyle(.plain)

                // Hidden, not disabled, on a monitor-only profile — matching
                // how Quick Block's own entry point in More already behaves,
                // rather than showing a button here that would just fail.
                if let address = sourceAddress, store.canAdminister {
                    Button {
                        showQuickBlock = true
                    } label: {
                        Label("Block this source", systemImage: "shield.slash")
                            .scaledFont(12, weight: .semibold)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.bad)
                    .padding(.leading, 21)
                    .padding(.bottom, 10)
                    .sheet(isPresented: $showQuickBlock) {
                        NavigationStack {
                            QuickBlockView(
                                prefillAddress: address,
                                prefillDescription: "Repeated blocks from incident timeline (\(group.count) attempts)"
                            )
                        }
                    }
                }

                if isExpanded {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(group.events) { event in
                            Button {
                                onSelect(event.id)
                            } label: {
                                IncidentTimelineRow(event: event)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.leading, 21)
                }
            }
        }
    }

    private var summaryRow: some View {
        HStack(alignment: .top, spacing: 11) {
            VStack(spacing: 0) {
                Circle()
                    .fill(health.color(theme))
                    .frame(width: 10, height: 10)
                    .padding(.top, 7)
                Rectangle()
                    .fill(theme.hairline)
                    .frame(width: 1)
                    .frame(minHeight: 58)
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    if let address = sourceAddress {
                        Label(address, systemImage: IncidentSource.firewall.symbol)
                            .scaledFont(11, weight: .semibold)
                            .foregroundStyle(theme.labelMuted)
                    }
                    StatusPill(text: group.severity.rawValue, health: health)
                    if group.isOngoing {
                        Circle()
                            .fill(theme.bad)
                            .frame(width: 6, height: 6)
                        Text("Ongoing")
                            .scaledFont(10, weight: .semibold)
                            .foregroundStyle(theme.bad)
                    }
                    Spacer()
                }
                Text("\(group.count) attempts")
                    .scaledFont(13, weight: .semibold)
                    .foregroundStyle(theme.label)
                HStack {
                    if let first = group.firstSeen, let last = group.lastSeen {
                        if first == last {
                            Text(last, style: .relative)
                        } else {
                            Text(first, format: .dateTime.hour().minute())
                            Text("–")
                            Text(last, format: .dateTime.hour().minute())
                        }
                    } else {
                        Text("Time unavailable")
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                }
                .scaledFont(10, design: .monospaced)
                .foregroundStyle(theme.labelFaint)
            }
            .padding(.bottom, 12)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct IncidentTimelineRow: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    let event: IncidentEvent

    private var health: Health {
        switch event.severity {
        case .attention: return .bad
        case .warning: return .warn
        case .information: return .info
        }
    }

    private var message: String {
        event.line.syslogFields?.message ?? event.line.text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            VStack(spacing: 0) {
                Circle()
                    .fill(health.color(theme))
                    .frame(width: 10, height: 10)
                    .padding(.top, 7)
                Rectangle()
                    .fill(theme.hairline)
                    .frame(width: 1)
                    .frame(minHeight: 58)
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Label(event.source.rawValue, systemImage: event.source.symbol)
                        .scaledFont(11, weight: .semibold)
                        .foregroundStyle(theme.labelMuted)
                    StatusPill(text: event.severity.rawValue, health: health)
                    Spacer()
                }
                Text(message)
                    .scaledFont(12, design: .monospaced)
                    .foregroundStyle(theme.label)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                HStack {
                    if let date = event.date {
                        Text(date, format: .dateTime.month(.abbreviated).day().hour().minute().second())
                        Text("·")
                        Text(date, style: .relative)
                    } else {
                        Text(event.timestampText ?? "Time unavailable")
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .scaledFont(10, design: .monospaced)
                .foregroundStyle(theme.labelFaint)
            }
            .padding(.bottom, 12)
        }
        .accessibilityElement(children: .combine)
    }
}
