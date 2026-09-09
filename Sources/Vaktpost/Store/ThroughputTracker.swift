import Foundation

/// Maximum elapsed time between samples before a throughput reading is discarded.
///
/// Beyond seven days the counters are almost certainly from a different interface
/// or a rebooted box, so treating them as a counter reset (which they are) is
/// correct, but the delta would be enormous and produce a bogus spike.
private let maxThroughputElapsed: TimeInterval = 7 * 86_400

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

        init(at: Date, inBps: Double, outBps: Double) {
            self.at = at
            self.inBps = inBps
            self.outBps = outBps
        }
    }

    private struct Reading {
        var at: Date
        var inBytes: Double
        var outBytes: Double
    }

    /// Roughly 30 minutes at the default 30s refresh.
    private let capacity: Int

    /// 60 points is half an hour at the default refresh, and two minutes at
    /// the interface screen's two-second poll. The live screen asks for more
    /// so its chart covers a useful span rather than the last ninety seconds.
    ///
    /// `bitsMultiplier` controls the output units: `8` produces bits per
    /// second (LAN interfaces), `1` produces bytes per second (VPN tunnels).
    init(capacity: Int = 60, bitsMultiplier: Double = 8) {
        self.capacity = capacity
        self.bitsMultiplier = bitsMultiplier
    }

    private var last: [String: Reading] = [:]
    @Published private(set) var series: [String: [Point]] = [:]

    private let bitsMultiplier: Double

    func ingest(_ interfaces: [InterfaceStat], at now: Date = Date()) {
        for iface in interfaces {
            guard let inBytes = iface.inBytes, let outBytes = iface.outBytes else { continue }
            // Keyed by the interface, not by its hardware device.
            //
            // Every VLAN on a lagg reports the same `hwif`, so keying on that
            // put five interfaces in one series: each refresh differenced one
            // VLAN's counters against another's, produced a negative delta,
            // and cleared the history as if the counter had reset. The series
            // never grew past a single point.
            let key = iface.seriesKey
            defer { last[key] = Reading(at: now, inBytes: inBytes, outBytes: outBytes) }

            guard let previous = last[key] else { continue }
            let elapsed = now.timeIntervalSince(previous.at)
            guard elapsed > 0.5, elapsed < maxThroughputElapsed else { continue }

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
                inBps: deltaIn * bitsMultiplier / elapsed,
                outBps: deltaOut * bitsMultiplier / elapsed
            ))
            if points.count > capacity { points.removeFirst(points.count - capacity) }
            series[key] = points
        }
    }

    /// Ingest a single key — used for VPN tunnels where the byte counts come
    /// from the OpenVPN / WireGuard status endpoints rather than InterfaceStat.
    func ingest(key: String, inBytes: Double, outBytes: Double, at now: Date = Date()) {
        let prev = last[key]
        defer { last[key] = Reading(at: now, inBytes: inBytes, outBytes: outBytes) }
        guard let prev else { return }
        let elapsed = now.timeIntervalSince(prev.at)
        guard elapsed > 0.5, elapsed < maxThroughputElapsed else { return }

        let deltaIn = inBytes - prev.inBytes
        let deltaOut = outBytes - prev.outBytes

        guard deltaIn >= 0, deltaOut >= 0 else {
            series[key] = []
            return
        }

        var points = series[key] ?? []
        points.append(Point(
            at: now,
            inBps: deltaIn * bitsMultiplier / elapsed,
            outBps: deltaOut * bitsMultiplier / elapsed
        ))
        if points.count > capacity { points.removeFirst(points.count - capacity) }
        series[key] = points
    }

    func points(for device: String) -> [Point] { series[device] ?? [] }

    /// What the tracker has, for the diagnostics screen.
    ///
    /// The dashboard chart has never drawn a line while the two-second detail
    /// chart does, and reading the code has not explained why — the keys
    /// match, the counters arrive, and the arithmetic is covered by tests. So
    /// the app reports its own state instead of being reasoned about.
    var summary: [(key: String, points: Int, lastSample: Date?)] {
        series.keys.sorted().map { key in
            (key, series[key]?.count ?? 0, last[key]?.at)
        }
    }

    /// Interfaces a reading has been taken for but which have no rate yet.
    /// One baseline and no second sample is the normal state for thirty
    /// seconds after launch and a bug if it persists.
    var awaitingSecondSample: [String] {
        last.keys.filter { (series[$0]?.isEmpty ?? true) }.sorted()
    }

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
