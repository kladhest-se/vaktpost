import XCTest
@testable import Vaktpost

final class ClientInvestigationTests: XCTestCase {
    private func dict(_ raw: [String: String]) -> JSONDict {
        let data = try! JSONSerialization.data(withJSONObject: raw)
        return JSONDict(try! JSONDecoder().decode(JSONValue.self, from: data))!
    }

    func testStructuredLogMatchesEndpointsOnly() {
        var line = LogLine(text: "192.168.1.1 appears in unrelated text", kind: .firewall)
        line.source = "192.168.1.10"
        line.destination = "10.0.0.1"
        let keys = Set(["192.168.1.1"].compactMap(ClientAddress.key))
        XCTAssertFalse(line.involves(addresses: keys))
        line.source = "192.168.1.1"
        XCTAssertTrue(line.involves(addresses: keys))
    }
    func testRawFilterLogMatchesParsedEndpoints() {
        let line = LogLine(text: "Sep 9 12:00:00 fw filterlog[123]: 1,0,,100,em0,match,pass,in,4,0x0,,64,1,0,none,6,tcp,60,192.168.1.1,8.8.8.8,1234,443,0,S", kind: .firewall)
        XCTAssertTrue(line.involves(addresses: Set(["192.168.1.1"].compactMap(ClientAddress.key))))
        XCTAssertFalse(line.involves(addresses: Set(["192.168.1.10"].compactMap(ClientAddress.key))))
    }
    func testInvestigationKeepsAllMACAddresses() {
        let first = ARPEntry(dict(["ip": "10.0.0.1", "mac": "aa:bb:cc:dd:ee:ff"]))
        let second = ARPEntry(dict(["ip": "10.0.0.2", "mac": "aa:bb:cc:dd:ee:ff"]))
        let other = ARPEntry(dict(["ip": "10.0.0.3", "mac": "11:22:33:44:55:66"]))
        let client = NetworkClient.merge(leases: [], arp: [first], statics: [])[0]
        let result = ClientInvestigation(client: client, leases: [], arp: [first, second, other], mappings: [], overrides: [], aliases: [])
        XCTAssertEqual(result.addresses, ["10.0.0.1", "10.0.0.2"])
        XCTAssertEqual(result.neighbors.count, 2)
    }
}
