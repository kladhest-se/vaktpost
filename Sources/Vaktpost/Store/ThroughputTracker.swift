import Foundation

/// Derives interface throughput from cumulative byte counters.
///
/// The REST API reports lifetime `inbytes`/`outbytes` per interface, not a
/// rate. Differencing consecutive samples client-side gives bits per second
/// without needing anything extra on the firewall. Counters reset when an
/// interface bounces or the box reboots, so a negative delta is treated as a
/// reset and dropped rather than rendered as a spike.
@MainActor
final class ThroughputTracker: ObservableObject {

    struct Point: Identifiable {
        let id = UUID()
        var at: Date
        var inBps: Double
        var outBps: Double
    }

    private struct Reading {
        var at: Date
        var inBytes: Double
        var outBytes: Double
    }

    /// Roughly 30 minutes at the default 30s refresh.
    private let capacity = 60

    private var last: [String: Reading] = [:]
    @Published private(set) var series: [String: [Point]] = [:]

    func ingest(_ interfaces: [InterfaceStat], at now: Date = Date()) {
        for iface in interfaces {
            guard let inBytes = iface.inBytes, let outBytes = iface.outBytes else { continue }
            let key = iface.device
            defer { last[key] = Reading(at: now, inBytes: inBytes, outBytes: outBytes) }

            guard let previous = last[key] else { continue }
            let elapsed = now.timeIntervalSince(previous.at)
            guard elapsed > 0.5 else { continue }

            let deltaIn = inBytes - previous.inBytes
            let deltaOut = outBytes - previous.outBytes
            guard deltaIn >= 0, deltaOut >= 0 else {
                // Counter reset — start a fresh baseline instead of charting a spike.
                series[key] = []
                continue
            }

            var points = series[key] ?? []
            points.append(Point(
                at: now,
                inBps: deltaIn * 8 / elapsed,
                outBps: deltaOut * 8 / elapsed
            ))
            if points.count > capacity { points.removeFirst(points.count - capacity) }
            series[key] = points
        }
    }

    func points(for device: String) -> [Point] { series[device] ?? [] }

    func latest(for device: String) -> Point? { series[device]?.last }

    /// Clears everything — used when switching firewalls, since counters from a
    /// different box would otherwise produce one enormous bogus delta.
    func reset() {
        last.removeAll()
        series.removeAll()
    }
}

enum Rate {
    static func bits(_ bps: Double) -> String {
        let units = ["bit/s", "kbit/s", "Mbit/s", "Gbit/s"]
        var v = bps
        var i = 0
        while v >= 1000, i < units.count - 1 { v /= 1000; i += 1 }
        return String(format: i == 0 ? "%.0f %@" : "%.1f %@", v, units[i])
    }
}
