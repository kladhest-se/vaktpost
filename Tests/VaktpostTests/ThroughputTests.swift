import XCTest
@testable import Vaktpost

/// Rates are differenced from lifetime counters, so the two things that can go
/// wrong are arithmetic and counter resets. A reset drawn as a spike is worse
/// than no chart, because it looks like a traffic event.
@MainActor
final class ThroughputTests: XCTestCase {

    /// The tracker keys by interface, not by hardware device: every VLAN on
    /// a lagg reports the same `hwif`, so a device key put five interfaces in
    /// one series. These tests build the same key the app does.
    private func key(_ device: String) -> String {
        iface(device, inBytes: 0, outBytes: 0).seriesKey
    }

    private func iface(_ device: String, inBytes: Double, outBytes: Double) -> InterfaceStat {
        let raw: [String: Any] = [
            "name": device.uppercased(), "hwif": device, "status": "up",
            "inbytes": inBytes, "outbytes": outBytes,
        ]
        let data = try! JSONSerialization.data(withJSONObject: raw)
        let value = try! JSONDecoder().decode(JSONValue.self, from: data)
        return InterfaceStat(JSONDict(value)!)
    }

    func testFirstSampleProducesNoPoint() {
        let tracker = ThroughputTracker()
        tracker.ingest([iface("igb0", inBytes: 1000, outBytes: 500)], at: Date())
        XCTAssertTrue(tracker.points(for: key("igb0")).isEmpty, "a rate needs two readings")
    }

    func testSecondSampleProducesBitsPerSecond() {
        let tracker = ThroughputTracker()
        let t0 = Date()
        tracker.ingest([iface("igb0", inBytes: 0, outBytes: 0)], at: t0)
        tracker.ingest([iface("igb0", inBytes: 1250, outBytes: 250)], at: t0.addingTimeInterval(10))

        let point = tracker.latest(for: key("igb0"))
        // 1250 bytes over 10s is 1000 bit/s.
        XCTAssertEqual(point?.inBps ?? 0, 1000, accuracy: 0.001)
        XCTAssertEqual(point?.outBps ?? 0, 200, accuracy: 0.001)
    }

    func testCounterResetStartsAFreshBaseline() {
        let tracker = ThroughputTracker()
        let t0 = Date()
        tracker.ingest([iface("igb0", inBytes: 0, outBytes: 0)], at: t0)
        tracker.ingest([iface("igb0", inBytes: 5000, outBytes: 5000)], at: t0.addingTimeInterval(10))
        XCTAssertEqual(tracker.points(for: key("igb0")).count, 1)

        // The interface bounced and the counter went back to zero.
        tracker.ingest([iface("igb0", inBytes: 10, outBytes: 10)], at: t0.addingTimeInterval(20))
        XCTAssertTrue(tracker.points(for: key("igb0")).isEmpty,
                      "a negative delta must clear the series, not chart a spike")
    }

    func testSimultaneousSamplesAreIgnored() {
        // Dividing by a zero interval is an infinite rate, which renders as a
        // chart with one bar and no scale.
        let tracker = ThroughputTracker()
        let t0 = Date()
        tracker.ingest([iface("igb0", inBytes: 0, outBytes: 0)], at: t0)
        tracker.ingest([iface("igb0", inBytes: 100, outBytes: 100)], at: t0)
        XCTAssertTrue(tracker.points(for: key("igb0")).isEmpty)
    }

    func testResetClearsEverything() {
        let tracker = ThroughputTracker()
        let t0 = Date()
        tracker.ingest([iface("igb0", inBytes: 0, outBytes: 0)], at: t0)
        tracker.ingest([iface("igb0", inBytes: 100, outBytes: 100)], at: t0.addingTimeInterval(5))
        XCTAssertFalse(tracker.points(for: key("igb0")).isEmpty)

        tracker.reset()
        XCTAssertTrue(tracker.points(for: key("igb0")).isEmpty)

        // And the baseline is gone too, so the next pair starts clean rather
        // than differencing against the previous firewall's counters.
        tracker.ingest([iface("igb0", inBytes: 9_000_000, outBytes: 0)], at: t0.addingTimeInterval(10))
        XCTAssertTrue(tracker.points(for: key("igb0")).isEmpty)
    }

    func testHistoryIsBounded() {
        let tracker = ThroughputTracker()
        let t0 = Date()
        for i in 0...200 {
            tracker.ingest(
                [iface("igb0", inBytes: Double(i) * 1000, outBytes: Double(i) * 100)],
                at: t0.addingTimeInterval(Double(i) * 30)
            )
        }
        XCTAssertLessThanOrEqual(tracker.points(for: key("igb0")).count, 60)
    }
}

/// Series identity. VLANs on a lagg all report the same hardware device.
@MainActor
final class ThroughputKeyTests: XCTestCase {

    private func iface(name: String, hwif: String, inBytes: Double) -> InterfaceStat {
        let raw: [String: Any] = [
            "descr": name, "hwif": hwif, "status": "up",
            "inbytes": inBytes, "outbytes": inBytes,
        ]
        let data = try! JSONSerialization.data(withJSONObject: raw)
        return InterfaceStat(JSONDict(try! JSONDecoder().decode(JSONValue.self, from: data))!)
    }

    func testVLANsOnOneLaggDoNotShareASeries() {
        // Five VLANs reporting hwif "lagg0" were one series: each refresh
        // differenced one VLAN's counters against another's, produced a
        // negative delta, and cleared the history as a counter reset. The
        // series never grew past a single point.
        let a = iface(name: "VLAN_100", hwif: "lagg0", inBytes: 1000)
        let b = iface(name: "VLAN_200", hwif: "lagg0", inBytes: 500)
        XCTAssertNotEqual(a.seriesKey, b.seriesKey)
    }

    func testHistoryAccumulatesPerInterface() {
        let tracker = ThroughputTracker()
        let t0 = Date()
        for step in 0...3 {
            tracker.ingest([
                iface(name: "VLAN_100", hwif: "lagg0", inBytes: Double(step) * 1000),
                iface(name: "VLAN_200", hwif: "lagg0", inBytes: Double(step) * 2000),
            ], at: t0.addingTimeInterval(Double(step) * 30))
        }
        let a = iface(name: "VLAN_100", hwif: "lagg0", inBytes: 0)
        let b = iface(name: "VLAN_200", hwif: "lagg0", inBytes: 0)
        XCTAssertEqual(tracker.points(for: a.seriesKey).count, 3)
        XCTAssertEqual(tracker.points(for: b.seriesKey).count, 3)
        // And the rates are each interface's own, not a blend.
        XCTAssertEqual(tracker.latest(for: a.seriesKey)?.inBps ?? 0,
                       1000 * 8 / 30, accuracy: 0.001)
        XCTAssertEqual(tracker.latest(for: b.seriesKey)?.inBps ?? 0,
                       2000 * 8 / 30, accuracy: 0.001)
    }
}

/// The live monitor's tracker, which keeps a longer history at a faster poll.
@MainActor
final class LiveThroughputTests: XCTestCase {

    private func iface(_ name: String, hwif: String, inBytes: Double, outBytes: Double) -> InterfaceStat {
        let raw: [String: Any] = ["name": name, "hwif": hwif,
                                  "inbytes": inBytes, "outbytes": outBytes]
        let data = try! JSONSerialization.data(withJSONObject: raw)
        return InterfaceStat(JSONDict(try! JSONDecoder().decode(JSONValue.self, from: data))!)
    }

    func testACapacityCanBeAskedFor() {
        // The detail screen polls every two seconds; 60 points would be two
        // minutes of history, which is not enough to see a transfer's shape.
        let live = ThroughputTracker(capacity: 180)
        let t0 = Date()
        for step in 0...200 {
            live.ingest([iface("WAN_1", hwif: "ix0",
                               inBytes: Double(step) * 250_000,
                               outBytes: Double(step) * 125_000)],
                        at: t0.addingTimeInterval(Double(step) * 2))
        }
        let key = iface("WAN_1", hwif: "ix0", inBytes: 0, outBytes: 0).seriesKey
        XCTAssertEqual(live.points(for: key).count, 180)
    }

    func testRatesAreBitsPerSecond() {
        // 250 kB over 2 seconds is 1 Mbit/s. The detail screen formats with
        // Rate.bits, and would be eight times out if the tracker stored bytes.
        let live = ThroughputTracker(capacity: 10)
        let t0 = Date()
        live.ingest([iface("WAN_1", hwif: "ix0", inBytes: 0, outBytes: 0)], at: t0)
        live.ingest([iface("WAN_1", hwif: "ix0", inBytes: 250_000, outBytes: 0)],
                    at: t0.addingTimeInterval(2))

        let key = iface("WAN_1", hwif: "ix0", inBytes: 0, outBytes: 0).seriesKey
        let rate = live.points(for: key).last?.inBps ?? 0
        XCTAssertEqual(rate, 1_000_000, accuracy: 1)
        XCTAssertEqual(Rate.bits(rate), "1.0 Mbit/s")
    }

    func testTheLiveTrackerIsSeparateFromTheDashboardOne() {
        // A minute spent watching one interface must not flush the half-hour
        // of history every other screen draws from.
        let dashboard = ThroughputTracker()
        let live = ThroughputTracker(capacity: 180)
        let t0 = Date()
        for step in 0...3 {
            dashboard.ingest([iface("WAN_1", hwif: "ix0",
                                    inBytes: Double(step) * 1000, outBytes: 0)],
                             at: t0.addingTimeInterval(Double(step) * 30))
        }
        live.reset()
        let key = iface("WAN_1", hwif: "ix0", inBytes: 0, outBytes: 0).seriesKey
        XCTAssertEqual(dashboard.points(for: key).count, 3)
        XCTAssertTrue(live.points(for: key).isEmpty)
    }
}
