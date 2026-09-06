import XCTest
@testable import Vaktpost

/// The join that makes the Clients tab worth having. Getting it wrong shows
/// one device as two entries, which looks like a firewall problem rather than
/// an app problem.
final class ClientMergeTests: XCTestCase {

    private func lease(ip: String, mac: String, host: String? = nil,
                       state: String = "active", isStatic: Bool = false) -> DHCPLease {
        var json: [String: Any] = ["ip": ip, "mac": mac, "state": state, "static": isStatic]
        if let host { json["hostname"] = host }
        return DHCPLease(dict(json))
    }

    private func arp(ip: String, mac: String, iface: String = "em0") -> ARPEntry {
        ARPEntry(dict(["ip": ip, "mac": mac, "interface": iface]))
    }

    private func dict(_ raw: [String: Any]) -> JSONDict {
        let data = try! JSONSerialization.data(withJSONObject: raw)
        let value = try! JSONDecoder().decode(JSONValue.self, from: data)
        return JSONDict(value)!
    }

    func testOneDeviceInBothTablesBecomesOneClient() {
        let clients = NetworkClient.merge(
            leases: [lease(ip: "192.168.1.50", mac: "AA:BB:CC:DD:EE:FF", host: "printer")],
            arp: [arp(ip: "192.168.1.50", mac: "aa:bb:cc:dd:ee:ff")],
            statics: []
        )
        XCTAssertEqual(clients.count, 1)
        XCTAssertTrue(clients[0].seenInARP)
        XCTAssertTrue(clients[0].seenInLease)
        XCTAssertEqual(clients[0].name, "printer")
    }

    func testMatchIsCaseInsensitiveOnMAC() {
        // pfSense spells MACs in both cases depending on the endpoint.
        let clients = NetworkClient.merge(
            leases: [lease(ip: "10.0.0.2", mac: "00:11:22:33:44:55")],
            arp: [arp(ip: "10.0.0.2", mac: "00:11:22:33:44:55")],
            statics: []
        )
        XCTAssertEqual(clients.count, 1)
    }

    func testStaticMappingSuppliesTheName() {
        let mapping = StaticMapping(dict([
            "mac": "aa:bb:cc:dd:ee:ff", "ipaddr": "192.168.1.50", "descr": "Office printer",
        ]))
        let clients = NetworkClient.merge(
            leases: [lease(ip: "192.168.1.50", mac: "aa:bb:cc:dd:ee:ff", host: "BRW001122")],
            arp: [],
            statics: [mapping]
        )
        XCTAssertEqual(clients.count, 1)
        XCTAssertTrue(clients[0].isStatic)
        // The description a human wrote beats the hostname the device announced.
        XCTAssertEqual(clients[0].name, "Office printer")
    }

    func testEntriesWithoutAMACFallBackToIP() {
        let clients = NetworkClient.merge(
            leases: [],
            arp: [arp(ip: "192.168.1.99", mac: "")],
            statics: []
        )
        XCTAssertEqual(clients.count, 1)
        XCTAssertEqual(clients[0].id, "ip:192.168.1.99")
    }

    func testDifferentDevicesStaySeparate() {
        let clients = NetworkClient.merge(
            leases: [lease(ip: "10.0.0.2", mac: "00:11:22:33:44:55")],
            arp: [arp(ip: "10.0.0.3", mac: "66:77:88:99:aa:bb")],
            statics: []
        )
        XCTAssertEqual(clients.count, 2)
    }

    func testSeenDevicesSortAboveUnseenOnes() {
        let clients = NetworkClient.merge(
            leases: [lease(ip: "10.0.0.9", mac: "aa:aa:aa:aa:aa:aa", host: "aaa", state: "expired")],
            arp: [arp(ip: "10.0.0.8", mac: "bb:bb:bb:bb:bb:bb")],
            statics: []
        )
        XCTAssertEqual(clients.first?.ip, "10.0.0.8")
    }
}
