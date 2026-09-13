import XCTest
@testable import Vaktpost

/// Decoding against payloads captured verbatim from a real firewall.
///
/// The models were written against documented endpoint names and guessed field
/// names, and five of those guesses were wrong in the same direction: they
/// produced a plausible zero rather than an error. "up 0m" on a box up for five
/// days, an empty load average, and "Current states 0" on a firewall holding
/// eleven thousand of them all rendered as a working screen.
///
/// So these fixtures are pasted from `curl` output rather than written by hand.
/// A hand-written fixture only ever tests the field names its author already
/// believed in, which is exactly what failed.
///
/// Captured from pfSense Plus 26.07-RELEASE, REST API v2, September 2026.
final class LiveShapeTests: XCTestCase {

    private func dict(_ json: String) throws -> JSONDict {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        return try XCTUnwrap(JSONDict(value))
    }

    // MARK: status/system

    private let systemJSON = """
    {
      "platform": "Super Micro 1537",
      "serial": "REDACTED",
      "uptime": "5 Days 01 Hour 37 Minutes 40 Seconds",
      "bios_vendor": "American Megatrends Inc.",
      "bios_version": "2.0c",
      "kernel_pti": true,
      "temp_c": null,
      "temp_f": null,
      "cpu_model": "Intel(R) Xeon(R) CPU D-1537 @ 1.70GHz",
      "cpu_load_avg": [0.88, 0.84, 0.72],
      "cpu_count": 16,
      "cpu_usage": 5.5,
      "mbuf_usage": null,
      "mem_usage": 9,
      "swap_usage": 0,
      "disk_usage": 0
    }
    """

    func testSystemStatusDecodesEveryFieldTheDashboardShows() throws {
        let sys = SystemStatus(try dict(systemJSON))

        XCTAssertEqual(sys.cpuUsage, 5.5)
        XCTAssertEqual(sys.memUsage, 9)
        XCTAssertEqual(sys.swapUsage, 0)
        XCTAssertEqual(sys.diskUsage, 0)
        XCTAssertEqual(sys.cpuCount, 16)
        XCTAssertEqual(sys.platform, "Super Micro 1537")

        // Nulls must stay nil so the meters hide rather than reading zero.
        XCTAssertNil(sys.temperature)
        XCTAssertNil(sys.mbufUsage)

        XCTAssertEqual(sys.load, [0.88, 0.84, 0.72])
        XCTAssertEqual(sys.loadDescription, "0.88  0.84  0.72")
    }

    func testUptimeParsesThePhrasingTheAPIActuallyReturns() throws {
        let sys = SystemStatus(try dict(systemJSON))
        // 5d 1h 37m 40s
        XCTAssertEqual(sys.uptimeSeconds, 5 * 86_400 + 3_600 + 37 * 60 + 40)
        XCTAssertEqual(Fmt.uptime(sys.uptimeSeconds ?? 0), "5d 1h 37m")
    }

    func testUptimeHandlesSingularUnitsAndPlainSeconds() {
        XCTAssertEqual(SystemStatus.uptime(.string("1 Day 01 Hour 00 Minutes 01 Second")),
                       86_400 + 3_600 + 1)
        XCTAssertEqual(SystemStatus.uptime(.string("42 Minutes 10 Seconds")), 42 * 60 + 10)
        // Some versions return a number instead.
        XCTAssertEqual(SystemStatus.uptime(.number(3_600)), 3_600)
        XCTAssertEqual(SystemStatus.uptime(.string("3600")), 3_600)
        XCTAssertNil(SystemStatus.uptime(.string("unknown")))
        XCTAssertNil(SystemStatus.uptime(nil))
    }

    // MARK: firewall/states/size

    func testStateTableFallsBackToTheDefaultLimit() throws {
        // `maximumstates` is null unless somebody overrode it, so the number
        // being enforced is the default. Without the fallback there is no
        // denominator and no meter on a stock firewall.
        let st = StateTableSize(try dict("""
        {"maximumstates": null, "defaultmaximumstates": 1621000, "currentstates": 11169}
        """))

        XCTAssertEqual(st.current, 11_169)
        XCTAssertNil(st.maximum)
        XCTAssertEqual(st.effectiveMaximum, 1_621_000)
        XCTAssertTrue(st.isDefaultLimit)
        XCTAssertEqual(st.fraction ?? 0, 11_169.0 / 1_621_000.0, accuracy: 0.000_001)
    }

    func testAnOverriddenLimitWins() throws {
        let st = StateTableSize(try dict("""
        {"maximumstates": 500000, "defaultmaximumstates": 1621000, "currentstates": 250000}
        """))
        XCTAssertEqual(st.effectiveMaximum, 500_000)
        XCTAssertFalse(st.isDefaultLimit)
        XCTAssertEqual(st.fraction ?? 0, 0.5, accuracy: 0.000_001)
    }

    // MARK: status/interfaces

    private let interfaceJSON = """
    {
      "id": 0,
      "name": "wan",
      "descr": "WAN_1",
      "hwif": "ix0",
      "macaddr": "3c:ec:ef:3d:46:38",
      "mtu": "1500",
      "enable": false,
      "status": "up",
      "ipaddr": "203.0.113.9",
      "subnet": "255.255.255.224",
      "linklocal": "fe80::3eec:efff:fe3d:4638%ix0",
      "ipaddrv6": null,
      "subnetv6": null,
      "inerrs": 359,
      "outerrs": 0,
      "collisions": 0,
      "inbytes": 689707905852,
      "outbytes": 515608849408,
      "inpkts": 611231240,
      "outpkts": 434801069,
      "dhcplink": "up",
      "media": "10Gbase-LR ",
      "gateway": "203.0.113.1",
      "gatewayv6": null
    }
    """

    func testInterfacePrefersTheAdministratorsDescription() throws {
        let iface = InterfaceStat(try dict(interfaceJSON))
        // "WAN_1", what the webConfigurator shows — not "wan", the internal handle.
        XCTAssertEqual(iface.name, "WAN_1")
        XCTAssertEqual(iface.device, "ix0")
    }

    func testDottedNetmaskRendersAsAPrefixLength() throws {
        let iface = InterfaceStat(try dict(interfaceJSON))
        XCTAssertEqual(iface.addressLine, "203.0.113.9/27")
    }

    func testPrefixLengthAcceptsEitherNotation() {
        XCTAssertEqual(InterfaceStat.prefixLength("255.255.255.224"), "27")
        XCTAssertEqual(InterfaceStat.prefixLength("255.255.255.0"), "24")
        XCTAssertEqual(InterfaceStat.prefixLength("255.255.0.0"), "16")
        // Already a prefix length on the configuration endpoints.
        XCTAssertEqual(InterfaceStat.prefixLength("27"), "27")
        XCTAssertNil(InterfaceStat.prefixLength(nil))
        XCTAssertNil(InterfaceStat.prefixLength(""))
    }

    func testALiveInterfaceIsHealthyDespiteTheEnableFlag() throws {
        let iface = InterfaceStat(try dict(interfaceJSON))
        // "enable": false on a WAN that is up and passing traffic. Link state
        // is what matters; trusting `enable` greyed out a working uplink.
        XCTAssertEqual(iface.enabled, false)
        XCTAssertTrue(iface.isUp)
        XCTAssertEqual(iface.health, .ok)
    }

    func testInterfaceCountersAndTrimmedMedia() throws {
        let iface = InterfaceStat(try dict(interfaceJSON))
        XCTAssertEqual(iface.inBytes, 689_707_905_852)
        XCTAssertEqual(iface.outBytes, 515_608_849_408)
        XCTAssertEqual(iface.mtu, "1500")
        XCTAssertEqual(iface.gateway, "203.0.113.1")
        // The API pads this with a trailing space.
        XCTAssertEqual(iface.media, "10Gbase-LR")
    }
}

/// Second batch, captured the same way — pasted from `curl`, not invented.
final class LiveShapeTests2: XCTestCase {

    private func dict(_ json: String) throws -> JSONDict {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        return try XCTUnwrap(JSONDict(value))
    }

    func testPackageDecodesAndFlattensItsDescription() throws {
        let pkg = PackageInfo(try dict("""
        {
          "id": 0,
          "name": "pfSense-pkg-acme",
          "shortname": "acme",
          "descr": "Automated Certificate Management Environment, for automated\\nuse of LetsEncrypt certificates.",
          "installed_version": "1.3.2",
          "latest_version": "1.3.2",
          "update_available": false
        }
        """))

        XCTAssertEqual(pkg.shortName, "acme")
        XCTAssertFalse(pkg.updateAvailable)
        XCTAssertEqual(pkg.health, .ok)
        // Up to date, so no arrow.
        XCTAssertEqual(pkg.versionLine, "1.3.2")
        // Manifest descriptions carry hard line breaks that would wrap oddly.
        XCTAssertFalse(pkg.descr?.contains("\n") ?? true)
    }

    func testAnOutdatedPackageShowsBothVersions() throws {
        let pkg = PackageInfo(try dict("""
        {"name": "pfSense-pkg-acme", "shortname": "acme",
         "installed_version": "1.3.2", "latest_version": "1.4.0",
         "update_available": true}
        """))
        XCTAssertEqual(pkg.versionLine, "1.3.2 → 1.4.0")
        XCTAssertEqual(pkg.health, .warn)
    }

    func testTableDecodesAndKeepsAnHonestCount() throws {
        let table = FirewallTable(try dict("""
        {"id": "LAN__NETWORK", "entries": ["172.16.1.0/24"], "name": "LAN__NETWORK"}
        """))
        XCTAssertEqual(table.name, "LAN__NETWORK")
        XCTAssertEqual(table.entries, ["172.16.1.0/24"])
        XCTAssertEqual(table.entryCount, 1)
        XCTAssertFalse(table.isTruncated)
        XCTAssertFalse(table.isNotable)
    }

    func testOnlyOperationallyInterestingTablesAreSurfaced() throws {
        let sshguard = FirewallTable(try dict("""
        {"id": "sshguard", "name": "sshguard", "entries": ["203.0.113.4", "198.51.100.9"]}
        """))
        XCTAssertTrue(sshguard.isNotable)
        XCTAssertEqual(sshguard.entryCount, 2)
    }

    func testConfiguredLiteralBlockIsSurfacedWithoutPfTableAccess() throws {
        let quickBlock = FirewallRule(try dict("""
        {
          "tracker": "1757720000", "type": "block", "interface": "wan",
          "source": {"address": "192.0.2.44/32"},
          "destination": {"any": true}, "descr": "Blocked by Vaktpost"
        }
        """))
        XCTAssertTrue(quickBlock.isConfiguredHostBlock)

        let disabled = FirewallRule(try dict("""
        {
          "tracker": "1757720001", "type": "block", "interface": "wan",
          "source": {"address": "192.0.2.45"},
          "destination": {"any": true}, "disabled": true
        }
        """))
        XCTAssertFalse(disabled.isConfiguredHostBlock)

        let selector = FirewallRule(try dict("""
        {
          "tracker": "1757720002", "type": "block", "interface": "wan",
          "source": {"network": "wanip"}, "destination": {"any": true}
        }
        """))
        XCTAssertFalse(selector.isConfiguredHostBlock)
    }

    func testPfSenseEmptyConfigurationMarkersMeanEnabledFlags() throws {
        // config.xml serialises presence flags as `<disabled/>` and `<log/>`.
        // XML-RPC turns those elements into empty strings, not JSON booleans.
        let rule = FirewallRule(try dict("""
        {
          "tracker": "1757720010", "type": "pass", "interface": "opt5",
          "source": {"any": true}, "destination": {"any": true},
          "disabled": "", "log": ""
        }
        """))
        XCTAssertTrue(rule.disabled)
        XCTAssertTrue(rule.logged)

        let explicitlyFalse = FirewallRule(try dict("""
        {
          "tracker": "1757720011", "type": "pass", "interface": "opt5",
          "source": {"any": true}, "destination": {"any": true},
          "disabled": "false", "log": 0
        }
        """))
        XCTAssertFalse(explicitlyFalse.disabled)
        XCTAssertFalse(explicitlyFalse.logged)

        let forward = PortForward(try dict("""
        {
          "tracker": "1757720012", "interface": "wan", "protocol": "tcp",
          "source": {"any": true}, "destination": {"any": true},
          "target": "192.0.2.10", "disabled": ""
        }
        """))
        XCTAssertTrue(forward.disabled)
    }

    func testHugeTablesAreCappedButStillCountedHonestly() throws {
        // `bogons` runs to thousands of rows. Keeping them all on a phone to
        // render a list nobody scrolls is pointless, but the count must not lie.
        let entries = (0..<5_000).map { "\"10.\($0 / 256).\($0 % 256).0/24\"" }.joined(separator: ",")
        let table = FirewallTable(try dict("""
        {"id": "bogons", "name": "bogons", "entries": [\(entries)]}
        """))
        XCTAssertEqual(table.entryCount, 5_000)
        XCTAssertEqual(table.entries.count, 200)
        XCTAssertTrue(table.isTruncated)
    }
}

/// OpenVPN, captured from the same firewall.
final class OpenVPNShapeTests: XCTestCase {

    private func dict(_ json: String) throws -> JSONDict {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        return try XCTUnwrap(JSONDict(value))
    }

    private let serverJSON = """
    {
      "id": 0,
      "name": "openvpn1 UDP4:1194",
      "mode": "server_tls_user",
      "port": "1194",
      "vpnid": 1,
      "mgmt": "server1",
      "conns": [
        {"common_name": "ovpn_sphere", "remote_host": "udp4:198.51.100.20:55372",
         "virtual_addr": "10.253.11.11", "bytes_recv": 1825361100, "bytes_sent": 1610612736},
        {"common_name": "ovpn_kak-sv-nas001", "remote_host": "udp4:198.51.100.162:43600",
         "virtual_addr": "10.253.11.10", "bytes_recv": 1010224988, "bytes_sent": 2040109465}
      ],
      "routes": [
        {"parent_id": 0, "id": 0, "common_name": "ovpn_sphere",
         "remote_host": "udp4:198.51.100.20:55372", "virtual_addr": "10.253.11.11",
         "last_time": "2026-09-03 11:20:42"},
        {"parent_id": 0, "id": 1, "common_name": "ovpn_kak-sv-nas001",
         "remote_host": "udp4:198.51.100.162:43600", "virtual_addr": "10.253.11.10",
         "last_time": "2026-09-03 00:28:49"}
      ]
    }
    """

    func testServerStateIsDerivedBecauseThereIsNoStatusField() throws {
        // 26.07 returns no `status` for OpenVPN servers. Reading one produced a
        // permanent "UNKNOWN" pill — a placeholder presented as a reading.
        let server = OpenVPNServerStatus(try dict(serverJSON))
        XCTAssertNil(server.status)
        XCTAssertEqual(server.connections.count, 2)
        XCTAssertEqual(server.statusLabel, "2 connected")
        XCTAssertEqual(server.health, .ok)
    }

    func testAServerWithNoClientsIsIdleNotBroken() throws {
        // Normal for a remote-access server nobody is using right now.
        let server = OpenVPNServerStatus(try dict("""
        {"id": 1, "name": "openvpn2 UDP4:1195", "mode": "server_tls_user", "vpnid": 2}
        """))
        XCTAssertEqual(server.statusLabel, "no clients")
        XCTAssertEqual(server.health, .idle)
    }

    func testSingularConnectionReadsNaturally() throws {
        let server = OpenVPNServerStatus(try dict("""
        {"name": "openvpn1", "vpnid": 1, "conns": [{"common_name": "a", "remote_host": "x"}]}
        """))
        XCTAssertEqual(server.statusLabel, "1 connected")
    }

    func testRoutesSupplyLastSeenPerClient() throws {
        let server = OpenVPNServerStatus(try dict(serverJSON))
        XCTAssertEqual(server.lastSeen(for: "ovpn_sphere"), "2026-09-03 11:20:42")
        XCTAssertEqual(server.lastSeen(for: "ovpn_kak-sv-nas001"), "2026-09-03 00:28:49")
        XCTAssertNil(server.lastSeen(for: "nobody"))
    }

    func testModeLabelIsReadable() throws {
        let server = OpenVPNServerStatus(try dict(serverJSON))
        XCTAssertEqual(server.modeLabel, "server tls user")
    }

    func testAStatusFieldStillWinsWhereOneExists() throws {
        // The clients endpoint does report one, and older versions may.
        let client = OpenVPNServerStatus(try dict("""
        {"name": "vpnclient", "vpnid": 3, "status": "connected"}
        """))
        XCTAssertEqual(client.statusLabel, "connected")
        XCTAssertEqual(client.health, .ok)
    }
}
