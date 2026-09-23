import SwiftUI

/// Ping, traceroute, DNS lookup and a speed test, in one screen.
///
/// Ping and traceroute run only on this device — see `ICMPProbe` for why:
/// pfSense's PHP has no ICMP capability, and reaching a shell on the
/// firewall to get one would be exactly the kind of exception this app's
/// write boundary exists to refuse. DNS lookup is the one of the three that
/// can run on the firewall too, since `dns_get_record()` needs no shell —
/// so it alone gets a choice of resolver, and the choice is worth keeping:
/// the firewall's resolver and this device's can genuinely disagree, most
/// often when a VPN, split-DNS, or a different Wi-Fi network is involved,
/// and that disagreement is usually the whole answer to why something
/// resolves one place and not another.
struct NetworkToolsView: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore

    enum Tool: String, CaseIterable, Identifiable {
        case ping = "Ping", traceroute = "Traceroute", dns = "DNS", speed = "Speed"
        var id: String { rawValue }
    }

    enum DNSSource: String, CaseIterable, Identifiable {
        case device = "This device", firewall = "Firewall"
        var id: String { rawValue }
    }

    private static let recordTypes = ["A", "AAAA", "CNAME", "MX", "NS", "TXT", "SOA"]

    @State private var tool: Tool = .ping
    @State private var host = ""

    @State private var pingResult: PingResult?
    @State private var isPinging = false

    @State private var tracerouteResult: TracerouteResult?
    @State private var isTracing = false

    @State private var dnsSource: DNSSource = .device
    @State private var dnsRecordType = "A"
    @State private var dnsResult: DNSLookupResult?
    @State private var isLookingUp = false

    var body: some View {
        ScrollView {
            PageHeader(title: "Network Tools", subtitle: "Ping, traceroute, DNS lookup and speed test")
            VStack(alignment: .leading, spacing: 14) {
                Picker("", selection: $tool) {
                    ForEach(Tool.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                // The speed test has no target to type: it measures the
                // firewall's own WAN against a fixed endpoint.
                if tool != .speed {
                    LabelledField(title: "Host", text: $host,
                                  placeholder: "IP address or hostname",
                                  keyboard: .URL, autocap: false)
                }

                switch tool {
                case .ping: pingSection
                case .traceroute: tracerouteSection
                case .dns: dnsSection
                case .speed: SpeedtestSection()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
            .readableWidth()
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationTitle("Network Tools")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var trimmedHost: String { host.trimmingCharacters(in: .whitespaces) }

    // MARK: - Ping

    private var pingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Four ICMP echo requests, sent from this device.")
                .scaledFont(12)
                .foregroundStyle(theme.labelFaint)

            runButton(title: "Ping", systemImage: "dot.radiowaves.left.and.right", isRunning: isPinging) {
                isPinging = true
                pingResult = nil
                let result = await ICMPProbe.ping(host: trimmedHost)
                pingResult = result
                isPinging = false
            }

            if let result = pingResult {
                Slab(rail: result.success ? .ok : .bad, title: "Result") {
                    VStack(alignment: .leading, spacing: 6) {
                        FieldRow(key: "Host", value: result.host)
                        if let avg = result.avgMs {
                            FieldRow(key: "Average", value: String(format: "%.1f ms", avg))
                        }
                        Text(result.message)
                            .scaledFont(13)
                            .foregroundStyle(theme.label)
                    }
                }
            }
        }
    }

    // MARK: - Traceroute

    private var tracerouteSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(
                "Up to 30 hops, sent from this device. Some networks — cellular especially — filter the probes "
                    + "this needs, which shows up as a run of timeouts rather than a wrong answer."
            )
                .scaledFont(12)
                .foregroundStyle(theme.labelFaint)

            runButton(title: "Trace route", systemImage: "point.3.connected.trianglepath.dotted", isRunning: isTracing) {
                isTracing = true
                tracerouteResult = nil
                let result = await ICMPProbe.traceroute(host: trimmedHost)
                tracerouteResult = result
                isTracing = false
            }

            if let result = tracerouteResult {
                if result.hops.isEmpty {
                    Notice(symbol: "questionmark.circle", title: "No hops recorded",
                           detail: "The host may not have resolved, or nothing along the path responded.")
                } else {
                    Slab(rail: .info, title: "Hops") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(result.hops.enumerated()), id: \.offset) { _, hop in
                                HStack(alignment: .firstTextBaseline) {
                                    Text("\(hop.hop)")
                                        .scaledFont(12, weight: .semibold, design: .monospaced)
                                        .foregroundStyle(theme.labelFaint)
                                        .frame(width: 24, alignment: .trailing)
                                    Text(hop.detail)
                                        .scaledFont(13, design: .monospaced)
                                        .foregroundStyle(hop.detail == "*" ? theme.labelFaint : theme.label)
                                    Spacer(minLength: 8)
                                    Text(hop.latencies.isEmpty ? "*"
                                        : hop.latencies.map { String(format: "%.0f ms", $0) }.joined(separator: "  "))
                                        .scaledFont(11, design: .monospaced)
                                        .foregroundStyle(theme.labelMuted)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - DNS lookup

    private var dnsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                fieldLabel("Resolver")
                Picker("", selection: $dnsSource) {
                    ForEach(DNSSource.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 4) {
                fieldLabel("Record type")
                Picker("", selection: $dnsRecordType) {
                    ForEach(Self.recordTypes, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            runButton(title: "Look up", systemImage: "magnifyingglass", isRunning: isLookingUp) {
                isLookingUp = true
                dnsResult = nil
                let result: DNSLookupResult
                switch dnsSource {
                case .device:
                    result = await DeviceDNSLookup.lookup(host: trimmedHost, recordType: dnsRecordType)
                case .firewall:
                    result = (try? await store.client.dnsLookup(host: trimmedHost, recordType: dnsRecordType))
                        ?? DNSLookupResult(JSONDict(["host": .string(trimmedHost),
                                                     "error": .string("The firewall did not answer.")]))
                }
                dnsResult = result
                isLookingUp = false
            }

            if let result = dnsResult {
                if result.hasError || result.records.isEmpty {
                    Notice(symbol: "questionmark.circle", title: "No records found",
                           detail: "Check the hostname and record type.")
                } else {
                    Slab(rail: .info, title: "\(dnsRecordType) records",
                         trailing: result.queryTime.map { "\($0) ms" }) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(result.records.enumerated()), id: \.offset) { _, record in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(record.name)
                                        .scaledFont(12, weight: .semibold, design: .monospaced)
                                        .foregroundStyle(theme.labelFaint)
                                    Text(record.value)
                                        .scaledFont(14, design: .monospaced)
                                        .foregroundStyle(theme.label)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                    if let timing = result.serverTimings.first {
                        Text("Answered by \(timing.server) in \(timing.timeString).")
                            .scaledFont(11)
                            .foregroundStyle(theme.labelFaint)
                    }
                }
            }
        }
    }

    // MARK: - Shared

    private func fieldLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .scaledFont(11, weight: .semibold)
            .tracking(0.8)
            .foregroundStyle(theme.labelFaint)
    }

    private func runButton(title: String, systemImage: String, isRunning: Bool,
                           action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: 9) {
                if isRunning {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .foregroundStyle(.white)
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(theme.accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isRunning || trimmedHost.isEmpty)
        .opacity(trimmedHost.isEmpty ? 0.55 : 1)
    }
}
