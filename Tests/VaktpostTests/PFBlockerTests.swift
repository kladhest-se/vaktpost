import XCTest
@testable import Vaktpost

/// The distinction this whole screen turns on is between a list that holds
/// nothing and a list that is not loaded. Both are zero on any screen that
/// prints a number, and only one of them means traffic is getting through.
final class PFBlockerTests: XCTestCase {

    private func status(_ raw: [String: Any]) -> PFBlockerStatus {
        let data = try! JSONSerialization.data(withJSONObject: raw)
        let value = try! JSONDecoder().decode(JSONValue.self, from: data)
        return PFBlockerStatus(JSONDict(value)!)
    }

    private func feed(_ name: String, entries: Int, type: String = "network",
                      source: String = "pf") -> [String: Any] {
        ["name": name, "descr": "\(name) feed", "type": type,
         "entries": entries, "source": entries < 0 ? "" : source]
    }

    // MARK: Loaded against not loaded

    func testAFeedWithNoPfTableIsNotLoadedRatherThanEmpty() {
        // The snippet sends -1 where pf has no table of that name. Reading it
        // as a count would report a list that is not blocking anything as a
        // list that matched nothing.
        let s = status(["installed": true, "feeds": [feed("pfB_Top_v4", entries: -1)]])
        XCTAssertNil(s.feeds[0].entries)
        XCTAssertEqual(s.unloadedFeeds.count, 1)
    }

    func testAFeedThatMatchedNothingIsLoadedAndEmpty() {
        let s = status(["installed": true, "feeds": [feed("pfB_Custom", entries: 0)]])
        XCTAssertEqual(s.feeds[0].entries, 0)
        XCTAssertTrue(s.unloadedFeeds.isEmpty, "a table with nothing in it is still a table")
    }

    func testUnloadedFeedsAreNotCountedTowardsWhatIsBlocked() {
        // "What is blocked" has to mean what pf holds. Counting an unloaded
        // alias as zero is harmless; counting it as anything else, or omitting
        // loaded-but-empty ones, would not be.
        let s = status(["installed": true, "feeds": [
            feed("pfB_Top_v4", entries: 12_000),
            feed("pfB_Africa_v4", entries: -1),
            feed("pfB_Custom", entries: 0),
        ]])
        XCTAssertEqual(s.blockedAddresses, 12_000)
        XCTAssertEqual(s.unloadedFeeds.map(\.name), ["pfB_Africa_v4"])
    }

    // MARK: Presentation

    func testFeedsAreOrderedByHowMuchTheyHold() {
        let s = status(["installed": true, "feeds": [
            feed("pfB_Small", entries: 10),
            feed("pfB_Large", entries: 90_000),
            feed("pfB_Unloaded", entries: -1),
        ]])
        XCTAssertEqual(s.feeds.map(\.name), ["pfB_Large", "pfB_Small", "pfB_Unloaded"])
    }

    func testThePrefixIsDroppedForDisplayButKeptForIdentity() {
        let s = status(["installed": true, "feeds": [feed("pfB_Top_v4", entries: 1)]])
        XCTAssertEqual(s.feeds[0].shortName, "Top_v4")
        XCTAssertEqual(s.feeds[0].id, "pfB_Top_v4", "identity is the alias pfSense knows")
    }

    func testAnAliasWithoutThePrefixKeepsItsWholeName() {
        let s = status(["installed": true, "feeds": [feed("something_else", entries: 1)]])
        XCTAssertEqual(s.feeds[0].shortName, "something_else")
    }

    // MARK: Capability and paths

    func testNoPfAccessorMeansNothingCanBeCounted() {
        // Distinct from the package being absent. The lists are configured;
        // this pfSense just will not say what pf holds for them.
        let s = status(["installed": true, "accessor": "",
                        "feeds": [feed("pfB_Top_v4", entries: -1)]])
        XCTAssertNil(s.accessor)
        XCTAssertEqual(s.blockedAddresses, 0)
        XCTAssertEqual(s.unloadedFeeds.count, 1)
    }

    func testOnlyPathsThatExistAreReported() {
        // The two builds of the package keep things in different places, so
        // the snippet probes rather than assumes and this carries the answer
        // through to the diagnostics line.
        let s = status(["installed": true,
                        "paths": ["pkg": true, "db": true, "dnsbl": false, "deny": false],
                        "feeds": []])
        XCTAssertEqual(s.foundPaths, ["db", "pkg"])
    }

    func testFlagsDefaultToOffRatherThanMissing() {
        let s = status(["installed": true, "feeds": []])
        XCTAssertFalse(s.enabled)
        XCTAssertFalse(s.dnsblEnabled)
        XCTAssertTrue(s.feeds.isEmpty)
        XCTAssertEqual(s.blockedAddresses, 0)
    }

    // MARK: Where a count came from

    func testACountFromTheTableFileIsStillACount() {
        // Neither pf accessor exists on pfSense Plus, which meant every list
        // read as "not loaded" on a firewall where every list was loaded. The
        // fallback is /var/db/aliastables, which is the file pf loads from.
        let s = status(["installed": true, "accessor": "", "feeds": [
            feed("pfB_PRI1_v4", entries: 48_000, type: "urltable", source: "file"),
        ]])
        XCTAssertNil(s.accessor)
        XCTAssertEqual(s.blockedAddresses, 48_000)
        XCTAssertEqual(s.feeds[0].source, .file)
        XCTAssertTrue(s.unloadedFeeds.isEmpty)
    }

    func testAPortAliasIsCountedFromTheConfiguration() {
        // A port alias has no pf table and no table file. Reporting it as "not
        // loaded" was describing a thing that never exists for that type.
        let s = status(["installed": true, "accessor": "", "feeds": [
            feed("pfB_DNSBL_Ports", entries: 2, type: "port", source: "config"),
        ]])
        XCTAssertEqual(s.feeds[0].source, .config)
        XCTAssertEqual(s.feeds[0].entries, 2)
    }

    func testAnUnanswerableCountKeepsItsSourceUnset() {
        let s = status(["installed": true, "feeds": [feed("pfB_Gone", entries: -1)]])
        XCTAssertNil(s.feeds[0].entries)
        XCTAssertEqual(s.feeds[0].source, .none)
    }

    func testPfIsPreferredOverTheFileWhenItIsAvailable() {
        let s = status(["installed": true, "accessor": "pfSense_get_pf_table", "feeds": [
            feed("pfB_Top_v4", entries: 100, type: "urltable", source: "pf"),
        ]])
        XCTAssertEqual(s.feeds[0].source, .pf, "the running firewall beats a file on disk")
    }

    // MARK: DNSBL settings live in their own package section

    func testDNSBLIsReadFromItsOwnSection() {
        // `pfb_dnsbl` was read from the main pfblockerng settings, where it
        // does not exist, so DNSBL always reported as off — on a firewall
        // whose dnsbl.log was being written to that minute. It lives under
        // `pfblockerngdnsblsettings`.
        let s = status(["installed": true, "enabled": true, "dnsbl": true,
                        "dnsbl_mode": "unbound", "feeds": []])
        XCTAssertTrue(s.dnsblEnabled)
        XCTAssertEqual(s.dnsblMode, "unbound")
    }

    func testAMissingDNSBLSectionReadsAsOffRatherThanUnknown() {
        let s = status(["installed": true, "enabled": true, "feeds": []])
        XCTAssertFalse(s.dnsblEnabled)
        XCTAssertNil(s.dnsblMode)
    }

    // MARK: DNSBL statistics

    private func dnsbl(_ raw: [String: Any]) -> DNSBLStats {
        let data = try! JSONSerialization.data(withJSONObject: raw)
        let value = try! JSONDecoder().decode(JSONValue.self, from: data)
        return DNSBLStats(JSONDict(value)!)
    }

    func testATruncatedReadIsReportedAsOne() {
        // A total that silently means "some of the log" is worse than no
        // total. The window is a megabyte and a busy DNSBL log is bigger.
        let s = dnsbl(["available": true, "events": 400, "bytes": 9_000_000,
                       "scanned": 1_048_576, "truncated": true])
        XCTAssertTrue(s.truncated)
        XCTAssertEqual(s.events, 400)
    }

    func testHourLabelsStayTextAndAreNotTurnedIntoDates() {
        // pfBlockerNG writes `M j H:i:s` with no year. Anything building a
        // Date from "Sep 3 01" would invent one, and would invent the wrong
        // one for a log spanning New Year.
        let s = dnsbl(["available": true, "hours": [
            ["label": "Sep 3 01", "count": 189],
            ["label": "Sep 3 02", "count": 105],
        ]])
        XCTAssertEqual(s.hours.map(\.label), ["Sep 3 01", "Sep 3 02"])
        XCTAssertEqual(s.hours.first?.shortLabel, "01", "the axis already knows the day")
    }

    func testHoursKeepLogOrderRatherThanBeingSorted() {
        // Sorting these by name puts "Sep 9" after "Sep 10". The log is
        // append-only, so its order is already chronological.
        let s = dnsbl(["available": true, "hours": [
            ["label": "Sep 9 23", "count": 4],
            ["label": "Sep 10 00", "count": 7],
        ]])
        XCTAssertEqual(s.hours.map(\.label), ["Sep 9 23", "Sep 10 00"])
    }

    func testTheBusiestHourIsTheHighestCountNotTheLast() {
        let s = dnsbl(["available": true, "hours": [
            ["label": "Sep 3 01", "count": 189],
            ["label": "Sep 3 08", "count": 13],
        ]])
        XCTAssertEqual(s.busiestHour?.label, "Sep 3 01")
    }

    func testAnEmptyLogIsUnavailableRatherThanZeroEvents() {
        // DNSBL enabled with an empty log and DNSBL never having run look the
        // same as a count of zero, and the screen says different things about
        // them.
        let s = dnsbl(["available": false, "events": 0, "bytes": 0])
        XCTAssertFalse(s.available)
    }

    func testUnparsedLinesAreCountedRatherThanGuessedAt() {
        let s = dnsbl(["available": true, "events": 100, "unparsed": 2])
        XCTAssertEqual(s.unparsed, 2)
    }

    func testCountsCarryTheirNamesAndTotals() {
        let s = dnsbl(["available": true, "domains": [
            ["name": "firebaselogging-pa.googleapis.com", "count": 107],
            ["name": "metrics.icloud.com", "count": 58],
        ], "clients": [["name": "172.16.1.10", "count": 165]]])
        XCTAssertEqual(s.domains.first?.name, "firebaselogging-pa.googleapis.com")
        XCTAssertEqual(s.domains.first?.count, 107)
        XCTAssertEqual(s.clients.first?.name, "172.16.1.10")
    }

    // MARK: The donut

    @MainActor
    private func donutSlices(_ rows: [(String, Int)], total: Int, limit: Int) -> [DonutChart.Slice] {
        let counts = rows.map { name, count -> DNSBLCount in
            let raw: [String: Any] = ["name": name, "count": count]
            let data = try! JSONSerialization.data(withJSONObject: raw)
            let value = try! JSONDecoder().decode(JSONValue.self, from: data)
            return DNSBLCount(JSONDict(value)!)
        }
        return DonutChart.slices(counts, total: total, limit: limit, theme: ThemeManager())
    }

    @MainActor
    func testTheRemainderIsWhatMakesThePercentagesTrue() {
        // The rows are a top-N and the total is every event. A donut built
        // only from the rows would describe the top six while looking like it
        // described the whole, which is the ordinary way a chart like this
        // ends up lying.
        let slices = donutSlices([("a", 50), ("b", 30)], total: 100, limit: 6)
        XCTAssertEqual(slices.count, 3)
        XCTAssertEqual(slices.last?.label, "Other")
        XCTAssertEqual(slices.last?.value, 20)
    }

    @MainActor
    func testNoRemainderSliceWhenTheRowsAccountForEverything() {
        let slices = donutSlices([("a", 60), ("b", 40)], total: 100, limit: 6)
        XCTAssertEqual(slices.count, 2)
        XCTAssertFalse(slices.contains { $0.label == "Other" })
    }

    @MainActor
    func testRowsPastTheLimitFoldIntoTheRemainder() {
        let slices = donutSlices([("a", 10), ("b", 9), ("c", 8), ("d", 7)],
                                 total: 34, limit: 2)
        XCTAssertEqual(slices.map(\.label), ["a", "b", "Other"])
        XCTAssertEqual(slices.last?.value, 15, "c and d, together")
    }

    @MainActor
    func testEverySliceGetsItsOwnColourUpToThePalette() {
        let rows = (0..<6).map { ("d\($0)", 10) }
        let slices = donutSlices(rows, total: 60, limit: 6)
        XCTAssertEqual(Set(slices.map(\.id)).count, slices.count, "ids must be unique for ForEach")
    }

    // MARK: Logs

    func testLogsCarryTheirSizeAndWhenTheyWereLastWritten() {
        // Described rather than read: a busy firewall's block log runs to
        // hundreds of megabytes, and the modification time answers the
        // question somebody actually has, which is whether it is running.
        let s = status(["installed": true, "feeds": [], "logs": [
            ["name": "dnsbl.log", "bytes": 4096, "updated": 1_772_000_000],
            ["name": "ip_block.log", "bytes": 0, "updated": 0],
        ]])
        XCTAssertEqual(s.logs.count, 2)
        XCTAssertNotNil(s.logs[0].updated)
        XCTAssertNil(s.logs[1].updated, "a zero timestamp is no timestamp")
    }
}
