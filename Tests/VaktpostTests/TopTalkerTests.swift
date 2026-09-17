import XCTest
@testable import Vaktpost

/// The record is built from captures taken while a screen is open, which means
/// two things have to be right: the aggregation, and the honesty about how
/// much of an hour it rests on. An hour summarised from three captures reads
/// identically to one summarised from three hundred unless the record keeps
/// enough to say which.
@MainActor
final class TopTalkerTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)

    private func recorder() -> TopTalkerRecorder {
        // A directory of its own, so a test never reads or writes the real
        // record and two tests never see each other's.
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("toptalkers-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return TopTalkerRecorder(directory: dir)
    }

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: 4,
                                           hour: hour, minute: minute))!
    }

    private func host(_ ip: String, in inBps: Double, out outBps: Double) -> HostTraffic {
        let raw: [String: Any] = ["ip": ip,
                                  "in_text": String(Int(inBps)),
                                  "out_text": String(Int(outBps))]
        let data = try! JSONSerialization.data(withJSONObject: raw)
        let value = try! JSONDecoder().decode(JSONValue.self, from: data)
        return HostTraffic(JSONDict(value)!, interface: "lan")
    }

    private func record(_ recorder: TopTalkerRecorder, _ hosts: [HostTraffic],
                        at when: Date, names: @escaping (String) -> String? = { _ in nil }) {
        recorder.record(hosts, serverID: "FW1", interface: "lan", interfaceName: "VLAN_100",
                        names: names, at: when, calendar: calendar, now: when)
    }

    // MARK: Aggregation

    func testCapturesInTheSameHourFoldTogether() {
        let r = recorder()
        record(r, [host("172.16.1.10", in: 100, out: 10)], at: at(2, 5))
        record(r, [host("172.16.1.10", in: 300, out: 30)], at: at(2, 55))

        let hours = r.history(serverID: "FW1", interface: "lan")
        XCTAssertEqual(hours.count, 1, "one hour, not one per capture")
        XCTAssertEqual(hours[0].samples, 2)
        XCTAssertEqual(hours[0].talkers.count, 1)
    }

    func testAdjacentHoursStaySeparate() {
        let r = recorder()
        record(r, [host("172.16.1.10", in: 100, out: 10)], at: at(2, 59))
        record(r, [host("172.16.1.10", in: 100, out: 10)], at: at(3, 1))
        XCTAssertEqual(r.history(serverID: "FW1", interface: "lan").count, 2)
    }

    func testPeakIsTheHighestSeenAndMeanIsAcrossCaptures() {
        let r = recorder()
        record(r, [host("172.16.1.10", in: 100, out: 0)], at: at(2, 5))
        record(r, [host("172.16.1.10", in: 300, out: 0)], at: at(2, 10))

        let talker = r.history(serverID: "FW1", interface: "lan")[0].talkers[0]
        XCTAssertEqual(talker.peakIn, 300)
        XCTAssertEqual(talker.meanIn, 200)
        XCTAssertEqual(talker.samples, 2)
    }

    func testAnAddressAbsentFromACaptureIsNotCountedAsZero() {
        // pfSense returns ten addresses and a different ten each time. A
        // device missing from one capture was not necessarily idle, so folding
        // in a zero would drag its mean down for being crowded out.
        let r = recorder()
        record(r, [host("172.16.1.10", in: 100, out: 0),
                   host("172.16.1.11", in: 100, out: 0)], at: at(2, 5))
        record(r, [host("172.16.1.10", in: 100, out: 0)], at: at(2, 10))

        let hour = r.history(serverID: "FW1", interface: "lan")[0]
        let quiet = hour.talkers.first { $0.address == "172.16.1.11" }
        XCTAssertEqual(quiet?.samples, 1, "one capture saw it, so it has one sample")
        XCTAssertEqual(quiet?.meanIn, 100)
    }

    func testTwoSpellingsOfOneAddressAreOneTalker() {
        let r = recorder()
        record(r, [host("2001:db8::1", in: 100, out: 0)], at: at(2, 5))
        record(r, [host("2001:db8:0:0:0:0:0:1", in: 100, out: 0)], at: at(2, 10))
        XCTAssertEqual(r.history(serverID: "FW1", interface: "lan")[0].talkers.count, 1)
    }

    func testOnlyTheBusiestAddressesAreKept() {
        // Without a bound, an hour on a busy VLAN accumulates every address
        // that was ever briefly in a top ten and the file grows without limit.
        let r = recorder()
        for index in 0..<40 {
            record(r, [host("172.16.1.\(index)", in: Double(index) * 10, out: 0)], at: at(2, 5))
        }
        let hour = r.history(serverID: "FW1", interface: "lan")[0]
        XCTAssertEqual(hour.talkers.count, TopTalkerRecorder.talkersPerHour)
        XCTAssertEqual(hour.busiest.first?.address, "172.16.1.39", "the loudest survives")
    }

    func testThirdCaptureOfTheSameAddressDoesNotTrap() {
        // The crash. Entries went into the dictionary under a normalised key
        // and were rebuilt from storage under the raw address, so every lookup
        // missed, every capture added a second entry for a host already there,
        // and the third hit `Dictionary(uniqueKeysWithValues:)` with two
        // entries of the same address. Six seconds at a two-second interval.
        let r = recorder()
        for minute in [5, 6, 7, 8] {
            record(r, [host("172.16.1.10", in: 100, out: 10)], at: at(2, minute))
        }
        let hour = r.history(serverID: "FW1", interface: "lan")[0]
        XCTAssertEqual(hour.talkers.count, 1, "one address is one talker")
        XCTAssertEqual(hour.talkers[0].samples, 4, "and it accumulated rather than restarting")
    }

    func testStatsActuallyAccumulateAcrossCaptures() {
        // The quieter half of the same bug: because every lookup missed, each
        // capture replaced the stat rather than folding into it, so every
        // talker read as a single sample however long the screen was open.
        let r = recorder()
        record(r, [host("172.16.1.10", in: 100, out: 0)], at: at(2, 5))
        record(r, [host("172.16.1.10", in: 500, out: 0)], at: at(2, 6))
        let talker = r.history(serverID: "FW1", interface: "lan")[0].talkers[0]
        XCTAssertEqual(talker.samples, 2)
        XCTAssertEqual(talker.peakIn, 500)
        XCTAssertEqual(talker.meanIn, 300)
    }

    func testADuplicateInAStoredFileIsMergedRatherThanFatal() {
        // A file written by the build that had the keying bug contains two
        // entries for one address. Loading it and recording once more must not
        // trap — a bad file should cost accuracy, not the app.
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("toptalkers-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let duplicated = TalkerHour(
            serverID: "FW1", interface: "lan", interfaceName: "VLAN_100",
            hour: at(2), firstSample: at(2, 5), lastSample: at(2, 6), samples: 2,
            talkers: [
                TalkerStat(address: "172.16.1.10", name: nil, peakIn: 100, peakOut: 0,
                           totalIn: 100, totalOut: 0, samples: 1),
                TalkerStat(address: "172.16.1.10", name: nil, peakIn: 300, peakOut: 0,
                           totalIn: 300, totalOut: 0, samples: 1),
            ])
        let key = "FW1|lan|\(at(2).timeIntervalSince1970)"
        let data = try! JSONEncoder().encode([key: duplicated])
        try! data.write(to: dir.appendingPathComponent("vaktpost-top-talkers.json"))

        let r = TopTalkerRecorder(directory: dir)
        r.record([host("172.16.1.10", in: 200, out: 0)], serverID: "FW1", interface: "lan",
                 interfaceName: "VLAN_100", names: { _ in nil }, at: at(2, 7), calendar: calendar, now: at(2, 7))

        let hour = r.history(serverID: "FW1", interface: "lan")[0]
        XCTAssertEqual(hour.talkers.count, 1, "the duplicate was merged, not kept or fatal")
        XCTAssertEqual(hour.talkers[0].peakIn, 300, "the merge keeps the higher peak")
        XCTAssertEqual(hour.talkers[0].samples, 3, "one from each stored entry, one from now")
    }

    // MARK: Coverage

    func testTheSpanOfTheCapturesIsKept() {
        // Three captures at 2:05 and three hundred across the hour produce the
        // same list and are not the same claim.
        let r = recorder()
        record(r, [host("172.16.1.10", in: 100, out: 0)], at: at(2, 5))
        record(r, [host("172.16.1.10", in: 100, out: 0)], at: at(2, 50))

        let hour = r.history(serverID: "FW1", interface: "lan")[0]
        XCTAssertEqual(hour.firstSample, at(2, 5))
        XCTAssertEqual(hour.lastSample, at(2, 50))
        XCTAssertEqual(hour.span, 45 * 60)
    }

    func testAnEmptyCaptureRecordsNothingAtAll() {
        // An interface with nothing on it should not create an hour that
        // claims coverage it does not have.
        let r = recorder()
        record(r, [], at: at(2, 5))
        XCTAssertTrue(r.isEmpty(serverID: "FW1"))
    }

    // MARK: Names

    func testTheNameIsCapturedAtRecordTime() {
        // Resolved later, a device that has since left the network loses its
        // name retroactively — at exactly the moment somebody is looking it up.
        let r = recorder()
        record(r, [host("172.16.1.10", in: 100, out: 0)], at: at(2, 5)) { _ in "nas001" }
        record(r, [host("172.16.1.10", in: 100, out: 0)], at: at(2, 10)) { _ in nil }

        XCTAssertEqual(r.history(serverID: "FW1", interface: "lan")[0].talkers[0].name, "nas001")
    }

    // MARK: Scope and housekeeping

    func testFirewallsAndInterfacesAreKeptApart() {
        let r = recorder()
        record(r, [host("172.16.1.10", in: 100, out: 0)], at: at(2, 5))
        r.record([host("10.0.0.1", in: 100, out: 0)], serverID: "FW2", interface: "lan",
                 interfaceName: "LAN", names: { _ in nil }, at: at(2, 5), calendar: calendar, now: at(2, 5))
        r.record([host("10.0.0.2", in: 100, out: 0)], serverID: "FW1", interface: "opt3",
                 interfaceName: "VLAN_202", names: { _ in nil }, at: at(2, 5), calendar: calendar, now: at(2, 5))

        XCTAssertEqual(r.history(serverID: "FW1", interface: "lan").count, 1)
        XCTAssertEqual(r.history(serverID: "FW2", interface: "lan").count, 1)
        XCTAssertEqual(r.recordedInterfaces(serverID: "FW1").map(\.interface).sorted(),
                       ["lan", "opt3"])
    }

    func testHoursOlderThanTheRetentionWindowAreDropped() {
        let r = recorder()
        record(r, [host("172.16.1.10", in: 100, out: 0)], at: at(2, 5))
        XCTAssertFalse(r.isEmpty(serverID: "FW1"))

        r.prune(now: at(2, 5).addingTimeInterval(TopTalkerRecorder.retention + 3_600))
        XCTAssertTrue(r.isEmpty(serverID: "FW1"))
    }

    func testHistoryIsNewestFirst() {
        let r = recorder()
        record(r, [host("172.16.1.10", in: 100, out: 0)], at: at(1, 5))
        record(r, [host("172.16.1.10", in: 100, out: 0)], at: at(5, 5))
        let hours = r.history(serverID: "FW1", interface: "lan")
        XCTAssertEqual(hours.map(\.hour), [at(5), at(1)])
    }

    func testClearingRemovesEverything() {
        let r = recorder()
        record(r, [host("172.16.1.10", in: 100, out: 0)], at: at(2, 5))
        r.clear()
        XCTAssertTrue(r.isEmpty(serverID: "FW1"))
    }

    func testTheRecordIsBoundedByCountAsWellAsAge() {
        // Retention alone is not a bound: seven days across fifteen
        // interfaces is thousands of hourly buckets, and the whole record is
        // re-encoded on every save. The ceiling that matters is the number of
        // entries, not their age.
        let r = recorder()
        let baseWhen = at(0)
        var count = 0
        let interfaces = ["lan", "opt1", "opt2", "opt3", "opt4", "opt5", "opt6", "opt7", "opt8", "opt9"]
        // Record 650 unique hourly buckets all within a 6-day retention window
        while count < TopTalkerRecorder.maxHours + 50 {
            for iface in interfaces {
                if count >= TopTalkerRecorder.maxHours + 50 { break }
                // Cycle through hours within a 6-day window (all within 7-day retention)
                let hourInDay = count % 144
                let when = baseWhen.addingTimeInterval(Double(hourInDay) * 3_600)
                r.record([host("172.16.1.10", in: 100, out: 0)], serverID: "FW1",
                         interface: iface, interfaceName: "VLAN_\(iface)",
                         names: { _ in nil }, at: when, calendar: calendar, now: when, skipPrune: true)
                count += 1
            }
        }
        let lastWhen = baseWhen.addingTimeInterval(143 * 3_600)
        r.prune(now: lastWhen)
        XCTAssertEqual(r.hours.filter { $0.value.serverID == "FW1" }.count,
                       TopTalkerRecorder.maxHours)
    }

    func testTheOldestHoursAreTheOnesDropped() {
        let r = recorder()
        for hour in 0..<(TopTalkerRecorder.maxHours + 10) {
            let when = at(0).addingTimeInterval(Double(hour) * 3_600)
            r.record([host("172.16.1.10", in: 100, out: 0)], serverID: "FW1",
                     interface: "lan", interfaceName: "VLAN_100",
                     names: { _ in nil }, at: when, calendar: calendar, now: when)
        }
        let kept = r.history(serverID: "FW1", interface: "lan")
        let newest = at(0).addingTimeInterval(Double(TopTalkerRecorder.maxHours + 9) * 3_600)
        XCTAssertEqual(kept.first?.hour, calendar.dateInterval(of: .hour, for: newest)?.start)
    }

    // MARK: Persistence

    func testTheRecordSurvivesARelaunch() async {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("toptalkers-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }

        let first = TopTalkerRecorder(directory: dir)
        first.record([host("172.16.1.10", in: 100, out: 0)], serverID: "FW1",
                     interface: "lan", interfaceName: "VLAN_100",
                     names: { _ in nil }, at: at(2, 5), calendar: calendar, now: at(2, 5))
        await first.saveSynchronously()

        let second = TopTalkerRecorder(directory: dir)
        XCTAssertEqual(second.history(serverID: "FW1", interface: "lan").count, 1)
    }

    func testAnUnreadableFileIsIgnoredRatherThanFatal() {
        // A file from an older shape of this type should cost a week of
        // history, not the ability to record anything until somebody deletes
        // it by hand.
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("toptalkers-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? Data("not json".utf8).write(to: dir.appendingPathComponent("vaktpost-top-talkers.json"))

        let r = TopTalkerRecorder(directory: dir)
        XCTAssertTrue(r.isEmpty(serverID: "FW1"))
        r.record([host("172.16.1.10", in: 100, out: 0)], serverID: "FW1",
                 interface: "lan", interfaceName: "VLAN_100",
                 names: { _ in nil }, at: at(2, 5), calendar: calendar, now: at(2, 5))
        XCTAssertFalse(r.isEmpty(serverID: "FW1"))
    }

    func testAnOlderSaveCannotOverwriteANewerSnapshot() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("toptalkers-writer-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("history.json")
        let writer = TopTalkerPersistenceWriter(store: file)

        let newer = TalkerHour(serverID: "FW1", interface: "lan", interfaceName: "LAN",
                               hour: at(3), firstSample: at(3), lastSample: at(3),
                               samples: 2, talkers: [])
        let older = TalkerHour(serverID: "FW1", interface: "lan", interfaceName: "LAN",
                               hour: at(2), firstSample: at(2), lastSample: at(2),
                               samples: 1, talkers: [])

        let newerOutcome = try await writer.save([newer.id: newer], generation: 2)
        let olderOutcome = try await writer.save([older.id: older], generation: 1)
        XCTAssertEqual(newerOutcome, .written)
        XCTAssertEqual(olderOutcome, .superseded)

        let data = try Data(contentsOf: file)
        let stored = try JSONDecoder().decode([String: TalkerHour].self, from: data)
        XCTAssertEqual(stored.values.first?.hour, newer.hour)
    }

    func testPersistenceFailureIsVisible() async throws {
        let file = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("toptalkers-blocked-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        try Data("not a directory".utf8).write(to: file)

        let recorder = TopTalkerRecorder(directory: file)
        record(recorder, [host("172.16.1.10", in: 100, out: 0)], at: at(2, 5))
        await recorder.saveSynchronously()

        XCTAssertNotNil(recorder.persistenceError)
    }

    func testSelectionFallsBackWhenTheNewFirewallLacksTheOldInterface() {
        XCTAssertEqual(
            TopTalkerSelection.resolve(preferred: "opt9", available: ["lan", "wan"]),
            "lan"
        )
        XCTAssertEqual(
            TopTalkerSelection.resolve(preferred: "wan", available: ["lan", "wan"]),
            "wan"
        )
    }
}
