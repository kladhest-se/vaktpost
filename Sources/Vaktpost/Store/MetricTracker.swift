import Foundation
import Combine

/// Default number of points retained in time-series before old samples are discarded.
private let defaultSeriesCapacity = 60

/// Generic metric tracker that stores time-series readings.
/// Used for system metrics history and gateway delay/loss trends.
@MainActor
final class MetricTracker<Key: Hashable, Value: Numeric & Comparable>: ObservableObject {

    struct Point: Identifiable {
        let id = UUID()
        var at: Date
        var value: Value
    }

    private let capacity = defaultSeriesCapacity
    @Published private(set) var series: [Key: [Point]] = [:]

    /// Gauges are independent samples, not cumulative counters. Falling CPU,
    /// memory, disk, and swap readings are valid history, including the first.
    func ingest(key: Key, value: Value, at now: Date = Date()) {
        var points = series[key] ?? []
        if let previous = points.last {
            guard now.timeIntervalSince(previous.at) > 0.5 else { return }
        }
        points.append(Point(at: now, value: value))
        if points.count > capacity { points.removeFirst(points.count - capacity) }
        series[key] = points
    }

    func points(for key: Key) -> [Point] { series[key] ?? [] }

    func latest(for key: Key) -> Point? { series[key]?.last }

    func reset() {
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

    private let capacity = defaultSeriesCapacity
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

    private let capacity = defaultSeriesCapacity
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
