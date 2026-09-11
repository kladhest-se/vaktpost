import XCTest
@testable import Vaktpost

/// Most of these test that nothing is reported.
///
/// The cost of a missed conflict is that somebody debugs by hand, which is
/// where they were before this screen existed. The cost of a false one is that
/// somebody hunts a problem that does not exist, which is worse than having
/// said nothing — so the cases that must not fire outnumber the ones that must.
final class ConflictDetectorTests: XCTestCase {

    private func decode<T>(_ raw: [String: Any], _ make: (JSONDict) -> T) -> T {
        let data = try! JSONSerialization.data(withJSONObject: raw)
        let value = try! JSONDecoder().decode(JSONValue.self, from: data)
        return make(JSONDict(value)!)
    }

    private func arp(_ ip: String, _ mac: String) -> ARPEntry {
        decode(["ip": ip, "mac": mac, "interface": "lagg0.100"], ARPEntry.init)
    }

    private func lease(_ ip: String, _ mac: String, state: String = "active",
                       hostname: String? = nil) -> DHCPLease {
        var raw: [String: Any] = ["ip": ip, "mac": mac, "state": state]
        if let hostname { raw["hostname"] = hostname }
        return decode(raw, DHCPLease.init)
    }

    private func mapping(_ ip: String, _ mac: String, hostname: String? = nil) -> StaticMapping {
        var raw: [String: Any] = ["ipaddr": ip, "mac": mac]
        if let hostname { raw["hostname"] = hostname }
        return decode(raw, StaticMapping.init)
    }

    private func override(_ host: String, _ domain: String, _ ip: String) -> HostOverride {
        decode(["host": host, "domain": domain, "ip": ip], HostOverride.init)
    }

    private func find(arp a: [ARPEntry] = [], leases l: [DHCPLease] = [],
                      mappings m: [StaticMapping] = [],
                      overrides o: [HostOverride] = []) -> [ConflictDetector.Conflict] {
        ConflictDetector.find(arp: a, leases: l, staticMappings: m, hostOverrides: o)
    }

    // MARK: Things that must not be reported

    func testOneDeviceWithSeveralAddressesIsNotAConflict() {
        // Perfectly ordinary — a host with a v4 and a v6, or an interface
        // alias. Reporting it would fire on most networks immediately.
        let found = find(arp: [arp("172.16.1.10", "aa:bb:cc:dd:ee:01"),
                               arp("172.16.1.11", "aa:bb:cc:dd:ee:01")])
        XCTAssertTrue(found.isEmpty)
    }

    func testTheSameMACInDifferentCaseIsTheSameDevice() {
        // pfSense is not consistent about case across tables, and comparing
        // them raw reports a device as being in conflict with itself.
        let found = find(arp: [arp("172.16.1.10", "AC:10:01:01:02:03")],
                         leases: [lease("172.16.1.10", "ac:10:01:01:02:03")])
        XCTAssertTrue(found.isEmpty)
    }

    func testAnExpiredLeaseNamingAnotherDeviceIsNotAConflict() {
        // The address was handed on. That is the system working, and flagging
        // it would fill the screen with history.
        let found = find(arp: [arp("172.16.1.10", "aa:bb:cc:dd:ee:01")],
                         leases: [lease("172.16.1.10", "aa:bb:cc:dd:ee:99", state: "expired")])
        XCTAssertTrue(found.isEmpty)
    }

    func testAStaticMappingMatchingItsOwnStaticLeaseIsNotAConflict() {
        let found = find(leases: [lease("172.16.1.32", "aa:bb:cc:dd:ee:02", state: "static")],
                         mappings: [mapping("172.16.1.32", "aa:bb:cc:dd:ee:02")])
        XCTAssertTrue(found.isEmpty)
    }

    func testAnEmptyMACIsNeverASide() {
        // Some tables carry blank MACs. Two blanks are not two devices.
        let found = find(arp: [arp("172.16.1.10", ""), arp("172.16.1.10", "")])
        XCTAssertTrue(found.isEmpty)
    }

    func testAMissingMACIsNotADevice() {
        // `DHCPLease` substitutes an em dash for an absent MAC, so two leases
        // with none would read as two devices holding one address — a conflict
        // invented out of two absences.
        let found = find(arp: [arp("172.16.1.10", "aa:bb:cc:dd:ee:01")],
                         leases: [decode(["ip": "172.16.1.10", "state": "active"], DHCPLease.init)])
        XCTAssertTrue(found.isEmpty)
    }

    func testEquivalentIPv6SpellingsAreOneAddress() {
        let found = find(arp: [arp("2001:db8::1", "aa:bb:cc:dd:ee:01"),
                               arp("2001:db8:0:0:0:0:0:1", "aa:bb:cc:dd:ee:01")])
        XCTAssertTrue(found.isEmpty)
    }

    // MARK: Things that must be reported

    func testTwoMACsOnOneAddress() {
        let found = find(arp: [arp("172.16.1.10", "aa:bb:cc:dd:ee:01"),
                               arp("172.16.1.10", "aa:bb:cc:dd:ee:02")])
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].kind, .addressClaimedTwice)
        XCTAssertEqual(found[0].sides.count, 2)
        XCTAssertEqual(found[0].kind.severity, .bad)
    }

    func testARPDisagreeingWithAnActiveLease() {
        // A device with a hardcoded address sitting on top of a live lease.
        let found = find(arp: [arp("172.16.1.10", "aa:bb:cc:dd:ee:01")],
                         leases: [lease("172.16.1.10", "aa:bb:cc:dd:ee:02")])
        XCTAssertEqual(found.first?.kind, .arpDisagreesWithLease)
    }

    func testTwoStaticMappingsForOneAddress() {
        let found = find(mappings: [mapping("172.16.1.32", "aa:bb:cc:dd:ee:01"),
                                    mapping("172.16.1.32", "aa:bb:cc:dd:ee:02")])
        XCTAssertEqual(found.first?.kind, .duplicateStaticAddress)
    }

    func testOneDeviceWithTwoStaticMappings() {
        let found = find(mappings: [mapping("172.16.1.32", "aa:bb:cc:dd:ee:01"),
                                    mapping("172.16.1.33", "aa:bb:cc:dd:ee:01")])
        XCTAssertEqual(found.first?.kind, .duplicateStaticMAC)
    }

    func testAReservedAddressCurrentlyLeasedToSomeoneElse() {
        let found = find(leases: [lease("172.16.1.32", "aa:bb:cc:dd:ee:99")],
                         mappings: [mapping("172.16.1.32", "aa:bb:cc:dd:ee:01")])
        XCTAssertTrue(found.contains { $0.kind == .staticAddressLeasedElsewhere })
    }

    func testOneNameResolvingToTwoAddresses() {
        // `example.se`, not a real domain. The publish gate greps the whole
        // tree for the internal one and refuses the push, which is how this
        // line was caught — a fixture is as public as the source around it.
        let found = find(overrides: [override("nas", "example.se", "172.16.1.32"),
                                     override("nas", "example.se", "172.16.1.33")])
        XCTAssertEqual(found.first?.kind, .overrideNameCollision)
        XCTAssertEqual(found.first?.subject, "nas.example.se")
    }

    func testTwoDevicesAnsweringToOneName() {
        let found = find(leases: [lease("172.16.1.10", "aa:bb:cc:dd:ee:01", hostname: "laptop"),
                                  lease("172.16.1.11", "aa:bb:cc:dd:ee:02", hostname: "laptop")])
        XCTAssertEqual(found.first?.kind, .duplicateHostname)
        XCTAssertEqual(found.first?.kind.severity, .idle,
                       "untidy and often deliberate — not an incident")
    }

    func testOneDeviceThatMovedAddressIsNotTwoDevicesWithOneName() {
        // Compared by MAC, not address. A laptop that changed subnet still has
        // one name and is one machine.
        let found = find(leases: [lease("172.16.1.10", "aa:bb:cc:dd:ee:01", hostname: "laptop"),
                                  lease("172.16.2.10", "aa:bb:cc:dd:ee:01", hostname: "laptop")])
        XCTAssertTrue(found.isEmpty)
    }

    // MARK: Ordering and identity

    func testTheOnesThatBreakTrafficComeFirst() {
        let found = find(arp: [arp("172.16.1.10", "aa:bb:cc:dd:ee:01"),
                               arp("172.16.1.10", "aa:bb:cc:dd:ee:02")],
                         leases: [lease("172.16.1.50", "aa:bb:cc:dd:ee:03", hostname: "dup"),
                                  lease("172.16.1.51", "aa:bb:cc:dd:ee:04", hostname: "dup")])
        XCTAssertEqual(found.first?.kind, .addressClaimedTwice)
        XCTAssertEqual(found.last?.kind, .duplicateHostname)
    }

    func testConflictsHaveUniqueIdentifiers() {
        let found = find(arp: [arp("172.16.1.10", "aa:bb:cc:dd:ee:01"),
                               arp("172.16.1.10", "aa:bb:cc:dd:ee:02"),
                               arp("172.16.1.11", "aa:bb:cc:dd:ee:03"),
                               arp("172.16.1.11", "aa:bb:cc:dd:ee:04")],
                         mappings: [mapping("172.16.1.32", "aa:bb:cc:dd:ee:05"),
                                    mapping("172.16.1.32", "aa:bb:cc:dd:ee:06")])
        XCTAssertEqual(Set(found.map(\.id)).count, found.count)
    }

    func testAnEmptyNetworkHasNoConflicts() {
        XCTAssertTrue(find().isEmpty)
    }
}
