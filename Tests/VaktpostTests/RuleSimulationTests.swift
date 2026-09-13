import XCTest
@testable import Vaktpost

/// The engine this replaces produced a number with no meaning:
/// `max(matchedAddresses.count + matchedPorts.count, 1)` — addresses added to
/// ports, matched on source *or* destination, floored at one so it could never
/// say zero. It was shown next to a "risk level" derived from it, immediately
/// before a firewall write.
///
/// So the first three tests here are the three things that number could not do.
final class RuleSimulationTests: XCTestCase {

    private func rule(interface: String = "lan", type: String = "pass",
                      source: String = "any", destination: String = "any",
                      destinationPort: String? = nil, proto: String? = nil) -> FirewallRule {
        var destination: [String: JSONValue] = ["address": .string(destination)]
        if let destinationPort { destination["port"] = .string(destinationPort) }
        var raw: [String: JSONValue] = [
            "tracker": .string("1"),
            "interface": .string(interface),
            "type": .string(type),
            "descr": .string(""),
            "source": .object(["address": .string(source)]),
            "destination": .object(destination)
        ]
        if let proto { raw["protocol"] = .string(proto) }
        return FirewallRule(JSONDict(raw))
    }

    /// A logged packet, written the way pfSense writes one.
    ///
    /// Built from real syslog text rather than by setting fields, because
    /// `filterFields` is parsed from the line rather than stored — so a
    /// fixture that set the fields directly would be testing a struct the app
    /// never sees. The v4 offsets are the ones the parser documents: tracker
    /// at 3, interface 4, action 6, and the protocol name at 16 with the
    /// addresses and ports following it.
    private func packet(action: String = "pass", interface: String = "lan",
                        source: String = "10.0.0.5", destination: String = "1.1.1.1",
                        sourcePort: String = "51000", destinationPort: String = "443",
                        proto: String = "tcp") -> LogLine {
        let fields = [
            "5", "16777216", "0", "1700000000", interface, "match", action, "in", "4",
            "0x0", "", "64", "12345", "0", "DF", "6", proto,
            "60", source, destination, sourcePort, destinationPort,
            "0", "1", "2", "S", "0", "0", "0", "", "mss;nop;wscale"
        ]
        let text = "Jan  1 00:00:00 fw filterlog[12345]: " + fields.joined(separator: ",")
        return LogLine(text: text, kind: .firewall)
    }

    // MARK: The three things the old number could not do

    func testARuleMatchingNothingReportsZero() {
        // The old engine floored its count at one, so "this affects nothing"
        // was not a sentence it could say.
        let result = RuleSimulation.run(rule(destination: "203.0.113.9"),
                                        against: [packet()])
        XCTAssertEqual(result.matched, 0)
        XCTAssertTrue(result.matchesNothing)
    }

    func testDirectionMatters() {
        // The old engine matched an address appearing as source *or*
        // destination, so a rule from A to B counted every host that was A or
        // B without ever checking a packet went from one to the other.
        let backwards = rule(source: "1.1.1.1", destination: "10.0.0.5")
        XCTAssertEqual(RuleSimulation.run(backwards, against: [packet()]).matched, 0)

        let forwards = rule(source: "10.0.0.5", destination: "1.1.1.1")
        XCTAssertEqual(RuleSimulation.run(forwards, against: [packet()]).matched, 1)
    }

    func testTheCountIsOneUnit() {
        // Addresses and ports are not summable. Everything reported is a count
        // of log lines.
        let result = RuleSimulation.run(rule(destinationPort: "443", proto: "tcp"),
                                        against: [packet(), packet(), packet(destinationPort: "22")])
        XCTAssertEqual(result.matched, 2)
        XCTAssertEqual(result.considered, 3)
    }

    // MARK: Matching

    func testTrafficOnAnotherInterfaceIsNotMatched() {
        XCTAssertEqual(RuleSimulation.run(rule(interface: "wan"),
                                          against: [packet(interface: "lan")]).matched, 0)
    }

    func testAnyMatchesEverything() {
        XCTAssertEqual(RuleSimulation.run(rule(), against: [packet(), packet()]).matched, 2)
    }

    func testAnAbsentFieldIsTreatedAsAny() {
        // pfSense omits a port rather than writing an empty one, and the app
        // reads the absence as "". Treating those differently would make a
        // rule that matches everything appear to match nothing.
        XCTAssertEqual(RuleSimulation.run(rule(proto: nil), against: [packet()]).matched, 1)
    }

    func testASubnetIsNotExpanded() {
        // Literal matching, exactly as `RulePlacement` does. A /24 covering
        // the source really would match on the firewall, and claiming so here
        // would need address maths this does not do — so it says nothing, and
        // the screen says why.
        XCTAssertEqual(RuleSimulation.run(rule(source: "10.0.0.0/24"),
                                          against: [packet(source: "10.0.0.5")]).matched, 0)
    }

    // MARK: What happened to the traffic

    func testABlockRuleOverPassingTrafficIsReportedAsANewBlock() {
        // The actionable number, and the one the old engine could not produce.
        let result = RuleSimulation.run(rule(type: "block", source: "10.0.0.5"),
                                        against: [packet(action: "pass"), packet(action: "pass")])
        XCTAssertEqual(result.wouldNewlyBlock, 2)
        XCTAssertEqual(result.wouldNewlyPass, 0)
    }

    func testAPassRuleOverBlockedTrafficIsReportedAsANewPass() {
        let result = RuleSimulation.run(rule(type: "pass", source: "10.0.0.5"),
                                        against: [packet(action: "block")])
        XCTAssertEqual(result.wouldNewlyPass, 1)
    }

    func testRejectCountsAsBlocked() {
        let result = RuleSimulation.run(rule(source: "10.0.0.5"),
                                        against: [packet(action: "reject")])
        XCTAssertEqual(result.blockedAtTheTime, 1)
    }

    // MARK: Lines it cannot judge

    func testLinesWithoutFilterFieldsAreCountedSeparately() {
        // Not silently dropped: a log that mostly failed to parse and a log
        // with no matching traffic produce the same zero otherwise.
        // A line with no filterlog CSV at all — a kernel message, a truncated
        // write, anything the parser cannot read.
        let bare = LogLine(text: "Jan  1 00:00:00 fw kernel: arp moved", kind: .firewall)
        let result = RuleSimulation.run(rule(), against: [packet(), bare])
        XCTAssertEqual(result.considered, 1)
        XCTAssertEqual(result.unparsed, 1)
    }

    func testAnEmptyLogMatchesNothingAndConsidersNothing() {
        let result = RuleSimulation.run(rule(), against: [])
        XCTAssertEqual(result.matched, 0)
        XCTAssertEqual(result.considered, 0)
    }

    // MARK: Sources

    func testTheBusiestSourcesAreReportedInOrder() {
        let lines = [packet(source: "10.0.0.5"), packet(source: "10.0.0.5"),
                     packet(source: "10.0.0.9")]
        let result = RuleSimulation.run(rule(), against: lines)
        XCTAssertEqual(result.sources.first, "10.0.0.5")
        XCTAssertEqual(result.sources.count, 2)
    }

    // MARK: Sample freshness

    func testRecentSuccessfulSampleCanBeSimulated() {
        let now = Date(timeIntervalSince1970: 2_000)
        let fetchedAt = now.addingTimeInterval(-30)
        var freshness = SectionFreshness()
        freshness.lastSuccess = fetchedAt

        let status = RuleSimulation.sampleStatus(
            freshness: freshness, error: nil, now: now, refreshInterval: 30
        )
        XCTAssertEqual(status, .fresh(fetchedAt: fetchedAt))
        XCTAssertTrue(status.allowsSimulation)
    }

    func testRecentCachedSampleIsExplicitlyLabelledAfterFailure() {
        let now = Date(timeIntervalSince1970: 2_000)
        let fetchedAt = now.addingTimeInterval(-90)
        var freshness = SectionFreshness()
        freshness.lastSuccess = fetchedAt
        freshness.failure = "offline"

        let status = RuleSimulation.sampleStatus(
            freshness: freshness, error: "offline", now: now, refreshInterval: 30
        )
        XCTAssertEqual(status, .cached(fetchedAt: fetchedAt, error: "offline"))
        XCTAssertTrue(status.allowsSimulation)
    }

    func testOldCachedSampleCannotProduceAResult() {
        let now = Date(timeIntervalSince1970: 2_000)
        let fetchedAt = now.addingTimeInterval(-301)
        var freshness = SectionFreshness()
        freshness.lastSuccess = fetchedAt
        freshness.failure = "offline"

        let status = RuleSimulation.sampleStatus(
            freshness: freshness, error: "offline", now: now, refreshInterval: 30
        )
        XCTAssertEqual(status, .stale(fetchedAt: fetchedAt, error: "offline"))
        XCTAssertFalse(status.allowsSimulation)
    }

    func testNeverFetchedSampleIsUnavailable() {
        let status = RuleSimulation.sampleStatus(
            freshness: SectionFreshness(), error: "permission denied",
            now: Date(timeIntervalSince1970: 2_000), refreshInterval: 30
        )
        XCTAssertEqual(status, .unavailable(error: "permission denied"))
        XCTAssertFalse(status.allowsSimulation)
    }

    func testOldSuccessfulSampleIsStaleEvenWithoutAnError() {
        let now = Date(timeIntervalSince1970: 2_000)
        let fetchedAt = now.addingTimeInterval(-61)
        var freshness = SectionFreshness()
        freshness.lastSuccess = fetchedAt

        let status = RuleSimulation.sampleStatus(
            freshness: freshness, error: nil, now: now, refreshInterval: 30
        )
        XCTAssertEqual(status, .stale(fetchedAt: fetchedAt, error: nil))
        XCTAssertFalse(status.allowsSimulation)
    }
}
