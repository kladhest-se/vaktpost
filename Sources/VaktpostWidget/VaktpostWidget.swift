import WidgetKit
import SwiftUI

// MARK: - Timeline

struct StatusEntry: TimelineEntry {
    let date: Date
    let snapshot: SharedSnapshot?
}

struct StatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry {
        StatusEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        completion(StatusEntry(date: Date(), snapshot: SharedSnapshot.read() ?? .preview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        let entry = StatusEntry(date: Date(), snapshot: SharedSnapshot.read())
        // The app reloads timelines after every refresh; this interval is only
        // the fallback so a stale card eventually re-renders its age label.
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

extension SharedSnapshot {
    static var preview: SharedSnapshot {
        var s = SharedSnapshot()
        s.serverLabel = "fw01"
        s.capturedAt = Date()
        s.level = .ok
        s.headline = "All monitored paths healthy"
        s.interfacesUp = 4
        s.interfacesTotal = 4
        s.gateways = [.init(name: "WAN_DHCP", status: "online", delayMS: 8.4,
                            lossPercent: 0, level: .ok)]
        s.wanInBps = 18_400_000
        s.wanOutBps = 2_100_000
        return s
    }
}

// MARK: - Colours

private extension SharedSnapshot.Level {
    func color(_ p: Palette) -> Color {
        switch self {
        case .ok: return p.green
        case .warn: return p.yellow
        case .bad: return p.red
        case .idle: return p.overlay0
        }
    }
}

private func widgetPalette(_ scheme: ColorScheme) -> Palette {
    // The widget cannot read the app's ObservableObject, so it mirrors the
    // default pairing: Latte in light, Mocha in dark.
    (scheme == .light ? Flavor.latte : Flavor.mocha).palette
}

// MARK: - Views

struct StatusWidgetView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetFamily) private var family
    let entry: StatusEntry

    private var palette: Palette { widgetPalette(scheme) }

    var body: some View {
        let snap = entry.snapshot

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill((snap?.level ?? .idle).color(palette))
                    .frame(width: 8, height: 8)
                Text(snap?.serverLabel ?? "Vaktpost")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                Spacer()
                if let count = snap?.alertCount, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(palette.crust)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(palette.red)
                        .clipShape(Capsule())
                }
            }

            if let snap {
                Text(snap.headline)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.subtext0)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if family != .systemSmall, let gw = snap.gateways.first {
                    HStack(spacing: 6) {
                        Text(gw.name)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(palette.text)
                            .lineLimit(1)
                        Spacer()
                        Text(readout(gw))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(gw.level.color(palette))
                    }
                }

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    metric("IF", "\(snap.interfacesUp)/\(snap.interfacesTotal)", palette.text)
                    if let inBps = snap.wanInBps {
                        metric("↓", short(inBps), palette.green)
                    }
                    if let outBps = snap.wanOutBps {
                        metric("↑", short(outBps), palette.sapphire)
                    }
                    Spacer()
                }

                Text(snap.capturedAt, style: .relative)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(palette.overlay0)
            } else {
                Spacer()
                Text("Open Vaktpost to sync")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.overlay1)
            }
        }
        .containerBackground(palette.base, for: .widget)
    }

    private func readout(_ gw: SharedSnapshot.GatewayLine) -> String {
        guard let d = gw.delayMS else { return gw.status }
        let loss = gw.lossPercent.map { String(format: " · %.0f%%", $0) } ?? ""
        return String(format: "%.1f ms", d) + loss
    }

    private func metric(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(palette.overlay1)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
    }

    private func short(_ bps: Double) -> String {
        let units = ["b", "k", "M", "G"]
        var v = bps
        var i = 0
        while v >= 1000, i < units.count - 1 { v /= 1000; i += 1 }
        return String(format: i == 0 ? "%.0f%@" : "%.1f%@", v, units[i])
    }
}

// MARK: - Widget

struct StatusWidget: Widget {
    let kind = "VaktpostStatus"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StatusProvider()) { entry in
            StatusWidgetView(entry: entry)
        }
        .configurationDisplayName("Firewall status")
        .description("Health, gateway latency and uplink rate from the last time Vaktpost refreshed.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct VaktpostWidgetBundle: WidgetBundle {
    var body: some Widget {
        StatusWidget()
    }
}
