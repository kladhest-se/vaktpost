import XCTest
@testable import Vaktpost

/// These counters are not guaranteed to only go up, and everything awkward
/// about this type follows from that.
final class InterfaceErrorTrackerTests: XCTestCase {

    private func iface(_ device: String, inErrs: Double, outErrs: Double,
                       collisions: Double = 0) -> InterfaceStat {
        let raw: [String: Any] = ["hwif": device, "descr": device.uppercased(),
                                  "status": "up", "inerrs": inErrs,
                                  "outerrs": outErrs, "collisions": collisions]
        let data = try! JSONSerialization.data(withJSONObject: raw)
        let value = try! JSONDecoder().decode(JSONValue.self, from: data)
        return InterfaceStat(JSONDict(value)!)
    }

    private func at(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_800_000_000 + seconds)
    }

    // MARK: The first reading

    func testTheFirstReadingReportsNoChange() {
        // A total since boot is not a change. Reporting one would flag every
        // interface on the first refresh after launch, which is the fastest
        // way to make somebody stop reading the warning.
        var tracker = InterfaceErrorTracker()
        tracker.record([iface("igb0", inErrs: 4_211, outErrs: 12)], at: at(0))
        XCTAssertNil(tracker.changes["igb0"])
    }

    // MARK: Rising and not rising

    func testNewErrorsAreReportedAsChange() {
        var tracker = InterfaceErrorTracker()
        tracker.record([iface("igb0", inErrs: 100, outErrs: 10)], at: at(0))
        tracker.record([iface("igb0", inErrs: 106, outErrs: 12)], at: at(30))

        let change = tracker.changes["igb0"]
        XCTAssertEqual(change?.inErrors, 6)
        XCTAssertEqual(change?.outErrors, 2)
        XCTAssertEqual(change?.total, 8)
        XCTAssertEqual(change?.isRising, true)
    }

    func testAStaticCounterIsNotRising() {
        // The distinction the screen turns on. A link that collected errors
        // months ago and one collecting them now show the same total.
        var tracker = InterfaceErrorTracker()
        tracker.record([iface("igb0", inErrs: 4_211, outErrs: 12)], at: at(0))
        tracker.record([iface("igb0", inErrs: 4_211, outErrs: 12)], at: at(30))
        XCTAssertEqual(tracker.changes["igb0"]?.isRising, false)
    }

    func testCollisionsCountAsErrors() {
        var tracker = InterfaceErrorTracker()
        tracker.record([iface("igb0", inErrs: 0, outErrs: 0, collisions: 0)], at: at(0))
        tracker.record([iface("igb0", inErrs: 0, outErrs: 0, collisions: 5)], at: at(30))
        XCTAssertEqual(tracker.changes["igb0"]?.collisions, 5)
        XCTAssertEqual(tracker.changes["igb0"]?.isRising, true)
    }

    // MARK: Counters that go backwards

    func testARebootIsNotNegativeErrors() {
        // A reboot, an interface bounce or a driver reload resets these.
        // Subtracting anyway gives a negative, and re-baselining wrongly gives
        // a large positive on the reading after that.
        var tracker = InterfaceErrorTracker()
        tracker.record([iface("igb0", inErrs: 4_211, outErrs: 12)], at: at(0))
        tracker.record([iface("igb0", inErrs: 3, outErrs: 0)], at: at(30))

        let change = tracker.changes["igb0"]
        XCTAssertEqual(change?.counterReset, true)
        XCTAssertEqual(change?.total, 0)
        XCTAssertEqual(change?.isRising, false, "a reset is not a fault")
        XCTAssertNil(change?.perMinute, "and there is no rate to report")
    }

    func testTheReadingAfterAResetMeasuresFromTheNewBaseline() {
        var tracker = InterfaceErrorTracker()
        tracker.record([iface("igb0", inErrs: 4_211, outErrs: 12)], at: at(0))
        tracker.record([iface("igb0", inErrs: 3, outErrs: 0)], at: at(30))
        tracker.record([iface("igb0", inErrs: 5, outErrs: 0)], at: at(60))

        XCTAssertEqual(tracker.changes["igb0"]?.counterReset, false)
        XCTAssertEqual(tracker.changes["igb0"]?.total, 2, "not 4211 and not -4206")
    }

    // MARK: Rates

    func testAShortIntervalReportsNoRate() {
        // Two errors across a two-second poll is "sixty a minute", which is a
        // projection rather than a measurement and reads as far more alarming
        // than what was seen.
        var tracker = InterfaceErrorTracker()
        tracker.record([iface("igb0", inErrs: 0, outErrs: 0)], at: at(0))
        tracker.record([iface("igb0", inErrs: 2, outErrs: 0)], at: at(2))

        XCTAssertEqual(tracker.changes["igb0"]?.isRising, true, "it is still rising")
        XCTAssertNil(tracker.changes["igb0"]?.perMinute, "but there is no honest rate yet")
    }

    func testALongEnoughIntervalReportsARate() {
        var tracker = InterfaceErrorTracker()
        tracker.record([iface("igb0", inErrs: 0, outErrs: 0)], at: at(0))
        tracker.record([iface("igb0", inErrs: 30, outErrs: 0)], at: at(60))
        XCTAssertEqual(tracker.changes["igb0"]?.perMinute ?? 0, 30, accuracy: 0.01)
    }

    // MARK: Identity and scope

    func testInterfacesAreTrackedByDeviceNotDescription() {
        // A description can be edited on the firewall. Renaming an interface
        // should not look like a counter reset.
        var tracker = InterfaceErrorTracker()
        tracker.record([iface("igb0", inErrs: 10, outErrs: 0)], at: at(0))

        let renamed: InterfaceStat = {
            let raw: [String: Any] = ["hwif": "igb0", "descr": "WAN_RENAMED",
                                      "status": "up", "inerrs": 12, "outerrs": 0]
            let data = try! JSONSerialization.data(withJSONObject: raw)
            let value = try! JSONDecoder().decode(JSONValue.self, from: data)
            return InterfaceStat(JSONDict(value)!)
        }()
        tracker.record([renamed], at: at(30))

        XCTAssertEqual(tracker.changes["igb0"]?.total, 2)
        XCTAssertEqual(tracker.changes["igb0"]?.counterReset, false)
    }

    func testOnlyRisingInterfacesAreListed() {
        var tracker = InterfaceErrorTracker()
        let first = [iface("igb0", inErrs: 0, outErrs: 0), iface("igb1", inErrs: 99, outErrs: 0)]
        let second = [iface("igb0", inErrs: 7, outErrs: 0), iface("igb1", inErrs: 99, outErrs: 0)]
        tracker.record(first, at: at(0))
        tracker.record(second, at: at(30))

        XCTAssertEqual(tracker.rising(among: second).map(\.device), ["igb0"])
    }

    func testAnInterfaceWithoutCountersIsIgnored() {
        var tracker = InterfaceErrorTracker()
        let raw: [String: Any] = ["hwif": "ovpns1", "descr": "OPENVPN1", "status": "up"]
        let data = try! JSONSerialization.data(withJSONObject: raw)
        let value = try! JSONDecoder().decode(JSONValue.self, from: data)
        tracker.record([InterfaceStat(JSONDict(value)!)], at: at(0))
        tracker.record([InterfaceStat(JSONDict(value)!)], at: at(30))
        XCTAssertTrue(tracker.changes.isEmpty)
    }

    func testResettingForgetsEverything() {
        // A different firewall's counters are not a continuation of this one's.
        var tracker = InterfaceErrorTracker()
        tracker.record([iface("igb0", inErrs: 0, outErrs: 0)], at: at(0))
        tracker.record([iface("igb0", inErrs: 5, outErrs: 0)], at: at(30))
        tracker.reset()
        XCTAssertTrue(tracker.changes.isEmpty)

        tracker.record([iface("igb0", inErrs: 500, outErrs: 0)], at: at(60))
        XCTAssertNil(tracker.changes["igb0"], "the first reading after a reset is a baseline")
    }
}
