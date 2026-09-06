import XCTest
@testable import Vaktpost

/// Rates are differenced from lifetime counters, so the two things that can go
/// wrong are arithmetic and counter resets. A reset drawn as a spike is worse
/// than no chart, because it looks like a traffic event.
@MainActor
final class ThroughputTests: XCTestCase {

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
        XCTAssertTrue(tracker.points(for: "igb0").isEmpty, "a rate needs two readings")
    }

    func testSecondSampleProducesBitsPerSecond() {
        let tracker = ThroughputTracker()
        let t0 = Date()
        tracker.ingest([iface("igb0", inBytes: 0, outBytes: 0)], at: t0)
        tracker.ingest([iface("igb0", inBytes: 1250, outBytes: 250)], at: t0.addingTimeInterval(10))

        let point = tracker.latest(for: "igb0")
        // 1250 bytes over 10s is 1000 bit/s.
        XCTAssertEqual(point?.inBps ?? 0, 1000, accuracy: 0.001)
        XCTAssertEqual(point?.outBps ?? 0, 200, accuracy: 0.001)
    }

    func testCounterResetStartsAFreshBaseline() {
        let tracker = ThroughputTracker()
        let t0 = Date()
        tracker.ingest([iface("igb0", inBytes: 0, outBytes: 0)], at: t0)
        tracker.ingest([iface("igb0", inBytes: 5000, outBytes: 5000)], at: t0.addingTimeInterval(10))
        XCTAssertEqual(tracker.points(for: "igb0").count, 1)

        // The interface bounced and the counter went back to zero.
        tracker.ingest([iface("igb0", inBytes: 10, outBytes: 10)], at: t0.addingTimeInterval(20))
        XCTAssertTrue(tracker.points(for: "igb0").isEmpty,
                      "a negative delta must clear the series, not chart a spike")
    }

    func testSimultaneousSamplesAreIgnored() {
        // Dividing by a zero interval is an infinite rate, which renders as a
        // chart with one bar and no scale.
        let tracker = ThroughputTracker()
        let t0 = Date()
        tracker.ingest([iface("igb0", inBytes: 0, outBytes: 0)], at: t0)
        tracker.ingest([iface("igb0", inBytes: 100, outBytes: 100)], at: t0)
        XCTAssertTrue(tracker.points(for: "igb0").isEmpty)
    }

    func testResetClearsEverything() {
        let tracker = ThroughputTracker()
        let t0 = Date()
        tracker.ingest([iface("igb0", inBytes: 0, outBytes: 0)], at: t0)
        tracker.ingest([iface("igb0", inBytes: 100, outBytes: 100)], at: t0.addingTimeInterval(5))
        XCTAssertFalse(tracker.points(for: "igb0").isEmpty)

        tracker.reset()
        XCTAssertTrue(tracker.points(for: "igb0").isEmpty)

        // And the baseline is gone too, so the next pair starts clean rather
        // than differencing against the previous firewall's counters.
        tracker.ingest([iface("igb0", inBytes: 9_000_000, outBytes: 0)], at: t0.addingTimeInterval(10))
        XCTAssertTrue(tracker.points(for: "igb0").isEmpty)
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
        XCTAssertLessThanOrEqual(tracker.points(for: "igb0").count, 60)
    }
}
