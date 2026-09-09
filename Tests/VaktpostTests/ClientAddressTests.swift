import XCTest
@testable import Vaktpost

final class ClientAddressTests: XCTestCase {
    func testSimilarIPv4AddressesStayDistinct() {
        XCTAssertNotEqual(ClientAddress.key("192.168.1.1"), ClientAddress.key("192.168.1.10"))
    }
    func testIPv6Canonicalization() {
        XCTAssertEqual(ClientAddress.key("2001:db8::1"), ClientAddress.key("2001:0DB8:0:0:0:0:0:1"))
        XCTAssertNotNil(ClientAddress.key("2001:db8::1"))
    }
    func testRejectsMissingAndNonAddresses() {
        for value in ["", "—", "example.com", "192.168.1.999", "192.168.1.1/24"] {
            XCTAssertNil(ClientAddress.key(value))
        }
    }
    func testMACMatchesAcrossAddressesAndSeparators() {
        XCTAssertTrue(ClientAddress.belongs(mac: "AA-BB-CC-DD-EE-FF", ip: "10.0.0.2", toMAC: "aa:bb:cc:dd:ee:ff", primaryIP: "10.0.0.1"))
    }
    func testDifferentMACDoesNotInheritReusedIP() {
        XCTAssertFalse(ClientAddress.belongs(mac: "11:22:33:44:55:66", ip: "10.0.0.1", toMAC: "aa:bb:cc:dd:ee:ff", primaryIP: "10.0.0.1"))
    }
    func testMissingMACFallsBackToExactValidIP() {
        XCTAssertTrue(ClientAddress.belongs(mac: "—", ip: "10.0.0.1", toMAC: "—", primaryIP: "10.0.0.1"))
        XCTAssertFalse(ClientAddress.belongs(mac: "—", ip: "—", toMAC: "—", primaryIP: "—"))
    }
}
