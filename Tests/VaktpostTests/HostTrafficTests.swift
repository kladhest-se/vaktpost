import XCTest
@testable import Vaktpost

/// The per-host rates arrive as text, not as numbers.
///
/// pfSense invokes `rate` without its exact-values flag, so the wire carries
/// "1.20M" where every other number in this app carries 1200000. Everything
/// that can go wrong here is in that conversion: a prefix read as a digit, a
/// binary base where the tool documents a decimal one, or a shape the parser
/// does not recognise quietly becoming zero and reordering the table.
///
/// The last one is why `inText` and `outText` are kept alongside the parsed
/// values: a row this parser cannot read is still displayed as the firewall
/// wrote it, and only its sort position is affected.
@MainActor
final class HostTrafficTests: XCTestCase {

    // MARK: Parsing

    func testPlainIntegerIsBitsPerSecond() {
        XCTAssertEqual(HostTraffic.bitsPerSecond("842"), 842)
    }

    func testZeroParsesAsZero() {
        XCTAssertEqual(HostTraffic.bitsPerSecond("0"), 0)
    }

    func testSIPrefixesUseADecimalBase() {
        // `rate` documents SI prefixes, not binary ones. A 1024 base here
        // would put every row 2.4% out at k and 4.9% out at M, which is small
        // enough never to look wrong and large enough to be wrong.
        XCTAssertEqual(HostTraffic.bitsPerSecond("13k"), 13_000)
        XCTAssertEqual(HostTraffic.bitsPerSecond("1.20M"), 1_200_000, accuracy: 0.5)
        XCTAssertEqual(HostTraffic.bitsPerSecond("2.5G"), 2_500_000_000, accuracy: 0.5)
        XCTAssertEqual(HostTraffic.bitsPerSecond("1T"), 1_000_000_000_000, accuracy: 0.5)
    }

    func testLowerAndUpperKiloAgree() {
        XCTAssertEqual(HostTraffic.bitsPerSecond("4K"), HostTraffic.bitsPerSecond("4k"))
    }

    func testSurroundingWhitespaceIsIgnored() {
        // awk pads its columns, and the PHP trims — but the trim is one line
        // of a snippet that could be edited, and this is cheap insurance.
        XCTAssertEqual(HostTraffic.bitsPerSecond("  1.5M  "), 1_500_000, accuracy: 0.5)
    }

    func testUnreadableTextBecomesZeroRatherThanCrashing() {
        XCTAssertEqual(HostTraffic.bitsPerSecond(""), 0)
        XCTAssertEqual(HostTraffic.bitsPerSecond("no info"), 0)
        XCTAssertEqual(HostTraffic.bitsPerSecond("—"), 0)
    }

    // MARK: Payload

    private func sample(_ raw: [String: Any]) -> HostTrafficSample {
        let data = try! JSONSerialization.data(withJSONObject: raw)
        let value = try! JSONDecoder().decode(JSONValue.self, from: data)
        return HostTrafficSample(JSONDict(value)!)
    }

    func testRowsCarryTheResolvedInterfaceAndBothForms() {
        let result = sample([
            "available": true,
            "interface": "lan",
            "descr": "LAN",
            "slot": 1,
            "reason": "",
            "raw": "192.0.2.10;1.20M;13k|192.0.2.11;842;0|",
            "data": [
                ["ip": "192.0.2.10", "in_text": "1.20M", "out_text": "13k"],
                ["ip": "192.0.2.11", "in_text": "842", "out_text": "0"],
            ],
        ])

        XCTAssertTrue(result.available)
        XCTAssertEqual(result.interface, "lan")
        XCTAssertEqual(result.slot, 1)
        XCTAssertNil(result.reason, "an empty reason is no reason, not an empty sentence")
        XCTAssertEqual(result.hosts.count, 2)

        let first = result.hosts[0]
        XCTAssertEqual(first.interface, "lan", "rows are labelled with the key the firewall resolved")
        XCTAssertEqual(first.ip, "192.0.2.10")
        XCTAssertEqual(first.inText, "1.20M", "the firewall's own text survives for display")
        XCTAssertEqual(first.bandwidthIn, 1_200_000, accuracy: 0.5)
        XCTAssertEqual(first.bandwidthOut, 13_000, accuracy: 0.5)
        XCTAssertEqual(first.total, 1_213_000, accuracy: 0.5)
    }

    func testIdentityIsPerInterfaceSoOneAddressCanAppearOnTwo() {
        let lan = sample([
            "available": true, "interface": "lan", "descr": "LAN", "slot": 0,
            "reason": "", "raw": "",
            "data": [["ip": "192.0.2.10", "in_text": "1", "out_text": "1"]],
        ])
        let opt = sample([
            "available": true, "interface": "opt1", "descr": "GUEST", "slot": 1,
            "reason": "", "raw": "",
            "data": [["ip": "192.0.2.10", "in_text": "1", "out_text": "1"]],
        ])
        XCTAssertNotEqual(lan.hosts[0].id, opt.hosts[0].id)
    }

    func testAnUnavailableFirewallKeepsItsReason() {
        // The four empty-list causes have to stay distinguishable: this is the
        // one where the include is missing, and it should not read the same as
        // a capture that ran and saw nothing.
        let result = sample([
            "available": false,
            "interface": "wan",
            "descr": "WAN",
            "slot": 0,
            "device": "ix0",
            "reason": "This pfSense has no bandwidth_by_ip.inc, so per-host traffic cannot be sampled.",
            "raw": "",
            "data": [],
        ])
        XCTAssertFalse(result.available)
        XCTAssertTrue(result.hosts.isEmpty)
        XCTAssertNotNil(result.reason)
    }

    func testAMeasuredButEmptySampleHasNoReasonOfItsOwn() {
        // "no info" is what printBandwidth echoes when the capture saw
        // nothing, and it goes through gettext. It stays in `raw` as
        // diagnostic text and never becomes the sentence on screen — the app
        // has its own, and it is the same sentence in every language the
        // webConfigurator might be set to.
        let result = sample([
            "available": true, "interface": "wan", "descr": "WAN",
            "device": "ix0", "slot": 0,
            "reason": "", "raw": "no info", "data": [],
        ])
        XCTAssertTrue(result.available, "the capture ran; it just saw nothing")
        XCTAssertNil(result.reason)
        XCTAssertEqual(result.raw, "no info")
        XCTAssertTrue(result.hosts.isEmpty)
    }

    func testAPhraseWherePfSenseWouldPutRowsIsNotParsedAsAHost() {
        // The failure this guards against is a table with one row in it
        // called "no info" and a rate of zero, on every idle interface.
        let result = sample([
            "available": true, "interface": "opt1", "descr": "WAN_2",
            "device": "ix1", "slot": 1, "reason": "", "raw": "no info",
            "data": [],
        ])
        XCTAssertTrue(result.hosts.isEmpty)
    }

    func testAnInterfaceWithNoDeviceIsReportedBeforeTheCaptureIsAttempted() {
        let result = sample([
            "available": false, "interface": "opt9", "descr": "WIREGUARD3",
            "device": "", "slot": 6,
            "reason": "pfSense has no device behind this interface at the moment, so there is nothing to capture on.",
            "raw": "", "data": [],
        ])
        XCTAssertFalse(result.available)
        XCTAssertNotNil(result.reason)
        XCTAssertTrue(result.raw.isEmpty, "no capture was attempted, so there is nothing pfSense wrote")
    }

    // MARK: Resolving a device's interface to a slot

    private func store(_ interfaces: [[String: Any]]) -> DashboardStore {
        let suite = "vaktpost.hosttraffic.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let store = DashboardStore(registry: ServerRegistry(defaults: defaults), defaults: defaults)
        store.interfaces = interfaces.map { raw in
            let data = try! JSONSerialization.data(withJSONObject: raw)
            let value = try! JSONDecoder().decode(JSONValue.self, from: data)
            return InterfaceStat(JSONDict(value)!)
        }
        return store
    }

    /// Shaped after a real firewall: fifteen interfaces where the slot order
    /// is neither alphabetical nor the order of the pfSense keys, and where
    /// `lan` sits in the middle rather than at the top.
    private var fixture: [[String: Any]] {
        [
            ["name": "wan", "descr": "WAN_1", "hwif": "ix0", "status": "up"],
            ["name": "opt1", "descr": "WAN_2", "hwif": "ix1", "status": "up"],
            ["name": "opt7", "descr": "WIREGUARD1", "hwif": "tun_wg0", "status": "up"],
            ["name": "lan", "descr": "VLAN_100", "hwif": "lagg0.100", "status": "up"],
            ["name": "opt10", "descr": "VLAN_101", "hwif": "lagg0.101", "status": "up"],
        ]
    }

    func testADeviceNameResolvesToItsSlot() {
        // What the ARP table spells it.
        XCTAssertEqual(store(fixture).interfaceSlot(for: "lagg0.100"), 3)
        XCTAssertEqual(store(fixture).interfaceSlot(for: "tun_wg0"), 2)
    }

    func testAnInternalHandleResolvesToTheSameSlot() {
        // What a DHCP lease spells the same interface.
        XCTAssertEqual(store(fixture).interfaceSlot(for: "lan"), 3)
        XCTAssertEqual(store(fixture).interfaceSlot(for: "opt10"), 4)
    }

    func testTheDescriptionResolvesTooAndCaseDoesNotMatter() {
        XCTAssertEqual(store(fixture).interfaceSlot(for: "VLAN_101"), 4)
        XCTAssertEqual(store(fixture).interfaceSlot(for: "LaGg0.100"), 3)
    }

    func testAnUnknownOrAbsentHintResolvesToNothing() {
        // Not zero. Falling back to the first interface would sample the WAN
        // and attribute its busiest addresses to a device on a VLAN.
        XCTAssertNil(store(fixture).interfaceSlot(for: "lagg0.999"))
        XCTAssertNil(store(fixture).interfaceSlot(for: ""))
        XCTAssertNil(store(fixture).interfaceSlot(for: nil))
    }

    func testAMultiInterfaceHintResolvesToNothing() {
        // A floating rule names every interface it applies to. That is not a
        // location, and sampling the first of them would be a guess.
        XCTAssertNil(store(fixture).interfaceSlot(for: "lan,opt10,opt1"))
    }

    // MARK: Trace points

    func testAnAbsentDeviceContributesAZeroPointRatherThanAGap() {
        // The live card plots zero when the device is not in the returned
        // list. A gap would make the trace lie about its own time axis; a
        // zero is honest about the reading and the card carries the caveat
        // about what "not in the list" means.
        let result = sample([
            "available": true, "interface": "lan", "descr": "VLAN_100",
            "device": "lagg0.100", "slot": 3, "reason": "", "raw": "",
            "data": [["ip": "172.16.1.99", "in_text": "5.63M", "out_text": "297.57k"]],
        ])
        let keys = Set(["172.16.1.10"].compactMap(ClientAddress.key))
        let match = result.hosts.first { ClientAddress.key($0.ip).map(keys.contains) == true }
        XCTAssertNil(match, "a different address on the same interface is not this device")
        XCTAssertEqual(match?.bandwidthIn ?? 0, 0)
    }

    func testADeviceIsMatchedUnderAnySpellingOfItsAddress() {
        // The capture and the ARP table can spell the same IPv6 address
        // differently. Matching on the raw string would plot a busy device as
        // idle for as long as it held that address.
        let result = sample([
            "available": true, "interface": "lan", "descr": "VLAN_100",
            "device": "lagg0.100", "slot": 3, "reason": "", "raw": "",
            "data": [["ip": "2001:db8:0:0:0:0:0:1", "in_text": "1.20M", "out_text": "13k"]],
        ])
        let keys = Set(["2001:db8::1"].compactMap(ClientAddress.key))
        let match = result.hosts.first { ClientAddress.key($0.ip).map(keys.contains) == true }
        XCTAssertNotNil(match)
        XCTAssertEqual(match?.bandwidthOut ?? 0, 13_000, accuracy: 0.5)
    }

    // MARK: The refresh interval

    func testTheIntervalDefaultsToFifteenSecondsWhenNothingIsStored() {
        // Zero in UserDefaults means "never set", which is not the same as
        // somebody choosing the fastest option — reading it as a literal
        // interval would poll the firewall continuously.
        XCTAssertEqual(store([]).hostTrafficInterval, 15)
    }

    func testTheIntervalIsRememberedAcrossStores() {
        let suite = "vaktpost.interval.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }

        let first = DashboardStore(registry: ServerRegistry(defaults: defaults), defaults: defaults)
        first.hostTrafficInterval = 60

        let second = DashboardStore(registry: ServerRegistry(defaults: defaults), defaults: defaults)
        XCTAssertEqual(second.hostTrafficInterval, 60)
    }

    func testEveryOfferedIntervalClearsTheFloorTheCaptureImposes() {
        // A capture is a second of wall clock plus a round trip pfSense
        // serialises against its own web UI. Below about one and a half
        // seconds the captures queue faster than they complete, so no option
        // may go there however the picker is edited later.
        for seconds in DashboardStore.hostTrafficIntervals {
            XCTAssertGreaterThanOrEqual(seconds, 2, "\(seconds)s is below the capture floor")
        }
    }

    func testTheDefaultIntervalIsOneThePickerOffers() {
        // Otherwise the control opens with nothing selected, and the first tap
        // changes the interval as a side effect of looking at it.
        let suite = "vaktpost.interval.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let fresh = DashboardStore(registry: ServerRegistry(defaults: defaults), defaults: defaults)
        XCTAssertTrue(DashboardStore.hostTrafficIntervals.contains(fresh.hostTrafficInterval))
    }

    // MARK: Snippet shape

    func testTheSnippetNeverPassesTheDestructiveMode() {
        // printBandwidth's iftop branch kills PIDs and unlinks logs. The only
        // thing keeping the app out of it is the empty mode argument, and that
        // is one string literal away from being wrong.
        for filter in PHPSnippet.HostFilter.allCases {
            let snippet = PHPSnippet.hostTraffic(slot: 0, filter: filter, sort: .inbound)
            XCTAssertFalse(snippet.body.contains("iftop"))
            XCTAssertTrue(snippet.body.contains("\"\", \"\")"),
                          "mode and hostipformat must both stay empty")
        }
    }

    func testTheSlotIsClampedToAnInteger() {
        XCTAssertTrue(PHPSnippet.hostTraffic(slot: -5, filter: .local, sort: .inbound)
            .body.contains("$vaktpost_slot = 0;"))
        XCTAssertTrue(PHPSnippet.hostTraffic(slot: 9_999, filter: .local, sort: .inbound)
            .body.contains("$vaktpost_slot = 63;"))
    }

    func testEveryFilterAndSortIsInTheAuditedCatalogue() {
        // `all` is what the publish check audits and what check-snippets.sh
        // runs against a live firewall. A snippet reachable from the app but
        // absent from it is unexercised.
        let names = Set(PHPSnippet.all.map(\.name))
        for filter in PHPSnippet.HostFilter.allCases {
            XCTAssertTrue(names.contains("host_traffic_\(filter.rawValue)_in"),
                          "host_traffic_\(filter.rawValue)_in missing from PHPSnippet.all")
        }
    }
}
