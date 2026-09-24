import SwiftUI

/// One box, and everything the firewall knows about what goes in it.
///
/// The data was always there and always scattered. Six screens each had their
/// own search field, so "what is 172.16.1.32 and what touches it" meant
/// visiting five of them and holding the answers in your head. This asks
/// nothing new of the firewall — it searches the tables the refresh has
/// already fetched.
struct InvestigateView: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore

    /// Prefilled when arriving from something that already knows the address.
    var initialQuery: String = ""

    @State private var query = ""
    @State private var hasApplied = false
    @State private var isLoading = false

    private var subject: Investigation.Subject? { Investigation.subject(query) }

    private var findings: [Investigation.Finding] {
        guard let subject else { return [] }
        return Investigation.findings(
            for: subject,
            in: Investigation.Sources(
                clients: store.overviewLayout.clients,
                arp: store.arp,
                leases: store.leases,
                staticMappings: store.staticMappings,
                hostOverrides: store.hostOverrides,
                aliases: store.aliases,
                rules: store.rules,
                portForwards: store.portForwards,
                openvpnServers: store.openvpnServers,
                wireguardPeers: store.wireguardPeers,
                dnsblClients: store.dnsblStats?.clients ?? []
            )
        )
    }

    /// Grouped in reading order: what the thing is, then what touches it.
    private var groups: [(kind: Investigation.Finding.Kind, items: [Investigation.Finding])] {
        let order: [Investigation.Finding.Kind] = [
            .client, .arp, .lease, .staticMapping, .hostOverride,
            .vpn, .alias, .rule, .portForward, .dnsbl
        ]
        return order.compactMap { kind in
            let items = findings.filter { $0.kind == kind }
            return items.isEmpty ? nil : (kind: kind, items: items)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                InlineSearchField(text: $query, prompt: "Address, MAC or name")
                content
                coverage
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationTitle("Investigate")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !hasApplied else { return }
            hasApplied = true
            if !initialQuery.isEmpty { query = initialQuery }
        }
        // Fetch what this screen searches rather than telling somebody to go
        // and open other screens first. Each loader guards against repeating
        // itself, so this costs nothing after the first open.
        .task {
            isLoading = true
            await store.loadInvestigationData()
            isLoading = false
        }
        .refreshable {
            await store.refresh()
            await store.loadInvestigationData()
        }
    }

    @ViewBuilder
    private var content: some View {
        if query.isEmpty {
            Notice(symbol: "magnifyingglass",
                   title: "Search everything at once",
                   detail: "An address, a MAC or part of a name. This looks through the client list, ARP, leases, static mappings, "
                       + "DNS overrides, aliases, firewall rules, port forwards, VPN connections and DNSBL.")
        } else if subject == nil {
            Notice(symbol: "text.magnifyingglass",
                   title: "Keep typing",
                   detail: "Two characters or more.")
        } else if findings.isEmpty {
            Notice(symbol: "questionmark.circle",
                   title: "Nothing references that",
                   detail: "Nothing in the client, ARP, lease, mapping, override, alias, rule, NAT, VPN or DNSBL tables mentions \(subject?.display ?? query).",
                   health: .idle)
        } else {
            ForEach(groups, id: \.kind) { group in
                GroupHeading(text: group.kind.title)
                ForEach(group.items) { finding in
                    // A result that has a screen opens it; one that does not
                    // stays exactly as it was, rather than looking tappable
                    // and doing nothing.
                    if canOpen(finding) {
                        NavigationLink {
                            destination(for: finding)
                        } label: {
                            row(finding, isLink: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens this \(finding.kind.title.lowercased())")
                    } else {
                        row(finding)
                    }
                }
            }
        }
    }

    /// Whether the thing this result names is still in the tables.
    ///
    /// A rule deleted since the search was typed stops being a link rather
    /// than opening an empty screen.
    private func canOpen(_ finding: Investigation.Finding) -> Bool {
        switch finding.reference {
        case let .rule(id): return store.rules.contains { $0.id == id }
        case let .portForward(id): return store.portForwards.contains { $0.id == id }
        case let .alias(name): return store.aliases.contains { $0.name == name }
        case let .client(id): return store.overviewLayout.clients.contains { $0.id == id }
        case nil: return false
        }
    }

    /// The screen behind a result, when the thing it names is still here.
    ///
    /// Resolved against the store rather than carried in the finding, so a
    /// rule deleted since the search stops being a link instead of opening
    /// a copy of something that no longer exists.
    @ViewBuilder
    private func destination(for finding: Investigation.Finding) -> some View {
        switch finding.reference {
        case let .rule(id):
            if let rule = store.rules.first(where: { $0.id == id }) {
                RuleDetailView(rule: rule, selection: .constant(nil))
            }
        case let .portForward(id):
            if let forward = store.portForwards.first(where: { $0.id == id }) {
                PortForwardDetailView(forward: forward, selection: .constant(nil))
            }
        case let .alias(name):
            if store.aliases.contains(where: { $0.name == name }) {
                AliasDetailView(aliasName: name)
            }
        case let .client(id):
            if let client = store.overviewLayout.clients.first(where: { $0.id == id }) {
                ClientDetailView(client: client)
            }
        case nil:
            EmptyView()
        }
    }

    private func row(_ finding: Investigation.Finding, isLink: Bool = false) -> some View {
        Slab(rail: .info) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: finding.kind.symbol)
                    .scaledFont(13)
                    .foregroundStyle(theme.accentColor)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(finding.title)
                        .scaledFont(13, weight: .semibold)
                        .foregroundStyle(theme.label)
                    if let detail = finding.detail, !detail.isEmpty {
                        Text(detail)
                            .scaledFont(11, design: .monospaced)
                            .foregroundStyle(theme.labelMuted)
                    }
                    if let via = finding.via {
                        // Why this matched. A result somebody cannot account
                        // for is one they have to go and check, which is the
                        // work this screen exists to save.
                        Text(via)
                            .scaledFont(10)
                            .foregroundStyle(theme.labelFaint)
                    }
                }
                Spacer(minLength: 0)
                if isLink {
                    Image(systemName: "chevron.right")
                        .scaledFont(10, weight: .semibold)
                        .foregroundStyle(theme.labelFaint)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    /// What is still arriving, and what the firewall simply does not have.
    ///
    /// This used to say "open those screens once and they will be included",
    /// which put the work back on the reader for something the screen could do
    /// itself. Now it either reports that the tables are being fetched, or —
    /// once they are — which of them this firewall has nothing for, because an
    /// empty alias list is a real answer rather than a missing one.
    private var coverage: some View {
        let absent = [
            store.rules.isEmpty ? "firewall rules" : nil,
            store.aliases.isEmpty ? "aliases" : nil,
            store.portForwards.isEmpty ? "port forwards" : nil,
        ].compactMap { $0 }

        return VStack(alignment: .leading, spacing: 8) {
            if isLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Fetching firewall rules, aliases and port forwards…")
                }
            } else if absent.isEmpty {
                Text("Searching every table the app holds.")
            } else {
                // Fetched and empty, which is an answer. "Not searched" here
                // would be untrue, and would send somebody looking for a
                // screen to open that would tell them the same thing.
                Text("This firewall has no \(absent.joined(separator: ", ")), so nothing can reference an address through them.")
            }

            if store.dnsblStats == nil && store.pfBlockerInstalled {
                Text("DNSBL counts are not included — pfBlockerNG is installed but its DNSBL component is off.")
                    .foregroundStyle(theme.labelFaint)
            }
        }
        .scaledFont(12)
        .foregroundStyle(theme.labelMuted)
        .padding(.horizontal, 2)
    }
}
