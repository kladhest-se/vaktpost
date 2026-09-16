import XCTest
@testable import Vaktpost

final class IncidentGroupingTests: XCTestCase {
    /// A realistic filterlog line with a fixed source, action, and
    /// timestamp — the same field layout confirmed against a real capture
    /// elsewhere in this project: rule,,,tracker,iface,reason,action,
    /// direction,ipVersion,tos,,id,offset,ttl,proto#,proto,length,
    /// source,destination,srcPort,dstPort,dataLen,flags.
    private func filterLine(action: String, source: String, timestamp: String) -> LogLine {
        let text = "Sep 15 \(timestamp) filterlog[4711]: "
            + "5,,,1700000002,vtnet0,match,\(action),in,4,0x0,,51,44210,0,none,6,tcp,60,"
            + "\(source),198.51.100.24,51422,22,0,S,"
        var line = LogLine(text: text, kind: .firewall)
        line.timestamp = "2026-09-15 \(timestamp)"
        return line
    }

    private func event(action: String, source: String, timestamp: String) -> IncidentEvent {
        let events = IncidentTimeline.build([(.firewall, [filterLine(action: action, source: source, timestamp: timestamp)])])
        return events[0]
    }

    func testSameSourceWithinWindowGroups() {
        let events = [
            event(action: "block", source: "203.0.113.66", timestamp: "14:00:00"),
            event(action: "block", source: "203.0.113.66", timestamp: "14:02:00"),
        ]
        let groups = IncidentGrouping.group(events)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.count, 2)
    }

    func testSameSourceOutsideWindowStaysSeparate() {
        let events = [
            event(action: "block", source: "203.0.113.66", timestamp: "14:00:00"),
            event(action: "block", source: "203.0.113.66", timestamp: "14:20:00"),
        ]
        let groups = IncidentGrouping.group(events)
        XCTAssertEqual(groups.count, 2)
        XCTAssertTrue(groups.allSatisfy { $0.count == 1 })
    }

    func testDifferentSourcesStaySeparate() {
        let events = [
            event(action: "block", source: "203.0.113.66", timestamp: "14:00:00"),
            event(action: "block", source: "203.0.113.200", timestamp: "14:00:30"),
        ]
        let groups = IncidentGrouping.group(events)
        XCTAssertEqual(groups.count, 2)
        XCTAssertTrue(groups.allSatisfy { $0.count == 1 })
    }

    func testNonFirewallEventsNeverGroup() {
        var first = LogLine(text: "authentication failed for admin", kind: .auth)
        first.timestamp = "2026-09-15 14:00:00"
        var second = LogLine(text: "authentication failed for admin", kind: .auth)
        second.timestamp = "2026-09-15 14:00:05"
        let events = IncidentTimeline.build([(.authentication, [first, second])])

        let groups = IncidentGrouping.group(events)
        // Auth lines carry no parsed source address at all, so even two
        // identical, adjacent failures never cluster — there is nothing
        // here to key a group on.
        XCTAssertEqual(groups.count, 2)
        XCTAssertTrue(groups.allSatisfy { $0.count == 1 && $0.groupKey == nil })
    }

    func testPassActionNeverGroups() {
        let events = [
            event(action: "pass", source: "203.0.113.66", timestamp: "14:00:00"),
            event(action: "pass", source: "203.0.113.66", timestamp: "14:00:05"),
        ]
        let groups = IncidentGrouping.group(events)
        // Both are .information severity (a plain pass), so neither is
        // eligible to group even though they share a source seconds apart.
        XCTAssertEqual(groups.count, 2)
        XCTAssertTrue(groups.allSatisfy { $0.count == 1 })
    }

    func testOngoingReflectsRecencyOfLastEvent() {
        let recentEvents = [
            event(action: "block", source: "203.0.113.66", timestamp: "14:00:00"),
            event(action: "block", source: "203.0.113.66", timestamp: "14:02:00"),
        ]
        let now = IncidentAnalysis.date(from: "2026-09-15 14:03:00")!
        let recentGroups = IncidentGrouping.group(recentEvents, now: now)
        XCTAssertEqual(recentGroups.first?.isOngoing, true)

        let settledNow = IncidentAnalysis.date(from: "2026-09-15 15:00:00")!
        let settledGroups = IncidentGrouping.group(recentEvents, now: settledNow)
        XCTAssertEqual(settledGroups.first?.isOngoing, false)
    }

    func testSingleEventIsAGroupOfOneWithNoKey() {
        let events = [event(action: "block", source: "203.0.113.66", timestamp: "14:00:00")]
        let groups = IncidentGrouping.group(events)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.count, 1)
        XCTAssertNil(groups.first?.groupKey)
    }
}
