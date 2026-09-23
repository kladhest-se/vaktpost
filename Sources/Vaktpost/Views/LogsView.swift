import SwiftUI

struct LogsView: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore
    @Environment(\.scenePhase) private var scenePhase

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
    @State private var interfaceFilter: String?
    @State private var protocolFilter: String?
    @State private var sourceFilter = ""
    @State private var destinationFilter = ""
    @State private var portFilter = ""
    @State private var filteredLines: [LogLine] = []
    @State private var isPaused = false
    @State private var followsNewest = true
    @State private var unseenCount = 0
    @State private var knownFirewallIDs: Set<UUID> = []

    private struct PollID: Hashable {
        var profileID: UUID?
        var active: Bool
        var paused: Bool
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

    private func filterLines() {
        var list: [LogLine]
        switch source {
        case .firewall: list = store.firewallLog
        case .system:   list = store.systemLog
        case .auth:     list = store.authLog
        case .dhcp:     list = store.dhcpLog
        case .openvpn:  list = store.openvpnLog
        }
        guard showsActionFilter else {
            filteredLines = query.isEmpty ? list
                : list.filter { $0.text.localizedCaseInsensitiveContains(query) }
            return
        }
        let actionValue: String?
        switch action {
        case .all: actionValue = nil
        case .blocked: actionValue = "block"
        case .passed: actionValue = "pass"
        }
        let filter = FirewallLogFilter(query: query, action: actionValue,
                                       interfaceName: interfaceFilter, proto: protocolFilter,
                                       source: sourceFilter, destination: destinationFilter,
                                       port: portFilter)
        filteredLines = list.filter(filter.matches)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                PageHeader(title: "Logs", subtitle: nil)
                VStack(spacing: 8) {
                    InlineSearchField(text: $query, prompt: "Search log text")
                        .padding(.horizontal, 16)

                    Picker("", selection: $source) {
                        ForEach(Source.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if showsActionFilter {
                        liveControls(proxy)

                        Picker("", selection: $action) {
                            ForEach(ActionFilter.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                filterMenu("Interface", value: interfaceFilter,
                                           options: firewallInterfaces) { interfaceFilter = $0 }
                                filterMenu("Protocol", value: protocolFilter,
                                           options: firewallProtocols) { protocolFilter = $0 }
                                if !sourceFilter.isEmpty || !destinationFilter.isEmpty || !portFilter.isEmpty {
                                    Button("Clear endpoints") {
                                        sourceFilter = ""; destinationFilter = ""; portFilter = ""
                                    }
                                    .scaledFont(11, weight: .medium)
                                }
                            }
                        }

                        HStack(spacing: 8) {
                            compactFilterField("Source", text: $sourceFilter)
                            compactFilterField("Destination", text: $destinationFilter)
                            compactFilterField("Port", text: $portFilter)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                FreshnessView(sections: [errorKey]).padding(.horizontal, 16)
                LazyVStack(alignment: .leading, spacing: 8) {
                    if let err = store.errors[errorKey] {
                        Notice(symbol: "exclamationmark.triangle",
                               title: "Log unavailable", detail: err, health: .warn)
                    } else if filteredLines.isEmpty {
                        Notice(
                            symbol: "doc.text.magnifyingglass",
                            title: query.isEmpty ? "No log lines" : "No matches",
                            detail: query.isEmpty && (source == .dhcp || source == .openvpn)
                                ? "This log is empty when the service isn't running."
                                : nil
                        )
                    } else {
                        ForEach(filteredLines) { line in
                            NavigationLink {
                                LogDetailView(line: line)
                            } label: {
                                LogRow(line: line)
                            }
                            .buttonStyle(.plain)
                            .id(line.id)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(theme.bg.ignoresSafeArea())
            .refreshable {
                if source == .firewall { await store.refreshFirewallLog() }
                else { await store.fetch(errorKey) }
            }
            .task(id: PollID(profileID: store.activeProfile?.id,
                             active: scenePhase == .active, paused: isPaused)) {
                guard scenePhase == .active else { return }
                await store.beginSecondaryLogs()
                filterLines()
                if !isPaused { await store.monitorFirewallLog() }
            }
            .onAppear {
                knownFirewallIDs = Set(store.firewallLog.map(\.id))
                filterLines()
            }
            .onChange(of: store.firewallLog.map(\.id)) {
                let current = Set(store.firewallLog.map(\.id))
                let additions = knownFirewallIDs.isEmpty ? 0 : current.subtracting(knownFirewallIDs).count
                knownFirewallIDs = current
                filterLines()
                if followsNewest, source == .firewall {
                    unseenCount = 0
                    scrollToNewest(proxy)
                } else {
                    unseenCount += additions
                }
            }
            .onChange(of: source) { unseenCount = 0; filterLines() }
            .onChange(of: followsNewest) {
                guard followsNewest else { return }
                unseenCount = 0
                scrollToNewest(proxy)
            }
            .onChange(of: action) { filterLines() }
            .onChange(of: query) { filterLines() }
            .onChange(of: interfaceFilter) { filterLines() }
            .onChange(of: protocolFilter) { filterLines() }
            .onChange(of: sourceFilter) { filterLines() }
            .onChange(of: destinationFilter) { filterLines() }
            .onChange(of: portFilter) { filterLines() }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        ShareLink(
                            item: LogExport.text(for: filteredLines, redacted: false),
                            preview: SharePreview("\(source.rawValue) log — full")
                        ) { Label("Share full log", systemImage: "doc.text") }
                        ShareLink(
                            item: "Addresses and ports redacted\n\n"
                                + LogExport.text(for: filteredLines, redacted: true),
                            preview: SharePreview("\(source.rawValue) log — redacted")
                        ) { Label("Share redacted log", systemImage: "eye.slash") }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share log")
                    .disabled(filteredLines.isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private func liveControls(_ proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 10) {
            Button {
                isPaused.toggle()
            } label: {
                Label(isPaused ? "Resume" : "Pause", systemImage: isPaused ? "play.fill" : "pause.fill")
            }
            .accessibilityHint(isPaused ? "Resume automatic filter log updates" : "Pause automatic filter log updates")

            Button {
                followsNewest.toggle()
                if followsNewest { scrollToNewest(proxy) }
            } label: {
                Label("Follow", systemImage: followsNewest ? "arrow.up.circle.fill" : "arrow.up.circle")
            }

            if unseenCount > 0 {
                Button("\(unseenCount) new") {
                    followsNewest = true
                    unseenCount = 0
                    scrollToNewest(proxy)
                }
                .foregroundStyle(theme.accentColor)
            }
            Spacer()
        }
        .scaledFont(11, weight: .medium)

        TimelineView(.periodic(from: .now, by: 5)) { context in
            HStack(spacing: 4) {
                if isPaused {
                    Text("Live updates paused")
                } else if let fetched = store.freshness[.firewallLog]?.lastSuccess {
                    Text("Last fetched")
                    Text(fetched, style: .relative)
                    Text("ago")
                } else {
                    Text("Waiting for first filter log update")
                }
                if !isPaused, let retryAt = store.firewallLogRetryAt,
                   retryAt > context.date, store.firewallLogFailureCount > 0 {
                    Text("· retry")
                    Text(retryAt, style: .relative)
                }
                Spacer()
            }
            .scaledFont(10)
            .foregroundStyle(theme.labelFaint)
        }
    }

    private func scrollToNewest(_ proxy: ScrollViewProxy) {
        guard let first = filteredLines.first?.id else { return }
        withAnimation(Motion.animation(.easeOut(duration: 0.2))) { proxy.scrollTo(first, anchor: .top) }
    }

    private var firewallInterfaces: [String] {
        Array(Set(store.firewallLog.compactMap { $0.filterFields?.interfaceName })).sorted()
    }

    private var firewallProtocols: [String] {
        Array(Set(store.firewallLog.compactMap { $0.filterFields?.proto?.lowercased() })).sorted()
    }

    private func filterMenu(_ title: String, value: String?, options: [String],
                            set: @escaping (String?) -> Void) -> some View {
        Menu {
            Button("All") { set(nil) }
            ForEach(options, id: \.self) { option in Button(option) { set(option) } }
        } label: {
            Text(value.map { "\(title): \($0)" } ?? "\(title): All")
                .scaledFont(11, weight: .medium)
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(theme.cardRaised, in: Capsule())
        }
    }

    private func compactFilterField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .scaledFont(11, design: .monospaced)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(8)
            .background(theme.cardRaised, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct LogRow: View {
    @Environment(\.themeManager) private var theme: ThemeManager
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
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore
    let line: LogLine
    @State private var ruleDraft: RuleEditForm?
    @State private var prefillError: String?

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
        .sheet(item: $ruleDraft) { form in
            RuleEditSheet(
                form: form,
                interfaces: store.interfaces,
                aliases: store.aliases,
                ruleset: store.rules,
                subject: form.apply(to: FirewallRule(JSONDict([
                    "tracker": .string(""),
                    "interface": .string(form.interface)
                ])))
            ) { saved in
                let dict = saved.toDict(tracker: "", interface: saved.interface)
                _ = try await store.writeCoordinator.execute(
                    .saveRule(rule: dict,
                              displayName: saved.descr.isEmpty
                                  ? "new rule on \(saved.interface)" : saved.descr)
                )
                await store.refreshManually()
            }
        }
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

        Button {
            stageRule(from: f)
        } label: {
            HStack {
                Image(systemName: "plus.shield")
                Text("Create staged rule from this")
                Spacer()
                Image(systemName: "chevron.right")
            }
            .scaledFont(13, weight: .semibold)
            .foregroundStyle(theme.accentColor)
            .padding(12)
            .background(theme.card, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)

        if let prefillError {
            Notice(symbol: "exclamationmark.triangle",
                   title: "Cannot prefill this event safely",
                   detail: prefillError, health: .warn)
        }
    }

    private func stageRule(from fields: LogLine.FilterFields) {
        let raw = fields.interfaceName ?? ""
        let interface = store.interfaces.first {
            $0.device.caseInsensitiveCompare(raw) == .orderedSame
                || $0.internalName?.caseInsensitiveCompare(raw) == .orderedSame
                || $0.name.caseInsensitiveCompare(raw) == .orderedSame
        }?.internalName
        do {
            ruleDraft = try RuleEditForm.prefilled(from: line, interface: interface)
            prefillError = nil
        } catch {
            ruleDraft = nil
            prefillError = error.localizedDescription
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
