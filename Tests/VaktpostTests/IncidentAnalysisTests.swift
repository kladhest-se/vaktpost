import XCTest
@testable import Vaktpost

final class IncidentAnalysisTests: XCTestCase {
    func testBlockedAndFailedEventsNeedAttention() {
        XCTAssertEqual(IncidentAnalysis.severity(action: "block", text: "routine packet"), .attention)
        XCTAssertEqual(IncidentAnalysis.severity(action: nil, text: "authentication failed"), .attention)
    }

    func testWarningsRemainSeparateFromInformation() {
        XCTAssertEqual(IncidentAnalysis.severity(action: nil, text: "gateway timeout"), .warning)
        XCTAssertEqual(IncidentAnalysis.severity(action: "pass", text: "connection established"), .information)
    }

    func testTermsAreWholeWords() {
        XCTAssertEqual(IncidentAnalysis.severity(action: nil, text: "download complete"), .information)
    }

    func testParsesISOAndEpochMilliseconds() {
        let iso = IncidentAnalysis.date(from: "2026-09-09T08:12:30Z")
        let epoch = IncidentAnalysis.date(from: "1788941550000")
        XCTAssertEqual(iso?.timeIntervalSince1970, epoch?.timeIntervalSince1970)
    }

    func testSyslogDateUsesCurrentYear() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = ISO8601DateFormatter().date(from: "2026-09-09T12:00:00Z")!
        let parsed = IncidentAnalysis.date(from: "Sep 8 10:11:12", now: now, calendar: calendar)
        XCTAssertEqual(calendar.component(.year, from: parsed!), 2026)
        XCTAssertEqual(calendar.component(.day, from: parsed!), 8)
    }

    func testFutureSyslogDateRollsBackOneYear() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = ISO8601DateFormatter().date(from: "2026-01-01T12:00:00Z")!
        let parsed = IncidentAnalysis.date(from: "Dec 31 23:59:59", now: now, calendar: calendar)
        XCTAssertEqual(calendar.component(.year, from: parsed!), 2025)
    }
}
