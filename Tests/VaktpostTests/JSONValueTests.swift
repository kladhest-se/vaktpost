import XCTest
@testable import Vaktpost

/// The tolerant decoder is the load-bearing piece: every model reads through
/// it, and the REST API package changes field names and value types between
/// releases. If coercion breaks, screens go blank rather than throwing.
final class JSONValueTests: XCTestCase {

    private func decode(_ json: String) throws -> JSONDict {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        return try XCTUnwrap(JSONDict(value))
    }

    func testReadsNumbersWrittenAsStrings() throws {
        let d = try decode(#"{"delay": "8.4", "loss": 0}"#)
        XCTAssertEqual(d.double("delay"), 8.4)
        XCTAssertEqual(d.double("loss"), 0)
    }

    func testStripsUnitsFromNumericStrings() throws {
        // Several status endpoints return "12.5%" or "23ms" rather than a number.
        let d = try decode(#"{"cpu": "12.5%", "rtt": "23ms", "rate": "1.2 Mbps"}"#)
        XCTAssertEqual(d.double("cpu"), 12.5)
        XCTAssertEqual(d.double("rtt"), 23)
        XCTAssertEqual(d.double("rate"), 1.2)
    }

    func testCoercesFirewallBooleanSpellings() throws {
        let d = try decode(#"{"a": "up", "b": "down", "c": "enabled", "d": 1, "e": "maybe"}"#)
        XCTAssertEqual(d.bool("a"), true)
        XCTAssertEqual(d.bool("b"), false)
        XCTAssertEqual(d.bool("c"), true)
        XCTAssertEqual(d.bool("d"), true)
        XCTAssertNil(d.bool("e"))
    }

    func testFallsThroughCandidateKeysInOrder() throws {
        let d = try decode(#"{"description": "WAN uplink"}"#)
        XCTAssertEqual(d.string("descr", "description"), "WAN uplink")
        XCTAssertNil(d.string("descr"))
    }

    func testTreatsNullAsAbsent() throws {
        // A present-but-null field must not shadow the next candidate key,
        // or one renamed field with a null placeholder blanks the value.
        let d = try decode(#"{"descr": null, "description": "LAN"}"#)
        XCTAssertEqual(d.string("descr", "description"), "LAN")
    }

    func testSurvivesUnexpectedShapes() throws {
        // A field that becomes an object where a string was expected should
        // read as nil rather than crash the whole screen.
        let d = try decode(#"{"source": {"any": true}}"#)
        XCTAssertNil(d.string("source"))
        XCTAssertNotNil(d.dict("source"))
    }
}
