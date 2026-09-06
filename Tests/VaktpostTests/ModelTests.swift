import XCTest
@testable import Vaktpost

/// Health is what the coloured rail on every card is derived from, so a wrong
/// mapping is a firewall that looks fine when it is not.
final class ModelTests: XCTestCase {

    private func dict(_ raw: [String: Any]) -> JSONDict {
        let data = try! JSONSerialization.data(withJSONObject: raw)
        let value = try! JSONDecoder().decode(JSONValue.self, from: data)
        return JSONDict(value)!
    }

    // MARK: Gateways

    func testOnlineGatewayIsHealthy() {
        let gw = GatewayStatus(dict(["name": "WAN_DHCP", "status": "online",
                                     "delay": "8.4", "loss": "0"]))
        XCTAssertEqual(gw.health, .ok)
    }

    func testOnlineGatewayWithSubstatusWarns() {
        // pfSense reports a lossy-but-up gateway as online with a substatus,
        // which is exactly the case a naive status check misses.
        let gw = GatewayStatus(dict(["name": "VPN", "status": "online",
                                     "substatus": "highloss", "loss": "6"]))
        XCTAssertEqual(gw.health, .warn)
    }

    func testHighLossWarnsWithoutASubstatus() {
        let gw = GatewayStatus(dict(["name": "VPN", "status": "online", "loss": 12]))
        XCTAssertEqual(gw.health, .warn)
    }

    func testDownGatewayIsBad() {
        XCTAssertEqual(GatewayStatus(dict(["name": "WAN", "status": "down"])).health, .bad)
    }

    func testPendingGatewayIsIdleNotBad() {
        XCTAssertEqual(GatewayStatus(dict(["name": "WAN", "status": "pending"])).health, .idle)
    }

    // MARK: Interfaces

    func testInterfaceAddressLineCombinesAddressAndPrefix() {
        let iface = InterfaceStat(dict([
            "name": "LAN", "hwif": "em1", "status": "up",
            "ipaddr": "192.168.1.1", "subnet": "24",
        ]))
        XCTAssertEqual(iface.addressLine, "192.168.1.1/24")
        XCTAssertTrue(iface.isUp)
        XCTAssertEqual(iface.health, .ok)
    }

    func testInterfaceWithoutAnAddressSaysSo() {
        let iface = InterfaceStat(dict(["name": "OPT1", "hwif": "em2", "status": "no carrier"]))
        XCTAssertEqual(iface.addressLine, "no address")
        XCTAssertEqual(iface.health, .warn)
    }

    // MARK: Filter addresses

    func testFilterAddressReadsTheObjectForm() {
        // v2 returns these as objects; earlier versions returned strings.
        let d = dict(["destination": ["network": "192.168.1.0/24"], "destination_port": "443"])
        XCTAssertEqual(FilterAddress(d.value("destination"), port: d.value("destination_port")).text,
                       "192.168.1.0/24:443")
    }

    func testFilterAddressReadsTheStringForm() {
        let d = dict(["source": "any"])
        XCTAssertEqual(FilterAddress(d.value("source")).text, "any")
    }

    func testFilterAddressDefaultsToAny() {
        XCTAssertEqual(FilterAddress(nil).text, "any")
        XCTAssertEqual(FilterAddress(dict(["source": ["any": true]]).value("source")).text, "any")
    }

    // MARK: Certificates

    func testCertificateExpiryDrivesSeverity() {
        func cert(inDays days: Int) -> CertificateInfo {
            let when = Date().addingTimeInterval(Double(days) * 86_400).timeIntervalSince1970
            return CertificateInfo(dict(["descr": "webConfigurator", "valid_until": when]))
        }
        XCTAssertEqual(cert(inDays: 200).health, .ok)
        XCTAssertEqual(cert(inDays: 20).health, .warn)
        XCTAssertEqual(cert(inDays: 5).health, .bad)
        XCTAssertEqual(cert(inDays: -1).health, .bad)
    }

    func testCertificateWithNoDateIsIdleNotAlarming() {
        let cert = CertificateInfo(dict(["descr": "internal CA"]), isCA: true)
        XCTAssertNil(cert.daysRemaining)
        XCTAssertEqual(cert.health, .idle)
    }

    // MARK: State table

    func testStateTableFractionIsNilWithoutAMaximum() {
        XCTAssertNil(StateTableSize(dict(["current_states": 4102])).fraction)
        XCTAssertEqual(
            StateTableSize(dict(["current_states": 50, "maximum_states": 100])).fraction ?? 0,
            0.5, accuracy: 0.001
        )
    }

    // MARK: Formatting

    func testByteFormatting() {
        XCTAssertEqual(Fmt.bytes(512), "512 B")
        XCTAssertEqual(Fmt.bytes(1536), "1.5 KiB")
    }

    func testUptimeFormatting() {
        XCTAssertEqual(Fmt.uptime(90), "1m")
        XCTAssertEqual(Fmt.uptime(3_660), "1h 1m")
        XCTAssertEqual(Fmt.uptime(90_000), "1d 1h 0m")
    }

    func testRateFormattingUsesDecimalUnits() {
        // Network rates are decimal, unlike the binary units used for volumes.
        XCTAssertEqual(Rate.bits(999), "999 bit/s")
        XCTAssertEqual(Rate.bits(1_000), "1.0 kbit/s")
        XCTAssertEqual(Rate.bits(18_400_000), "18.4 Mbit/s")
    }
}
