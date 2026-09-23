import SwiftUI

/// A one-tap throughput measurement run from the firewall itself, not the
/// phone — so a fast-but-far VPN tunnel, or a phone on weak Wi-Fi, does not
/// masquerade as a slow WAN link. Builds a short on-device history across
/// runs, scoped to this one firewall, so a trend is visible without needing
/// several app opens to notice one.
///
/// Lives inside Network Tools rather than on a screen of its own: it asks the
/// firewall a question about its link, which is what ping, traceroute and DNS
/// lookup there do too, and one fewer entry in More is one less place to look.
struct SpeedtestSection: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore

    @State private var isRunning = false
    @State private var latest: SpeedtestResult?
    @State private var history: [SpeedtestResult] = []
    @State private var errorMessage: String?

    private static let historyLimit = 20

    private var historyKey: String {
        "Speedtest.history.\(store.activeProfile?.id.uuidString ?? "unknown")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Downloads and uploads a fixed test file over HTTPS and times it — the same "
                + "approach a browser-based speed test uses, run from the firewall itself so the "
                + "result reflects its WAN link rather than this phone's own connection back to it.")
                .scaledFont(12)
                .foregroundStyle(theme.labelFaint)

            runButton

            if let errorMessage {
                Notice(symbol: "exclamationmark.triangle", title: "Speed test failed",
                       detail: errorMessage, health: .warn)
            }

            if let latest {
                if latest.available {
                    resultSlab(latest)
                } else {
                    Notice(symbol: "wifi.slash", title: "Not available",
                           detail: latest.reason ?? "The firewall could not complete a speed test.",
                           health: .warn)
                }
            }

            if history.count > 1 {
                historySlab
            }
        }
        // Keyed to the firewall, the same way every lazy-loaded screen this
        // session was fixed to react to a switch: reloads this firewall's
        // own history rather than showing the previous one's numbers as if
        // they belonged to whichever firewall is now active.
        .task(id: store.activeProfile?.id) { loadHistory() }
    }

    private var runButton: some View {
        Button {
            Task { await run() }
        } label: {
            HStack(spacing: 9) {
                if isRunning {
                    ProgressView().controlSize(.small).tint(.white)
                    Text("Testing — this takes about a minute…")
                } else {
                    Image(systemName: "gauge.with.dots.needle.67percent")
                    Text("Run Speed Test")
                }
            }
            .foregroundStyle(.white)
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(theme.accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isRunning)
        .opacity(isRunning ? 0.7 : 1)
    }

    private func resultSlab(_ result: SpeedtestResult) -> some View {
        Slab(rail: .ok, title: "Result", trailing: result.server) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 20) {
                    metric("DOWNLOAD", result.downloadMbps.map { String(format: "%.0f Mbps", $0) } ?? "—")
                    metric("UPLOAD", result.uploadMbps.map { String(format: "%.0f Mbps", $0) } ?? "—")
                    metric("PING", result.pingMs.map { String(format: "%.0f ms", $0) } ?? "—")
                }
                Text(result.date, style: .relative)
                    .scaledFont(11)
                    .foregroundStyle(theme.labelFaint)
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .scaledFont(10, weight: .bold, design: .rounded)
                .tracking(0.6)
                .foregroundStyle(theme.labelFaint)
            Text(value)
                .scaledFont(18, weight: .semibold, design: .monospaced)
                .foregroundStyle(theme.label)
        }
    }

    private var historySlab: some View {
        Slab(rail: .info, title: "History") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(history.prefix(10)) { entry in
                    HStack {
                        Text(entry.date, style: .date)
                            .scaledFont(11, design: .monospaced)
                            .foregroundStyle(theme.labelFaint)
                        Spacer()
                        if entry.available {
                            Text("\(entry.downloadMbps.map { String(format: "%.0f", $0) } ?? "—")↓ "
                                + "\(entry.uploadMbps.map { String(format: "%.0f", $0) } ?? "—")↑ Mbps")
                                .scaledFont(12, design: .monospaced)
                                .foregroundStyle(theme.label)
                        } else {
                            Text("unavailable")
                                .scaledFont(12)
                                .foregroundStyle(theme.labelFaint)
                        }
                    }
                }
            }
        }
    }

    private func run() async {
        isRunning = true
        errorMessage = nil
        defer { isRunning = false }
        do {
            let result = try await store.client.speedtest()
            latest = result
            history.insert(result, at: 0)
            if history.count > Self.historyLimit { history.removeLast(history.count - Self.historyLimit) }
            saveHistory()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let decoded = try? JSONDecoder().decode([SpeedtestResult].self, from: data) else {
            history = []
            latest = nil
            return
        }
        history = decoded
        latest = decoded.first
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        UserDefaults.standard.set(data, forKey: historyKey)
    }
}
