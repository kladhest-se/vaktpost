import Foundation
import Observation

/// Maximum elapsed time between samples before a throughput reading is discarded.
///
/// Beyond seven days the counters are almost certainly from a different interface
/// or a rebooted box, so treating them as a counter reset (which they are) is
/// correct, but the delta would be enormous and produce a bogus spike.
private let maxThroughputElapsed: TimeInterval = 7 * 86_400

/// Derives interface throughput from cumulative byte counters.
///
/// pfSense reports lifetime `inbytes`/`outbytes` per interface, not a
/// rate. Differencing consecutive samples client-side gives bits per second
/// without needing anything extra on the firewall. Counters reset when an
/// interface bounces or the box reboots, so a negative delta is treated as a
/// reset and dropped rather than rendered as a spike.
@MainActor
@Observable
final class ThroughputTracker {

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
    private(set) var series: [String: [Point]] = [:]

    private let bitsMultiplier: Double

    /// What this tracker's points are measured in.
    ///
    /// Derived from the multiplier rather than stored alongside it, so the two
    /// cannot disagree. A multiplier of eight turns byte counters into bits; a
    /// multiplier of one leaves them as bytes.
    var unit: RateUnit { bitsMultiplier == 1 ? .bytes : .bits }

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

/// Which unit a series of rates is in.
///
/// This exists because the answer is not the same everywhere and remembering
/// which is which at each call site does not work. `ThroughputTracker` is
/// constructed twice: once for interfaces, where byte counters are multiplied
/// by eight and the series is bits per second, and once for VPN tunnels, where
/// the multiplier is one and it stays bytes per second.
///
/// `ThroughputChart` fed the interface tracker's bits into `Sparkline`, whose
/// tooltip formatted them as bytes — so the tooltip read "1.4 MiB/s" over a
/// legend reading "11.8 Mbit/s", for the same sample, a factor of 8.4 apart
/// (eight for bits against bytes, and again 1024 against 1000). Both were
/// drawn on the same card.
///
/// Carrying the unit with the tracker rather than at the call site is what
/// stops that recurring: a caller that forgets to pass one gets the wrong
/// label, but a caller that passes `tracker.unit` cannot.
enum RateUnit {
    case bits
    case bytes

    func format(_ value: Double) -> String {
        switch self {
        case .bits: return Rate.bits(value)
        case .bytes: return Fmt.bytesPerSec(value)
        }
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
    
    static func bytes(_ b: Double) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = b
        var i = 0
        while v >= 1024, i < units.count - 1 { v /= 1024; i += 1 }
        return String(format: i == 0 ? "%.0f %@" : "%.1f %@", v, units[i])
    }
}

// MARK: - Chart axis scale

/// Rounds a peak sample up to a "nice" axis top — 1, 2, 2.5, 5, or 10 times a
/// power of ten — the way every chart worth reading is scaled, rather than
/// whatever exact value the highest sample happened to be.
enum AxisScale {
    static func niceMax(for peak: Double) -> Double {
        guard peak > 0, peak.isFinite else { return 1 }
        let magnitude = pow(10, floor(log10(peak)))
        let normalised = peak / magnitude
        let step: Double
        switch normalised {
        case ...1: step = 1
        case ...2: step = 2
        case ...2.5: step = 2.5
        case ...5: step = 5
        default: step = 10
        }
        return step * magnitude
    }

    /// Four tick values from the axis top down to zero, in reading order —
    /// the order a Y-axis is labelled in, top to bottom.
    static func ticks(for peak: Double, count: Int = 4) -> [Double] {
        let top = niceMax(for: peak)
        guard count > 1 else { return [top] }
        return (0..<count).map { top * Double(count - 1 - $0) / Double(count - 1) }
    }
}

extension RateUnit {
    /// The divisor and suffix every tick on one axis shares, chosen from the
    /// axis top so "2.5" and "10.0" on the same chart read in the same unit
    /// rather than each auto-scaling on its own — which is exactly the
    /// mismatch that made the tooltip and the legend once disagree.
    ///
    /// Axis labels use the short "bps/Kbps/Mbps" family rather than
    /// `Rate.bits`'s "bit/s" — a Y-axis column is narrow, and the shorter
    /// form is also the convention every reference dashboard uses on one.
    private func axisStep(for axisMax: Double) -> (divisor: Double, suffix: String) {
        switch self {
        case .bits:
            let units = ["bps", "Kbps", "Mbps", "Gbps"]
            var v = axisMax, i = 0
            while v >= 1000, i < units.count - 1 { v /= 1000; i += 1 }
            return (pow(1000, Double(i)), units[i])
        case .bytes:
            let units = ["B/s", "KiB/s", "MiB/s", "GiB/s"]
            var v = axisMax, i = 0
            while v >= 1024, i < units.count - 1 { v /= 1024; i += 1 }
            return (pow(1024, Double(i)), units[i])
        }
    }

    /// A tick label in the axis's shared unit — the origin always reads "0"
    /// in the base unit, matching the convention every reference dashboard
    /// uses even when the rest of the axis is in Kbps or Mbps.
    func axisLabel(_ value: Double, axisMax: Double) -> String {
        guard value > 0 else {
            switch self {
            case .bits: return "0 bps"
            case .bytes: return "0 B/s"
            }
        }
        let step = axisStep(for: axisMax)
        let scaled = value / step.divisor
        return String(format: step.divisor == 1 ? "%.0f %@" : "%.1f %@", scaled, step.suffix)
    }
}
