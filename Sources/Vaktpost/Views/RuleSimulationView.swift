import SwiftUI

struct RuleSimulationView: View {
    @Environment(\.dashboardStore) private var store: DashboardStore
    @Environment(\.themeManager) private var theme: ThemeManager
    @State private var engine: RuleSimulationEngine
    @State private var proposedRule = RuleSimulationEngine.ProposedRule(
        action: .pass,
        source: "",
        destination: "any",
        destinationPort: nil,
        protocol: .any
    )
    @State private var simulationResult: RuleSimulationEngine.SimulationResult?
    @State private var isSimulating = false
    
    init() {
        _engine = State(initialValue: RuleSimulationEngine(
            arpTable: [],
            leases: [],
            staticMappings: [],
            topTalkers: [],
            firewallLog: [],
            aliases: [],
            rules: []
        ))
    }
    
    var body: some View {
        NavigationStack {
            Form {
                sectionHeader("Rule Configuration")
                
                RuleActionPicker(selection: $proposedRule.action)
                AddressField(label: "Source", text: $proposedRule.source)
                AddressField(label: "Destination", text: $proposedRule.destination)
                PortField(text: $proposedRule.destinationPort)
                ProtocolPicker(selection: $proposedRule.protocol)
                
                sectionHeader("Simulation")
                
                Button {
                    simulate()
                } label: {
                    HStack {
                        if isSimulating {
                            ProgressView()
                        } else {
                            Image(systemName: "play.fill")
                        }
                        Text("Simulate Rule")
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(theme.label)
                }
                .disabled(proposedRule.source.isEmpty || isSimulating)
                
                if let result = simulationResult {
                    sectionHeader("Results")
                    simulationResultView(result)
                }
            }
            .navigationTitle("Rule Simulator")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            updateEngine()
        }
        .task {
            updateEngine()
        }
    }
    
    private func updateEngine() {
        engine = RuleSimulationEngine(
            arpTable: store.arp,
            leases: store.leases,
            staticMappings: store.staticMappings,
            topTalkers: [],
            firewallLog: store.firewallLog,
            aliases: store.aliases,
            rules: store.rules
        )
    }
    
    private func simulate() {
        isSimulating = true
        defer { isSimulating = false }
        
        simulationResult = engine.simulate(rule: proposedRule)
    }
    
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .scaledFont(12, weight: .semibold)
            .foregroundStyle(theme.labelFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }
    
    private func simulationResultView(_ result: RuleSimulationEngine.SimulationResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Estimated Matches")
                        .scaledFont(11)
                        .foregroundStyle(Color.primary.opacity(0.6))
                    Text("\(result.estimatedMatches)")
                        .scaledFont(24, weight: .bold)
                        .foregroundStyle(riskColor(result.riskLevel))
                }
                Spacer()
                riskBadge(result.riskLevel)
            }
            
            if !result.matchedAddresses.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Matched Addresses")
                        .scaledFont(11, weight: .medium)
                        .foregroundStyle(theme.label)
                    Text(result.matchedAddresses.prefix(10).joined(separator: ", "))
                        .scaledFont(12)
                        .foregroundStyle(theme.labelMuted)
                    if result.matchedAddresses.count > 10 {
                        Text("...and \(result.matchedAddresses.count - 10) more")
                            .scaledFont(11)
                            .foregroundStyle(theme.labelFaint)
                    }
                }
                .padding(8)
                .background(theme.labelFaint.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            }
            
            if !result.matchedPorts.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Matched Ports")
                        .scaledFont(11, weight: .medium)
                        .foregroundStyle(theme.label)
                    Text(result.matchedPorts.joined(separator: ", "))
                        .scaledFont(12)
                        .foregroundStyle(theme.labelMuted)
                }
                .padding(8)
                .background(theme.labelFaint.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            }
            
            Text(result.summary)
                .scaledFont(12)
                .foregroundStyle(theme.label)
                .padding(8)
                .background(riskColor(result.riskLevel).opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }
    }
    
    private func riskColor(_ level: RuleSimulationEngine.SimulationResult.RiskLevel) -> Color {
        switch level {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .red
        }
    }
    
    private func riskBadge(_ level: RuleSimulationEngine.SimulationResult.RiskLevel) -> some View {
        Text(level.rawValue.uppercased())
            .scaledFont(10, weight: .semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(riskColor(level), in: Capsule())
    }
}

private struct RuleActionPicker: View {
    @Binding var selection: RuleSimulationEngine.ProposedRule.RuleAction
    
    var body: some View {
        LabeledContent("Action") {
            Picker("", selection: $selection) {
                Text("Pass").tag(RuleSimulationEngine.ProposedRule.RuleAction.pass)
                Text("Block").tag(RuleSimulationEngine.ProposedRule.RuleAction.block)
                Text("Reject").tag(RuleSimulationEngine.ProposedRule.RuleAction.reject)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct AddressField: View {
    let label: String
    @Binding var text: String
    
    var body: some View {
        LabeledContent(label) {
            TextField("e.g., 10.0.0.1, 192.168.1.0/24, any, LAN", text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

private struct PortField: View {
    @Binding var text: String?
    
    var body: some View {
        LabeledContent("Destination Port") {
            TextField("e.g., 443, 8080, 1-1024", text: Binding(
                get: { text ?? "" },
                set: { text = $0.isEmpty ? nil : $0 }
            ))
            .keyboardType(.numberPad)
            .textFieldStyle(.roundedBorder)
        }
    }
}

private struct ProtocolPicker: View {
    @Binding var selection: RuleSimulationEngine.ProposedRule.ProtocolType
    
    var body: some View {
        LabeledContent("Protocol") {
            Picker("", selection: $selection) {
                Text("TCP").tag(RuleSimulationEngine.ProposedRule.ProtocolType.tcp)
                Text("UDP").tag(RuleSimulationEngine.ProposedRule.ProtocolType.udp)
                Text("ICMP").tag(RuleSimulationEngine.ProposedRule.ProtocolType.icmp)
                Text("Any").tag(RuleSimulationEngine.ProposedRule.ProtocolType.any)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: .infinity)
        }
    }
}

#Preview {
    RuleSimulationView()
}
