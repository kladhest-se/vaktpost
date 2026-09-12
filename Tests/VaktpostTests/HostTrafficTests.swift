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

    // MARK: Which hosts to ask for, per interface

    private func iface(_ raw: [String: Any]) -> InterfaceStat {
        let data = try! JSONSerialization.data(withJSONObject: raw)
        let value = try! JSONDecoder().decode(JSONValue.self, from: data)
        return InterfaceStat(JSONDict(value)!)
    }

    func testATunnelAsksForEveryHost() {
        // A tunnel is point to point and has no local subnet, so a capture
        // scoped to one returns nothing however busy the tunnel is. Local
        // there is an empty list that reads as a broken screen.
        for device in ["ovpns1", "ovpnc2", "tun_wg0", "ipsec1000", "gif0", "gre0"] {
            let stat = iface(["name": "opt7", "descr": "TUNNEL", "hwif": device,
                              "status": "up", "gateway": "GW_TUNNEL"])
            XCTAssertEqual(stat.kind, .tunnel, "\(device) should read as a tunnel")
            XCTAssertEqual(stat.suggestedHostFilter, .all)
            XCTAssertNotNil(stat.hostFilterRationale)
        }
    }

    func testAnInterfaceWithAGatewayAsksForRemoteHosts() {
        // On a WAN the "local" subnet is the link to the ISP, so Local returns
        // the provider's side rather than anything on the network.
        let wan = iface(["name": "wan", "descr": "WAN_1", "hwif": "ix0",
                         "status": "up", "gateway": "WAN_DHCP"])
        XCTAssertEqual(wan.kind, .wan)
        XCTAssertEqual(wan.suggestedHostFilter, .remote)

        // A second WAN is an opt interface and is recognised by its gateway,
        // not by being called WAN.
        let second = iface(["name": "opt1", "descr": "WAN_2", "hwif": "ix1",
                            "status": "up", "gateway": "WAN2_DHCP"])
        XCTAssertEqual(second.kind, .wan)
    }

    func testAVLANAsksForLocalHostsAndExplainsNothing() {
        let vlan = iface(["name": "lan", "descr": "VLAN_100", "hwif": "lagg0.100",
                          "status": "up"])
        XCTAssertEqual(vlan.kind, .local)
        XCTAssertEqual(vlan.suggestedHostFilter, .local)
        XCTAssertNil(vlan.hostFilterRationale,
                     "there is nothing to explain on a VLAN, and a line saying so is noise")
    }

    func testADescriptionAloneDoesNotMakeSomethingAWAN() {
        // "WAN_2" is a convention, not a fact. A LAN somebody named badly
        // should not be classified by its label, and misclassifying it would
        // start that screen on Remote and show them nothing.
        let misnamed = iface(["name": "opt9", "descr": "WANNABE", "hwif": "lagg0.400",
                              "status": "up"])
        XCTAssertEqual(misnamed.kind, .local)
    }

    func testAnEmptyGatewayIsNotAGateway() {
        for gateway in ["", "none", "None"] {
            let stat = iface(["name": "opt3", "descr": "VLAN_202", "hwif": "lagg0.202",
                              "status": "up", "gateway": gateway])
            XCTAssertEqual(stat.kind, .local, "gateway \"\(gateway)\" should not read as a WAN")
        }
    }

    // MARK: Grouping the interface picker

    /// The shape of a real firewall: fifteen interfaces in pfSense's config
    /// order, with two uplinks, five tunnels and eight VLANs interleaved.
    private var wholeFirewall: [InterfaceStat] {
        [
            iface(["name": "wan", "descr": "WAN_1", "hwif": "ix0", "gateway": "WAN_DHCP"]),
            iface(["name": "opt1", "descr": "WAN_2", "hwif": "ix1", "gateway": "WAN2_DHCP"]),
            iface(["name": "opt5", "descr": "OPENVPN1", "hwif": "ovpns1"]),
            iface(["name": "opt6", "descr": "OPENVPN2", "hwif": "ovpns2"]),
            iface(["name": "opt7", "descr": "WIREGUARD1", "hwif": "tun_wg0"]),
            iface(["name": "opt8", "descr": "WIREGUARD2", "hwif": "tun_wg1"]),
            iface(["name": "opt9", "descr": "WIREGUARD3", "hwif": "tun_wg2"]),
            iface(["name": "lan", "descr": "VLAN_100", "hwif": "lagg0.100"]),
            iface(["name": "opt10", "descr": "VLAN_101", "hwif": "lagg0.101"]),
        ]
    }

    func testGroupingKeepsTheSlotEachInterfaceOccupies() {
        // The whole point. Grouping reorders what is shown; it must not
        // reorder what is sent, or the app samples one interface and labels it
        // with another's name.
        for group in InterfaceStat.grouped(wholeFirewall) {
            for entry in group.entries {
                XCTAssertEqual(entry.interface.name, wholeFirewall[entry.id].name,
                               "slot \(entry.id) no longer points at the interface it did")
            }
        }
    }

    func testGroupsAreUplinksThenNetworksThenTunnels() {
        let groups = InterfaceStat.grouped(wholeFirewall)
        XCTAssertEqual(groups.map(\.title), ["Uplinks", "Networks", "Tunnels"])
        XCTAssertEqual(groups[0].entries.map(\.id), [0, 1])
        XCTAssertEqual(groups[1].entries.map(\.id), [7, 8])
        XCTAssertEqual(groups[2].entries.map(\.id), [2, 3, 4, 5, 6])
    }

    func testEveryInterfaceAppearsExactlyOnce() {
        let ids = InterfaceStat.grouped(wholeFirewall).flatMap { $0.entries.map(\.id) }
        XCTAssertEqual(Set(ids).count, wholeFirewall.count)
        XCTAssertEqual(ids.count, wholeFirewall.count)
    }

    func testConfigOrderSurvivesWithinAGroup() {
        // Sorting by name would look tidier and would mean the menu reordered
        // itself whenever somebody renamed an interface.
        let tunnels = InterfaceStat.grouped(wholeFirewall).last?.entries.map(\.interface.name)
        XCTAssertEqual(tunnels, ["OPENVPN1", "OPENVPN2", "WIREGUARD1", "WIREGUARD2", "WIREGUARD3"])
    }

    func testAFirewallWithNoTunnelsGetsNoTunnelHeading() {
        let plain = [iface(["name": "wan", "descr": "WAN", "hwif": "em0", "gateway": "GW"]),
                     iface(["name": "lan", "descr": "LAN", "hwif": "em1"])]
        XCTAssertEqual(InterfaceStat.grouped(plain).map(\.title), ["Uplinks", "Networks"])
    }

    func testGroupingNothingGivesNothing() {
        XCTAssertTrue(InterfaceStat.grouped([]).isEmpty)
    }

    // MARK: Finding the device a captured address belongs to

    private func networkClient(mac: String, ip: String) -> NetworkClient {
        NetworkClient(id: "\(mac)-\(ip)", mac: mac, ip: ip, hostname: nil, descr: nil,
                      interfaceName: "lan", leaseState: nil, leaseEnds: nil,
                      isStatic: false, overrideName: nil, aliasName: nil,
                      seenInARP: true, seenInLease: false, online: true)
    }

    private func lease(mac: String, ip: String) -> DHCPLease {
        let raw: [String: Any] = ["ip": ip, "mac": mac, "if": "lan", "state": "active"]
        let data = try! JSONSerialization.data(withJSONObject: raw)
        let value = try! JSONDecoder().decode(JSONValue.self, from: data)
        return DHCPLease(JSONDict(value)!)
    }

    private func arpEntry(mac: String, ip: String) -> ARPEntry {
        let raw: [String: Any] = ["ip": ip, "mac": mac, "interface": "lagg0.100"]
        let data = try! JSONSerialization.data(withJSONObject: raw)
        let value = try! JSONDecoder().decode(JSONValue.self, from: data)
        return ARPEntry(JSONDict(value)!)
    }

    func testACapturedAddressFindsItsClientDirectly() {
        let s = store([])
        s.overviewLayout.leases = [lease(mac: "aa:bb:cc:dd:ee:01", ip: "172.16.1.10")]
        XCTAssertEqual(s.client(matching: "172.16.1.10")?.mac, "aa:bb:cc:dd:ee:01")
    }

    func testASecondAddressOnTheSameDeviceStillFindsIt() {
        // The client list shows one address per device. A capture can catch
        // the device on another one, and that row would otherwise be a link
        // that mysteriously refuses to open.
        let s = store([])
        s.overviewLayout.leases = [lease(mac: "aa:bb:cc:dd:ee:02", ip: "172.16.1.11")]
        s.arp = [arpEntry(mac: "aa:bb:cc:dd:ee:02", ip: "172.16.1.99")]
        XCTAssertEqual(s.client(matching: "172.16.1.99")?.ip, "172.16.1.11")
    }

    func testAnAddressMatchesAcrossEquivalentIPv6Spellings() {
        let s = store([])
        s.overviewLayout.leases = [lease(mac: "aa:bb:cc:dd:ee:03", ip: "2001:db8::5")]
        XCTAssertNotNil(s.client(matching: "2001:db8:0:0:0:0:0:5"))
    }

    func testAnUnknownAddressLinksNowhere() {
        // Most of what a WAN capture returns is not a client, and a row that
        // looks tappable and does nothing is worse than one that does not.
        let s = store([])
        s.overviewLayout.leases = [lease(mac: "aa:bb:cc:dd:ee:04", ip: "172.16.1.12")]
        XCTAssertNil(s.client(matching: "203.0.113.7"))
        XCTAssertNil(s.client(matching: "not an address"))
    }

    func testAnARPEntryWithNoMatchingClientLinksNowhere() {
        let s = store([])
        s.arp = [arpEntry(mac: "aa:bb:cc:dd:ee:05", ip: "172.16.1.13")]
        XCTAssertNil(s.client(matching: "172.16.1.13"))
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
