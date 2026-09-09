import XCTest
@testable import Vaktpost

final class IncidentTimelineTests: XCTestCase {
    func testEventsSortNewestFirstAcrossSources() {
        var older = LogLine(text: "service started", kind: .system)
        older.timestamp = "2026-09-09 10:00:00"
        var newer = LogLine(text: "authentication failed", kind: .auth)
        newer.timestamp = "2026-09-09 11:00:00"

        let events = IncidentTimeline.build([(.system, [older]), (.authentication, [newer])])
        XCTAssertEqual(events.map(\.source), [.authentication, .system])
        XCTAssertEqual(events.first?.severity, .attention)
    }

    func testUnparseableEventsRemainVisible() {
        let line = LogLine(text: "unstructured message", kind: .system)
        let events = IncidentTimeline.build([(.system, [line])])
        XCTAssertEqual(events.count, 1)
        XCTAssertNil(events[0].date)
    }
}
