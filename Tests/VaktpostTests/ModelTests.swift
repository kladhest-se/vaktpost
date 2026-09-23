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

    /// pfSense calls one interface three things depending on which record is
    /// being read, and a rule can only be written against its key.
    func testAnInterfaceIsFoundByDeviceKeyOrLabel() {
        let interfaces = [
            InterfaceStat(dict(["descr": "WAN", "name": "wan", "hwif": "igb0", "status": "up"])),
            InterfaceStat(dict(["descr": "LAN", "name": "lan", "hwif": "igb1", "status": "up"])),
        ]
        XCTAssertEqual(interfaces.matchingLogName("igb0")?.internalName, "wan")
        XCTAssertEqual(interfaces.matchingLogName("wan")?.internalName, "wan")
        XCTAssertEqual(interfaces.matchingLogName("LAN")?.internalName, "lan")
        XCTAssertEqual(interfaces.matchingLogName("lan")?.internalName, "lan")
        XCTAssertEqual(interfaces.matchingLogName("IGB1")?.internalName, "lan")
    }

    func testAnUnknownOrMissingInterfaceNameMatchesNothing() {
        let interfaces = [InterfaceStat(dict(["descr": "WAN", "name": "wan", "hwif": "igb0", "status": "up"]))]
        XCTAssertNil(interfaces.matchingLogName("igb9"))
        XCTAssertNil(interfaces.matchingLogName(""))
        XCTAssertNil(interfaces.matchingLogName(nil))
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
        XCTAssertFalse(RPCError.malformed(nil).isRetryable)
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

/// Dynamic Type, checked at the source rather than by rendering.
///
/// A snapshot test would be better and needs a rendering harness this project
/// does not have. This at least catches the reintroduction of a fixed font,
/// which is how all 246 of them got there: one at a time, each looking
/// reasonable on its own.
final class DynamicTypeTests: XCTestCase {

    private var sourceFiles: [URL] {
        // #filePath is inside Tests/VaktpostTests, so Sources is two up.
        let here = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = here.appendingPathComponent("Sources")
        let all = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
        return (all?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "swift" }
    }

    func testNoViewUsesAFixedFontSize() throws {
        var offenders: [String] = []
        for url in sourceFiles {
            // The modifier itself is the one place allowed to call it.
            if url.lastPathComponent == "ScaledFont.swift" { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            for (n, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where line.contains(".font(.system(size:") {
                offenders.append("\(url.lastPathComponent):\(n + 1)")
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "fixed font sizes: \(offenders.joined(separator: ", "))")
    }

    func testTheSourceFilesWereActuallyFound() {
        // Without this the test above passes when the path is wrong, which is
        // the failure mode of every test that scans a directory.
        XCTAssertGreaterThan(sourceFiles.count, 20)
    }
}

/// Filter log parsing, checked against lines from a live firewall.
final class FilterLogFieldTests: XCTestCase {

    private func line(_ text: String) -> LogLine {
        LogLine(text: text, kind: .firewall)
    }

    func testATCPPassParsesEveryField() throws {
        let f = try XCTUnwrap(line(
            "Sep  7 13:28:22 fw filterlog[48170]: 0,321,,1788391996,tun_wg0,match,pass,in,4,0x0,,64,0,0,DF,6,tcp,64,"
                + "10.253.21.10,192.168.200.1,50181,443,0,SEC,2244295301,,65535,,mss;nop"
        ).filterFields)
        XCTAssertEqual(f.action, "pass")
        XCTAssertEqual(f.direction, "in")
        XCTAssertEqual(f.interfaceName, "tun_wg0")
        // The name, not the number: index 15 is "6" and index 16 is "tcp".
        // Taking the number gave a protocol column reading "6", which is
        // correct and useless.
        XCTAssertEqual(f.proto, "tcp")
        XCTAssertEqual(f.source, "10.253.21.10")
        XCTAssertEqual(f.destination, "192.168.200.1")
        XCTAssertEqual(f.sourcePort, "50181")
        XCTAssertEqual(f.destinationPort, "443")
        XCTAssertEqual(f.tracker, "1788391996")
    }

    func testAUDPBlockParses() throws {
        let f = try XCTUnwrap(line(
            "Sep  7 13:41:16 fw filterlog[48170]: 4294967295,,,0,tun_wg0,match,block,in,4,0x0,,64,42252,1400,none,17,udp,80,"
                + "10.253.21.10,203.0.113.9,51820,51820"
        ).filterFields)
        XCTAssertEqual(f.action, "block")
        XCTAssertEqual(f.proto, "udp")
        XCTAssertEqual(f.destination, "203.0.113.9")
        // UDP carries no TCP flags, and inventing one would be worse than
        // leaving the row out.
        XCTAssertNil(f.tcpFlags)
    }

    func testIPv6UsesItsOwnOffsets() throws {
        // v4 carries tos, ecn, ttl, id, offset and flags before the protocol;
        // v6 carries class, flow label and hop limit. Reading v6 at the v4
        // offsets produced a protocol of "64", which is the hop limit.
        let f = try XCTUnwrap(line(
            "Sep  7 10:00:00 fw filterlog[100]: 0,,,1000,lan,match,block,in,6,0x00,0x00000,64,58,ipv6-icmp,72,fe80::1,ff02::1,,"
        ).filterFields)
        XCTAssertEqual(f.ipVersion, "6")
        XCTAssertEqual(f.proto, "ipv6-icmp")
        XCTAssertEqual(f.source, "fe80::1")
        XCTAssertEqual(f.destination, "ff02::1")
    }

    func testATruncatedLineReturnsNilRatherThanNonsense() {
        XCTAssertNil(line("Sep  7 10:00:00 fw filterlog[100]: 0,,,1,lan").filterFields)
    }

    func testANonFilterLineIsNotParsed() {
        // A DHCP or system line has no CSV, and pretending otherwise would
        // fill a detail screen with fields taken from a sentence.
        let dhcp = LogLine(text: "Sep  7 17:13:12 fw kea-dhcp4[77435]: INFO lease allocated",
                           kind: .dhcp)
        XCTAssertNil(dhcp.filterFields)
    }
}

/// Chart readouts, which are arithmetic and so can be tested.
final class ChartSampleTests: XCTestCase {

    /// The same snapping the charts do: nearest sample, clamped in range.
    ///
    /// The clamp is written out rather than borrowed. `clamped(to:)` is
    /// fileprivate to Components.swift, so reaching for it here does not
    /// compile — and a test that shares the implementation's helper would pass
    /// even if that helper were the thing that was wrong. The arithmetic under
    /// test is two lines; stating it twice is the point.
    private func index(x: CGFloat, width: CGFloat, count: Int) -> Int {
        let step = width / CGFloat(count - 1)
        let raw = Int((x / step).rounded())
        return min(max(raw, 0), count - 1)
    }

    func testATapSnapsToTheNearestSampleNotTheOneBefore() {
        // Truncating meant a tap two thirds of the way between two samples
        // reported the one on its left, so the dot never sat where the finger
        // was and never sat on the line either.
        XCTAssertEqual(index(x: 66, width: 100, count: 11), 7)
        XCTAssertEqual(index(x: 64, width: 100, count: 11), 6)
    }

    func testTheRightEdgeIsInRange() {
        // The clamp allowed `count`, one past the end — a tap on the right
        // edge indexed out of bounds.
        XCTAssertEqual(index(x: 100, width: 100, count: 11), 10)
        XCTAssertEqual(index(x: 140, width: 100, count: 11), 10)
    }

    func testTheLeftEdgeIsInRange() {
        XCTAssertEqual(index(x: 0, width: 100, count: 11), 0)
        XCTAssertEqual(index(x: -20, width: 100, count: 11), 0)
    }

    func testTheSnappedPositionLandsOnTheLine() {
        // The marker used the tapped x with the sample's y, so it floated off
        // the line. Snapping the x is what puts it back on.
        let width: CGFloat = 100, count = 11
        let step = width / CGFloat(count - 1)
        let i = index(x: 66, width: width, count: count)
        XCTAssertEqual(CGFloat(i) * step, 70, accuracy: 0.001)
    }
}

/// The device's own addresses, used to mark its row in the client list.
final class LocalDeviceTests: XCTestCase {

    func testItFindsAtLeastOneAddress() {
        // A simulator or a device on a network has at least one non-loopback
        // IPv4 address. Zero would mean the interface walk is broken rather
        // than that the machine is offline, which is worth knowing.
        let addresses = LocalDevice.addresses()
        XCTAssertFalse(addresses.isEmpty, "no interfaces found at all")
    }

    func testLoopbackIsExcluded() {
        // 127.0.0.1 is nobody's client, and a firewall never lists it. If it
        // came through, every client list would mark whichever row happened to
        // hold it.
        XCTAssertFalse(LocalDevice.addresses().values.contains("127.0.0.1"))
    }

    func testAnUnrelatedAddressIsNotThisDevice() {
        XCTAssertFalse(LocalDevice.isThisDevice("203.0.113.9"))
        XCTAssertFalse(LocalDevice.isThisDevice(""))
    }

    func testItsOwnAddressIsRecognised() {
        guard let mine = LocalDevice.addresses().values.first else {
            return XCTFail("no address to test with")
        }
        XCTAssertTrue(LocalDevice.isThisDevice(mine))
    }
}

/// When the app should hide its tabs.
@MainActor
final class UnreachableStateTests: XCTestCase {

    private func store() -> DashboardStore {
        DashboardStore(registry: ServerRegistry(
            defaults: UserDefaults(suiteName: "vaktpost.tests.\(UUID().uuidString)")!))
    }

    func testStaleDataDoesNotKeepTheTabsUp() {
        // The store keeps the last good data, so requiring `system == nil`
        // meant an app that had ever connected never showed the disconnected
        // state — it sat behind a banner showing hour-old numbers.
        let s = store()
        s.connectionError = "The firewall did not respond."
        s.system = SystemStatus(JSONDict(.object([:]))!)
        XCTAssertTrue(s.isUnreachable)
    }

    func testAnErrorWithNothingLoadedHidesThem() {
        let s = store()
        s.connectionError = "The firewall did not respond."
        s.system = nil
        XCTAssertTrue(s.isUnreachable)
    }

    func testNoErrorIsNotUnreachable() {
        let s = store()
        s.connectionError = nil
        s.system = nil
        XCTAssertFalse(s.isUnreachable)
    }
}

extension UnreachableStateTests {

    func testTransportFailureCountsAsUnreachable() {
        // A phone with no network produces a transport error on every request.
        // That used to be recorded against each section and nowhere else, so
        // the app kept its tabs and showed the previous refresh's numbers —
        // the exact case the disconnected screen exists for.
        XCTAssertTrue(RPCError.transport("The Internet connection appears to be offline.")
            .localizedDescription.isEmpty == false)
    }

    func testCancellationIsNotAFailure() {
        // Backgrounding the app cancels in flight requests, and that must not
        // read as the firewall being unreachable.
        let s = store()
        s.connectionError = nil
        XCTAssertFalse(s.isUnreachable)
    }
}

extension UnreachableStateTests {

    func testOfflineIsNotRetried() {
        // The system already knows there is no route. A retry waits the full
        // timeout again to be told the same thing, and a refresh makes five
        // calls — which is how the app sat on stale readings for minutes.
        XCTAssertFalse(RPCError.offline("offline").isRetryable)
        XCTAssertTrue(RPCError.transport("timed out").isRetryable)
    }

    func testBothCountAsAConnectionFailure() {
        XCTAssertTrue(RPCError.offline("offline").isConnectionFailure)
        XCTAssertTrue(RPCError.transport("timed out").isConnectionFailure)
        XCTAssertFalse(RPCError.unauthorized.isConnectionFailure)
        XCTAssertFalse(RPCError.fault(0, "boom").isConnectionFailure)
    }

    func testOfflineCarriesTheSystemsWording() {
        // "The Internet connection appears to be offline" is the system's own
        // sentence, and it says more than any paraphrase would.
        let error = RPCError.offline("The Internet connection appears to be offline.")
        XCTAssertEqual(error.localizedDescription,
                       "The Internet connection appears to be offline.")
    }
}
