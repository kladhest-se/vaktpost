import SwiftUI

/// What this rule would have done to traffic the firewall logged.
///
/// Reachable from a rule, prefilled with that rule — the previous simulation
/// view could only be opened from its own `#Preview`, so the whole feature
/// existed and nobody could see it.
///
/// It answers the question `RulePlacement` deliberately refuses: placement
/// compares rules to each other by literal value, this one compares a rule to
/// observed packets. Together they cover "what else claims this traffic" and
/// "is there any such traffic".
struct RuleSimulationSheet: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore
    @Environment(\.dismiss) private var dismiss

    let rule: FirewallRule

    @State private var result: RuleSimulation.Result?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if isLoading {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Reading the filter log…")
                                .scaledFont(12)
                                .foregroundStyle(theme.labelFaint)
                        }
                        .frame(maxWidth: .infinity, minHeight: 120)
                    } else if let result {
                        headline(result)
                        consequence(result)
                        sources(result)
                        caveats(result)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(theme.bg.ignoresSafeArea())
            .navigationTitle("Against the log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                // Fetched here rather than assumed: the filter log is loaded
                // when the Logs tab is opened, and somebody arriving from a
                // rule may never have been there. An empty log would otherwise
                // read as "no matching traffic", which is the one wrong answer
                // this screen must not give.
                await store.fetch(.firewallLog)
                result = RuleSimulation.run(rule, against: store.firewallLog)
                isLoading = false
            }
        }
    }

    private func headline(_ result: RuleSimulation.Result) -> some View {
        Slab(rail: result.matchesNothing ? .idle : .info, title: "Matched") {
            HStack(alignment: .firstTextBaseline) {
                Text("\(result.matched)")
                    .scaledFont(28, weight: .bold, design: .rounded)
                    .foregroundStyle(theme.label)
                // "log lines", not "flows" or "connections". One TCP session
                // is many lines or none depending on what is logged, and
                // calling them connections would be a number about something
                // this cannot see.
                Text(result.matched == 1 ? "logged packet" : "logged packets")
                    .scaledFont(12)
                    .foregroundStyle(theme.labelMuted)
                Spacer()
                Text("of \(result.considered)")
                    .scaledFont(12, design: .monospaced)
                    .foregroundStyle(theme.labelFaint)
            }
        }
    }

    /// The part worth reading: what happens to that traffic today.
    @ViewBuilder
    private func consequence(_ result: RuleSimulation.Result) -> some View {
        if !result.matchesNothing {
            let isBlocking = rule.type != "pass"
            Slab(rail: relevantCount(result, blocking: isBlocking) > 0 ? .warn : .info,
                 title: "Effect") {
                VStack(alignment: .leading, spacing: 6) {
                    if isBlocking && result.wouldNewlyBlock > 0 {
                        Text("\(result.wouldNewlyBlock) of those were passed at the time, so this rule would stop traffic that is getting through today.")
                            .scaledFont(12)
                            .foregroundStyle(theme.label)
                    } else if !isBlocking && result.wouldNewlyPass > 0 {
                        Text("\(result.wouldNewlyPass) of those were blocked at the time, so this rule would let through traffic that is being refused today.")
                            .scaledFont(12)
                            .foregroundStyle(theme.label)
                    } else {
                        Text("The matching traffic is already being handled the same way, so this rule changes what is logged rather than what happens.")
                            .scaledFont(12)
                            .foregroundStyle(theme.labelMuted)
                    }

                    FieldRow(key: "Passed at the time", value: "\(result.passedAtTheTime)", mono: false)
                    FieldRow(key: "Blocked at the time", value: "\(result.blockedAtTheTime)", mono: false)
                }
            }
        }
    }

    private func relevantCount(_ result: RuleSimulation.Result, blocking: Bool) -> Int {
        blocking ? result.wouldNewlyBlock : result.wouldNewlyPass
    }

    @ViewBuilder
    private func sources(_ result: RuleSimulation.Result) -> some View {
        if !result.sources.isEmpty {
            GroupHeading(text: "Busiest sources")
            Slab(rail: .info) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(result.sources, id: \.self) { address in
                        HStack(spacing: 8) {
                            Text(store.nameForAddress(address) ?? address)
                                .scaledFont(12, weight: .semibold)
                                .foregroundStyle(theme.label)
                            if store.nameForAddress(address) != nil {
                                Text(address)
                                    .scaledFont(10, design: .monospaced)
                                    .foregroundStyle(theme.labelFaint)
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    /// Where this is blind, said next to the number rather than left implied.
    private func caveats(_ result: RuleSimulation.Result) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // The big one. pfSense logs the rules that have logging switched
            // on, plus the default deny — so the sample is not a sample of
            // traffic, it is a sample of what somebody chose to record.
            Text("This counts packets in the filter log. pfSense only logs rules with logging enabled, plus the default deny, so a zero here means nothing matching was logged — not that no such traffic exists.")

            Text("Matching is literal: \"any\" matches everything, otherwise values must be equal. A rule naming an alias or a network will match nothing here even when it would match traffic on the firewall.")

            if result.unparsed > 0 {
                Text("\(result.unparsed) log lines had no readable filter fields and were not judged.")
                    .foregroundStyle(theme.labelFaint)
            }
        }
        .scaledFont(12)
        .foregroundStyle(theme.labelMuted)
        .padding(.horizontal, 2)
    }
}
