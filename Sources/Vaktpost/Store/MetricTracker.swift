import Foundation

/// Generic metric tracker that stores time-series readings.
/// Used for system metrics history and gateway delay/loss trends.
@MainActor
final class MetricTracker<Key: Hashable, Value: Numeric & Comparable>: ObservableObject {

    struct Point: Identifiable {
        let id = UUID()
        var at: Date
        var value: Value
    }

    private struct Reading {
        var at: Date
        var value: Value
    }

    /// Max points per key (roughly 30 minutes at default 30s refresh).
    private let capacity = 60
    private var last: [Key: Reading] = [:]
    @Published private(set) var series: [Key: [Point]] = [:]

    /// Feed in a new reading. Counters that decrease are treated as resets.
    func ingest(key: Key, value: Value, at now: Date = Date()) {
        defer { last[key] = Reading(at: now, value: value) }
        guard let previous = last[key] else { return }
        let elapsed = now.timeIntervalSince(previous.at)
        guard elapsed > 0.5, elapsed < 86400 * 7 else { return }
        let delta = value - previous.value
        guard delta >= Value.zero else {
            series[key] = []
            return
        }
        var points = series[key] ?? []
        points.append(Point(at: now, value: value))
        if points.count > capacity { points.removeFirst(points.count - capacity) }
        series[key] = points
    }

    func points(for key: Key) -> [Point] { series[key] ?? [] }

    func latest(for key: Key) -> Point? { series[key]?.last }

    func reset() {
        last.removeAll()
        series.removeAll()
    }
}

/// Gateway-specific tracker for delay and loss percentages.
@MainActor
final class GatewayMetricTracker: ObservableObject {

    struct Reading {
        let at: Date
        var delayMS: Double?
        var lossPercent: Double?
    }

    private let capacity = 60
    @Published private(set) var series: [String: [Reading]] = [:]

    func ingest(key: String, delayMS: Double?, lossPercent: Double?, at now: Date = Date()) {
        var readings = series[key] ?? []
        readings.append(Reading(at: now, delayMS: delayMS, lossPercent: lossPercent))
        if readings.count > capacity { readings.removeFirst(readings.count - capacity) }
        series[key] = readings
    }

    func readings(for key: String) -> [Reading] { series[key] ?? [] }
    func latest(for key: String) -> Reading? { series[key]?.last }

    func reset() {
        series.removeAll()
    }
}

/// Tracks state table current values across refreshes for trend visualization.
@MainActor
final class StateHistoryTracker: ObservableObject {

    struct Point: Identifiable {
        let id = UUID()
        var at: Date
        var value: Int
    }

    private let capacity = 60
    @Published private(set) var points: [Point] = []

    func ingest(current: Int, at now: Date = Date()) {
        var pts = points
        pts.append(Point(at: now, value: current))
        if pts.count > capacity { pts.removeFirst(pts.count - capacity) }
        points = pts
    }

    func latest() -> Int? { points.last?.value }

    func reset() { points.removeAll() }
}

/// Throughput-specific tracker that stores in/out bytes and computes rates.
@MainActor
final class ThroughputTrackerV2: ObservableObject {

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

    private let capacity = 60
    private var last: [String: Reading] = [:]
    @Published private(set) var series: [String: [Point]] = [:]

    func ingest(key: String, inBytes: Double, outBytes: Double, at now: Date = Date()) {
        let prev = last[key]
        defer { last[key] = Reading(at: now, inBytes: inBytes, outBytes: outBytes) }
        guard let prev else { return }
        let elapsed = now.timeIntervalSince(prev.at)
        guard elapsed > 0.5, elapsed < 86400 * 7 else { return }

        let deltaIn = inBytes - prev.inBytes
        let deltaOut = outBytes - prev.outBytes

        guard deltaIn >= 0, deltaOut >= 0 else {
            series[key] = []
            return
        }

        var points = series[key] ?? []
        points.append(Point(
            at: now,
            inBps: deltaIn / elapsed,
            outBps: deltaOut / elapsed
        ))
        if points.count > capacity { points.removeFirst(points.count - capacity) }
        series[key] = points
    }

    func inPoints(for key: String) -> [Point] {
        guard let points = series[key] else { return [] }
        return points.map { Point(at: $0.at, inBps: $0.inBps, outBps: 0) }
    }

    func outPoints(for key: String) -> [Point] {
        guard let points = series[key] else { return [] }
        return points.map { Point(at: $0.at, inBps: 0, outBps: $0.outBps) }
    }

    func latest(for key: String) -> Point? { series[key]?.last }

    func reset() {
        last.removeAll()
        series.removeAll()
    }
}
