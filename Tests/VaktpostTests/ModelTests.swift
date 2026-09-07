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

    func testTemperatureFallsBackToConvertingFahrenheit() {
        // Which of the two fields is populated depends on the sensor driver.
        let f = SystemStatus(dict(["temp_c": NSNull(), "temp_f": 122.0]))
        XCTAssertEqual(f.temperature ?? 0, 50, accuracy: 0.01)
        XCTAssertTrue(f.hasTemperature)

        let c = SystemStatus(dict(["temp_c": 41.5, "temp_f": 106.7]))
        XCTAssertEqual(c.temperature ?? 0, 41.5, accuracy: 0.01)
    }

    func testNoSensorIsNilRatherThanZeroDegrees() {
        // Null must not read as 0 °C, which would look alarming and be wrong.
        let none = SystemStatus(dict(["temp_c": NSNull(), "temp_f": NSNull()]))
        XCTAssertNil(none.temperature)
        XCTAssertFalse(none.hasTemperature)
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

/// Regressions from running against a live firewall, where a screen full of
/// good data sat under a red "Cannot reach firewall" banner.
final class ErrorClassificationTests: XCTestCase {

    private func dict(_ raw: [String: Any]) -> JSONDict {
        let data = try! JSONSerialization.data(withJSONObject: raw)
        let value = try! JSONDecoder().decode(JSONValue.self, from: data)
        return JSONDict(value)!
    }

    func testCancellationIsItsOwnErrorNotATLSFailure() {
        // Cancellation happens constantly and normally: backgrounding, a
        // firewall switch, a refresh superseding the one in flight. Reporting
        // it as "TLS handshake failed" told people to go and change their
        // certificate settings for a request that was working fine.
        XCTAssertNotEqual(RPCError.cancelled, RPCError.tls)
        XCTAssertEqual(RPCError.cancelled.errorDescription, "Cancelled.")
    }

    func testStandaloneFirewallIsNotReportedAsHavingCARP() {
        // The endpoint answers on every firewall, so "did it respond" is not
        // the same question as "does this box do HA".
        let standalone = CARPStatus(dict(["enable": false, "maintenance_mode": false]))
        XCTAssertFalse(standalone.isConfigured)
    }

    func testEnabledCARPIsConfigured() {
        XCTAssertTrue(CARPStatus(dict(["enable": true])).isConfigured)
    }

    func testCARPWithVirtualIPsIsConfiguredEvenIfTheFlagIsOff() {
        // Maintenance mode and a demoted node both leave VIPs present.
        let withVIPs = CARPStatus(dict([
            "enable": false,
            "interfaces": [["interface": "lan", "vhid": "1", "status": "backup"]],
        ]))
        XCTAssertTrue(withVIPs.isConfigured)
    }

    func testFilterAddressAnyWithPort() {
        let d = dict(["source": ["any": true], "source_port": "443"])
        XCTAssertEqual(FilterAddress(d.value("source"), port: d.value("source_port")).text, "any:443")
    }

    func testIsRetryableOnlyAppliesToTransportErrors() {
        XCTAssertTrue(RPCError.transport("DNS timeout").isRetryable)
        XCTAssertFalse(RPCError.unauthorized.isRetryable)
        XCTAssertFalse(RPCError.forbidden.isRetryable)
        XCTAssertFalse(RPCError.tls.isRetryable)
        XCTAssertFalse(RPCError.malformed.isRetryable)
        XCTAssertFalse(RPCError.fault(1, "undefined function").isRetryable)
        XCTAssertFalse(RPCError.noCredentials.isRetryable)
        XCTAssertFalse(RPCError.cancelled.isRetryable)
    }
}

/// Acknowledgement identity, which has to survive the numbers changing.
final class AlertSignatureTests: XCTestCase {

    private func alert(_ title: String, _ severity: Health,
                       _ category: VaktpostAlert.Category) -> VaktpostAlert {
        VaktpostAlert(severity: severity, category: category, title: title, detail: "")
    }

    func testTheSameConditionADegreeHotterKeepsItsSignature() {
        // Otherwise acknowledging "Chipset at 81 °C" would need doing again at
        // 82, which is worse than not offering acknowledgement at all.
        let a = alert("Chipset at 81 °C", .warn, .capacity)
        let b = alert("Chipset at 83 °C", .warn, .capacity)
        XCTAssertEqual(a.signature, b.signature)
    }

    func testGettingWorseBreaksTheAcknowledgement() {
        // Something you decided to live with at a warning is not something you
        // decided to live with when it turns critical.
        let warned = alert("Chipset at 96 °C", .warn, .capacity)
        let critical = alert("Chipset at 106 °C", .bad, .capacity)
        XCTAssertNotEqual(warned.signature, critical.signature)
    }

    func testADigitInsideANameIsPartOfTheName() {
        // The bug this caught: stripping every digit made these one condition,
        // so acknowledging one gateway silenced the other.
        XCTAssertNotEqual(alert("WAN_DHCP is down", .bad, .gateway).signature,
                          alert("WAN2_DHCP is down", .bad, .gateway).signature)
        XCTAssertNotEqual(alert("openvpn1 has no clients", .warn, .vpn).signature,
                          alert("openvpn2 has no clients", .warn, .vpn).signature)
    }

    func testAMeasurementIsDropped() {
        // A word that is only a number is a reading, not a name.
        XCTAssertEqual(alert("3 packages have updates", .warn, .update).signature,
                       alert("4 packages have updates", .warn, .update).signature)
        XCTAssertEqual(alert("State table 45% full", .warn, .capacity).signature,
                       alert("State table 61% full", .warn, .capacity).signature)
    }

    func testTwoFilesystemsStayApart() {
        XCTAssertNotEqual(alert("/var at 91%", .warn, .capacity).signature,
                          alert("/tmp at 91%", .warn, .capacity).signature)
    }

    func testTheSameTitleInTwoCategoriesStaysDistinct() {
        XCTAssertNotEqual(alert("Something", .warn, .capacity).signature,
                          alert("Something", .warn, .vpn).signature)
    }
}

extension AlertSignatureTests {

    func testABareNumberIdentifierNeedsAKey() {
        // "CARP VHID 1 backup" and "CARP VHID 2 backup" differ only by a digit
        // the signature drops as a measurement, so the alert supplies a key.
        let one = VaktpostAlert(severity: .bad, category: .ha,
                                title: "CARP VHID 1 backup", detail: "", key: "vhid-1")
        let two = VaktpostAlert(severity: .bad, category: .ha,
                                title: "CARP VHID 2 backup", detail: "", key: "vhid-2")
        XCTAssertNotEqual(one.signature, two.signature)
    }

    func testTheSameVirtualIPStillMatchesItself() {
        let backup = VaktpostAlert(severity: .bad, category: .ha,
                                   title: "CARP VHID 1 backup", detail: "", key: "vhid-1")
        let same = VaktpostAlert(severity: .bad, category: .ha,
                                 title: "CARP VHID 1 backup", detail: "", key: "vhid-1")
        XCTAssertEqual(backup.signature, same.signature)
    }
}
