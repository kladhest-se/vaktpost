import XCTest
@testable import Vaktpost

/// The XML-RPC payload shapes differ from the REST ones in small, quiet ways —
/// hyphens instead of underscores, "online" instead of true. Each of these is a
/// field that would read as nil and render as a blank rather than an error.
final class XMLRPCShapeTests: XCTestCase {

    private func dict(_ json: String) throws -> JSONDict {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        return try XCTUnwrap(JSONDict(value))
    }

    func testARPTableUsesHyphenatedKeys() throws {
        // `system_get_arp_table` returns ip-address / mac-address.
        let entry = ARPEntry(try dict("""
        {"hostname": "nas001", "ip-address": "172.16.1.20", "mac-address": "AA:BB:CC:DD:EE:FF",
         "interface": "igb1", "expires": 1199, "type": "ethernet"}
        """))
        XCTAssertEqual(entry.ip, "172.16.1.20")
        XCTAssertEqual(entry.mac, "aa:bb:cc:dd:ee:ff")
        XCTAssertEqual(entry.interfaceName, "igb1")
    }

    func testLeaseOnlineIsAStringNotABoolean() throws {
        // `system_get_dhcpleases` reports "online" / "offline".
        let online = DHCPLease(try dict("""
        {"ip": "172.16.1.50", "mac": "aa:bb:cc:dd:ee:ff", "if": "lan",
         "act": "static", "online": "online", "hostname": "printer"}
        """))
        XCTAssertEqual(online.online, true)
        // `.info` rather than `.ok`: this lease is a static mapping, and the
        // model colours those distinctly from a device that merely happens to
        // be answering. The string parsing is what this test is about.
        XCTAssertEqual(online.health, .info)

        let offline = DHCPLease(try dict("""
        {"ip": "172.16.1.51", "mac": "11:22:33:44:55:66", "act": "active", "online": "offline"}
        """))
        XCTAssertEqual(offline.online, false)
    }

    func testGatewayValuesCarryTheirUnits() throws {
        // return_gateways_status gives "0.387ms" and "0.0%", not numbers.
        let gw = GatewayStatus(try dict("""
        {"name": "WAN_DHCP", "monitorip": "198.51.100.1", "srcip": "198.51.100.9",
         "delay": "0.387ms", "stddev": "0.097ms", "loss": "0.0%",
         "status": "online", "substatus": "none"}
        """))
        XCTAssertEqual(gw.delayMS ?? 0, 0.387, accuracy: 0.0001)
        XCTAssertEqual(gw.lossPercent ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(gw.health, .ok)
    }

    func testLoadAverageDecodesFromEitherShape() throws {
        let asList = SystemStatus(try dict("""
        {"cpu_load_avg": [0.88, 0.84, 0.72]}
        """))
        XCTAssertEqual(asList.load, [0.88, 0.84, 0.72])

        let asObject = SystemStatus(try dict("""
        {"cpu_load_avg": {"one_minute": 0.88, "five_minute": 0.84, "fifteen_minute": 0.72}}
        """))
        XCTAssertEqual(asObject.load, [0.88, 0.84, 0.72])
    }

    func testTelemetryCarriesTheStateTableToo() throws {
        // One exec_php round trip is expensive, so the state counts ride along
        // in the telemetry snippet rather than costing a call of their own.
        let d = try dict("""
        {"cpu_usage": 5.5, "mem_usage": 9, "uptime_sec": 437860,
         "currentstates": 12110, "maximumstates": 1621000}
        """)
        XCTAssertEqual(SystemStatus(d).uptimeSeconds, 437_860)
        XCTAssertEqual(StateTableSize(d).current, 12_110)
        XCTAssertEqual(StateTableSize(d).effectiveMaximum, 1_621_000)
    }

    func testFilesystemHealthTracksUsage() throws {
        let full = Filesystem(try dict("""
        {"mountpoint": "/var", "device": "/dev/ufsid/x", "percent_used": 94, "total_size": "3.5G"}
        """))
        XCTAssertEqual(full.health, .bad)
        XCTAssertEqual(full.mountpoint, "/var")

        let fine = Filesystem(try dict(#"{"mountpoint": "/", "percent_used": 12}"#))
        XCTAssertEqual(fine.health, .ok)
    }

    func testNoticeCarriesItsTimestampFromTheKey() throws {
        // get_notices returns an object keyed by creation time; the snippet
        // folds the key back in as created_at.
        let notice = SystemNotice(try dict("""
        {"created_at": "1757193600", "notice": "Gateway alarm: WAN_DHCP",
         "category": "system", "priority": 1}
        """))
        XCTAssertEqual(notice.health, .bad)
        XCTAssertNotNil(notice.date)
    }

    func testDyndnsRecordsWhatItLastPushed() throws {
        let entry = DyndnsEntry(try dict("""
        {"host": "home.example.se", "type": "cloudflare", "interface": "wan",
         "descr": "Home", "enabled": true, "cached_address": "198.51.100.9",
         "updated_at": 1757193600}
        """))
        XCTAssertEqual(entry.displayName, "Home")
        XCTAssertEqual(entry.cachedAddress, "198.51.100.9")
        XCTAssertNotNil(entry.updatedAt)
    }

    func testDyndnsWithNoCacheFileReadsAsNeverUpdated() throws {
        // An entry configured but never successfully pushed. Empty string, not
        // absent — the snippet always sets the key.
        let entry = DyndnsEntry(try dict("""
        {"host": "new.example.se", "enabled": true, "cached_address": "", "updated_at": 0}
        """))
        XCTAssertNil(entry.cachedAddress)
        XCTAssertNil(entry.updatedAt)
        XCTAssertEqual(entry.updatedDescription, "never updated")
    }
}

/// Row extraction, which has to cope with three different shapes because PHP
/// returns whichever one the underlying function felt like.
final class RowShapeTests: XCTestCase {

    private func decode(_ json: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    }

    /// Mirrors `XMLRPCClient.runList` without needing a live connection.
    private func rows(_ json: String) throws -> [JSONDict] {
        let value = try decode(json)
        if let array = value.arrayValue { return array.compactMap { JSONDict($0) } }
        guard let dict = JSONDict(value) else { return [] }
        if let payload = dict.value("data") {
            if let array = payload.arrayValue { return array.compactMap { JSONDict($0) } }
            if let object = payload.objectValue { return fold(object) }
            return []
        }
        return fold(dict.raw)
    }

    private func fold(_ object: [String: JSONValue]) -> [JSONDict] {
        object.compactMap { key, value in
            guard var row = JSONDict(value)?.raw else { return nil }
            if row["name"] == nil { row["name"] = .string(key) }
            return JSONDict(row)
        }
        .sorted { ($0.string("name") ?? "") < ($1.string("name") ?? "") }
    }

    func testListUnderData() throws {
        let result = try rows(#"{"data": [{"name": "a"}, {"name": "b"}]}"#)
        XCTAssertEqual(result.count, 2)
    }

    func testKeyedObjectUnderData() throws {
        // return_gateways_status(true) keys by gateway name. Getting this
        // wrong produced a single row called "data" — which looked like one
        // broken gateway rather than a parsing failure.
        let result = try rows("""
        {"data": {
          "WAN2_DHCP": {"monitorip": "198.51.100.2", "status": "online", "delay": "8.4ms"},
          "WAN_DHCP":  {"monitorip": "198.51.100.1", "status": "online", "delay": "0.4ms"}
        }}
        """)
        XCTAssertEqual(result.count, 2)
        // The key is the gateway's name and has to survive.
        XCTAssertEqual(result.map { $0.string("name") }, ["WAN2_DHCP", "WAN_DHCP"])
        XCTAssertEqual(GatewayStatus(result[1]).name, "WAN_DHCP")
        XCTAssertEqual(GatewayStatus(result[1]).delayMS ?? 0, 0.4, accuracy: 0.001)
    }

    func testKeyedObjectKeepsAnExistingName() throws {
        // Where the row already names itself, the key must not overwrite it.
        let result = try rows(#"{"data": {"wan": {"name": "WAN_1", "status": "up"}}}"#)
        XCTAssertEqual(result.first?.string("name"), "WAN_1")
    }

    func testEmptyDataIsNoRowsNotOneRow() throws {
        XCTAssertTrue(try rows(#"{"data": []}"#).isEmpty)
        XCTAssertTrue(try rows(#"{"data": {}}"#).isEmpty)
    }

    func testBareListAtTopLevel() throws {
        XCTAssertEqual(try rows(#"[{"name": "a"}]"#).count, 1)
    }
}

/// Fixtures taken verbatim from a pfSense Plus 26.07 firewall over XML-RPC.
/// Each one is here because a field read wrong the first time.
final class TelemetryShapeTests: XCTestCase {

    private func dict(_ json: String) throws -> JSONDict {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        return try XCTUnwrap(JSONDict(value))
    }

    func testPlatformIsAnObjectNotAString() throws {
        // system_identify_specific_platform() returns name/descr. Reading it
        // as a string gave nil and the hardware row disappeared.
        let sys = SystemStatus(try dict("""
        {"platform": {"descr": "Super Micro 1537", "name": "1537"}, "cpu_count": 16}
        """))
        XCTAssertEqual(sys.platform, "Super Micro 1537")
        XCTAssertEqual(sys.hardwareDescription, "Super Micro 1537 · 16 cores")
    }

    func testPlatformStillWorksAsAPlainString() throws {
        let sys = SystemStatus(try dict(#"{"platform": "Netgate 6100"}"#))
        XCTAssertEqual(sys.platform, "Netgate 6100")
    }

    func testAbsentSensorsAreNilNotZero() throws {
        // get_temp() and get_mbuf() return empty on hardware without them.
        // floatval("") is 0.0 — a firewall at exactly zero degrees with zero
        // mbufs, both of which look like readings.
        let sys = SystemStatus(try dict("""
        {"temp_c": null, "mbuf_usage": null, "mbuf_used": null, "mem_usage": 8}
        """))
        XCTAssertNil(sys.temperature)
        XCTAssertFalse(sys.hasTemperature)
        XCTAssertNil(sys.mbufUsage)
        XCTAssertEqual(sys.memUsage, 8)
    }

    func testCPUArrivesAsTicksWithNoPercentage() throws {
        // cpu_usage() gives "<total>|<idle>". Taking floatval of it produced a
        // CPU meter reading 995026240%.
        let sys = SystemStatus(try dict("""
        {"cpu_ticks_total": 995026240, "cpu_ticks_idle": 900000000, "cpu_count": 16}
        """))
        XCTAssertNil(sys.cpuUsage, "a single sample cannot yield a percentage")
        XCTAssertEqual(sys.cpuTicksTotal, 995_026_240)
        XCTAssertEqual(sys.cpuTicksIdle, 900_000_000)
    }

    func testCPUPercentageFromTwoSamples() {
        // The arithmetic DashboardStore.deriveCPUUsage performs.
        func busy(_ from: (Int, Int), _ to: (Int, Int)) -> Double? {
            let totalDelta = to.0 - from.0
            let idleDelta = to.1 - from.1
            guard totalDelta > 0, idleDelta >= 0, idleDelta <= totalDelta else { return nil }
            return min(100, max(0, (1 - Double(idleDelta) / Double(totalDelta)) * 100))
        }
        // 1000 ticks passed, 950 of them idle: 5% busy.
        XCTAssertEqual(busy((0, 0), (1000, 950)) ?? -1, 5, accuracy: 0.001)
        XCTAssertEqual(busy((0, 0), (1000, 1000)) ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(busy((0, 0), (1000, 0)) ?? -1, 100, accuracy: 0.001)
        // A reboot resets the counters.
        XCTAssertNil(busy((5000, 4000), (100, 90)))
        // The same sample twice.
        XCTAssertNil(busy((1000, 900), (1000, 900)))
    }

    func testFirmwareUpdateFlagComesFromTheComparison() throws {
        // The nested object compares versions itself; "<" means behind.
        // Comparing the two version strings directly fails on release
        // suffixes — "26.07-RELEASE" against "26.07".
        let current = SystemVersion(try dict("""
        {"version": "26.07-RELEASE", "installed_version": "26.07",
         "latest_version": "26.07", "update_available": false}
        """))
        XCTAssertEqual(current.current, "26.07-RELEASE")
        XCTAssertEqual(current.updateAvailable, false)

        let behind = SystemVersion(try dict("""
        {"version": "26.07-RELEASE", "installed_version": "26.07",
         "latest_version": "26.09", "update_available": true}
        """))
        XCTAssertEqual(behind.updateAvailable, true)
        XCTAssertEqual(behind.latest, "26.09")
    }

    func testZFSDatasetsReportZeroPercent() throws {
        // Real output. pfSense computes this per-dataset against the pool's
        // free space, so every ZFS dataset on a large pool reads 0 — the
        // figure is honest, just not useful. Only tmpfs shows real pressure.
        let zfs = Filesystem(try dict("""
        {"device": "pfSense/var/log", "mountpoint": "/var/log",
         "percent_used": "0", "total_size": "403G", "type": "zfs"}
        """))
        XCTAssertEqual(zfs.percentUsed, 0)
        XCTAssertEqual(zfs.health, .ok)

        let tmp = Filesystem(try dict("""
        {"device": "tmpfs", "mountpoint": "/var/run",
         "percent_used": "5", "total_size": "4.0M", "type": "tmpfs"}
        """))
        XCTAssertEqual(tmp.percentUsed, 5)
    }
}

extension TelemetryShapeTests {

    func testDiskUsageFallsBackToTheFullestMount() throws {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data("""
        {"filesystems": [
          {"mountpoint": "/", "percent_used": "0"},
          {"mountpoint": "/var/run", "percent_used": "5"},
          {"mountpoint": "/var/log", "percent_used": "0"}
        ]}
        """.utf8))
        let sys = SystemStatus(JSONDict(value)!)
        // The worst mount, not an average — a full /var stops logging while
        // the pool as a whole looks empty.
        XCTAssertEqual(sys.diskUsage, 5)
    }

    func testAnAggregateFigureStillWins() throws {
        // The REST transport reported one number; it is preferred where present.
        let value = try JSONDecoder().decode(JSONValue.self, from: Data("""
        {"disk_usage": 42, "filesystems": [{"mountpoint": "/", "percent_used": "1"}]}
        """.utf8))
        XCTAssertEqual(SystemStatus(JSONDict(value)!).diskUsage, 42)
    }
}

/// Notices, including the ones this app causes.
final class NoticeTests: XCTestCase {

    private func dict(_ json: String) throws -> JSONDict {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        return try XCTUnwrap(JSONDict(value))
    }

    func testEntitiesAreDecoded() throws {
        // pfSense stores notices HTML-escaped.
        let notice = SystemNotice(try dict("""
        {"created_at": "1757253120",
         "notice": "PHP ERROR: eval()&#039;d code &gt; failed &amp; logged"}
        """))
        XCTAssertEqual(notice.notice, "PHP ERROR: eval()'d code > failed & logged")
    }

    func testAmpersandDecodesLast() {
        // "&amp;gt;" is a literal "&gt;", not a ">".
        XCTAssertEqual(SystemNotice.decodeEntities("&amp;gt;"), "&gt;")
    }

    func testAStackTraceCollapsesToItsFirstLine() throws {
        let notice = SystemNotice(try dict("""
        {"created_at": "1757253120",
         "notice": "PHP ERROR: Uncaught TypeError: Cannot access offset\\nStack trace:\\n#0 xmlrpc.php(141)\\n#1 Server.php(135)"}
        """))
        XCTAssertTrue(notice.isMultiline)
        XCTAssertEqual(notice.summary, "PHP ERROR: Uncaught TypeError: Cannot access offset")
        XCTAssertFalse(notice.summary.contains("Stack trace"))
    }

    func testAShortNoticeIsNotCollapsed() throws {
        let notice = SystemNotice(try dict("""
        {"created_at": "1757253120", "notice": "Gateway alarm: WAN_DHCP is down"}
        """))
        XCTAssertFalse(notice.isMultiline)
        XCTAssertEqual(notice.summary, notice.notice)
    }

    func testTheAppRecognisesItsOwnFailures() throws {
        // A snippet that throws is recorded by pfSense as a notice, which the
        // app reads back and displays — so its own bug arrives looking like a
        // firewall fault. Saying which is which is the least it can do.
        let ours = SystemNotice(try dict("""
        {"created_at": "1757253120",
         "notice": "PHP ERROR: Type: 1, File: /usr/local/www/xmlrpc.php(141) : eval()&#039;d code, Line: 19"}
        """))
        XCTAssertTrue(ours.isFromThisApp)

        let theirs = SystemNotice(try dict("""
        {"created_at": "1757253120", "notice": "Gateway alarm: WAN_DHCP is down"}
        """))
        XCTAssertFalse(theirs.isFromThisApp)
    }
}

/// WireGuard, whose peers live in their own config section.
final class WireGuardShapeTests: XCTestCase {

    private func dict(_ json: String) throws -> JSONDict {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        return try XCTUnwrap(JSONDict(value))
    }

    func testPeerDecodesFromConfiguration() throws {
        let peer = WireGuardPeer(try dict("""
        {"tun": "tun_wg0", "public_key": "EiKx9SbSk+9TCtY+abcdefghijklmnop=",
         "descr": "wireguard1-pc-frossmant-macbook",
         "endpoint": "198.51.100.137:15980", "enabled": true,
         "allowed_ips": ["10.253.21.10/32"]}
        """))
        XCTAssertEqual(peer.tunnel, "tun_wg0")
        XCTAssertEqual(peer.descr, "wireguard1-pc-frossmant-macbook")
        XCTAssertEqual(peer.endpoint, "198.51.100.137:15980")
        XCTAssertEqual(peer.allowedIPs, ["10.253.21.10/32"])
        XCTAssertEqual(peer.shortKey, "EiKx9SbSk+…")
    }

    func testAbsentHandshakeIsNotReportedAsAFailure() throws {
        // Configuration carries no handshake time — that is in `wg show`.
        // Calling a peer "no handshake" says it is failing, when the truth is
        // that nothing was measured.
        let peer = WireGuardPeer(try dict("""
        {"tun": "tun_wg0", "public_key": "abc", "enabled": true}
        """))
        XCTAssertFalse(peer.hasLiveStatus)
        XCTAssertEqual(peer.statusLabel, "configured")
        XCTAssertEqual(peer.health, .info)
    }

    func testADisabledPeerIsIdle() throws {
        let peer = WireGuardPeer(try dict("""
        {"tun": "tun_wg2", "public_key": "abc", "enabled": false}
        """))
        XCTAssertEqual(peer.statusLabel, "disabled")
        XCTAssertEqual(peer.health, .idle)
    }

    func testALiveHandshakeStillWins() throws {
        // A fixed timestamp went stale the moment the label started depending
        // on recency — the peer was connected when this was written and idle
        // by definition a week later.
        let recent = Int(Date().timeIntervalSince1970) - 30
        let peer = WireGuardPeer(try dict("""
        {"tun": "tun_wg0", "public_key": "abc", "enabled": true,
         "latest_handshake": "\(recent)"}
        """))
        XCTAssertTrue(peer.hasLiveStatus)
        XCTAssertEqual(peer.statusLabel, "connected")
        XCTAssertEqual(peer.health, .ok)
    }

    func testPeersAreMatchedToTheirTunnelByName() throws {
        // The tunnel's `name` is "tun_wg0"; its `descr` is "wireguard1".
        let tunnel = WireGuardTunnel(try dict("""
        {"name": "tun_wg0", "descr": "wireguard1", "listenport": "51820", "enabled": "yes"}
        """))
        let peer = WireGuardPeer(try dict("""
        {"tun": "tun_wg0", "public_key": "abc", "enabled": true}
        """))
        XCTAssertEqual(tunnel.name, "tun_wg0")
        XCTAssertEqual(peer.tunnel, tunnel.name)
    }
}

/// WireGuard live status, from a `wg_get_status()` payload captured verbatim.
/// Keys are replaced; the structure is exactly as returned.
final class WireGuardStatusTests: XCTestCase {

    private func dict(_ json: String) throws -> JSONDict {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        return try XCTUnwrap(JSONDict(value))
    }

    func testTunnelCarriesLiveTotals() throws {
        let tunnel = WireGuardTunnel(try dict("""
        {"name": "tun_wg0", "descr": "wireguard1", "enabled": true,
         "listen_port": "51820", "mtu": 1500, "status": "up",
         "public_key": "REDACTED", "transfer_rx": 2387984808,
         "transfer_tx": 57617946964, "peer_count": 1}
        """))
        XCTAssertTrue(tunnel.isUp)
        XCTAssertEqual(tunnel.statusLabel, "up")
        XCTAssertEqual(tunnel.health, .ok)
        XCTAssertEqual(tunnel.bytesSent, 57_617_946_964)
        XCTAssertEqual(tunnel.peerCount, 1)
    }

    func testARecentHandshakeIsConnected() throws {
        let recent = Date().timeIntervalSince1970 - 60
        let peer = WireGuardPeer(try dict("""
        {"tun": "tun_wg0", "public_key": "REDACTED",
         "descr": "wireguard1-pc-frossmant-macbook", "enabled": true,
         "endpoint": "198.51.100.137:15980", "latest_handshake": "\(Int(recent))",
         "transfer_rx": "2387984808", "transfer_tx": "57617946964",
         "allowed_ips": ["10.253.21.10/32"]}
        """))
        XCTAssertEqual(peer.statusLabel, "connected")
        XCTAssertEqual(peer.health, .ok)
        XCTAssertEqual(peer.bytesSent, 57_617_946_964)
        XCTAssertEqual(peer.allowedIPs, ["10.253.21.10/32"])
    }

    func testAnOldHandshakeIsIdleNotBroken() throws {
        // WireGuard rehandshakes about every two minutes while traffic flows.
        // A laptop that closed its lid is idle, not a fault.
        let old = Date().timeIntervalSince1970 - 3_600
        let peer = WireGuardPeer(try dict("""
        {"tun": "tun_wg0", "public_key": "REDACTED", "enabled": true,
         "latest_handshake": "\(Int(old))"}
        """))
        XCTAssertEqual(peer.statusLabel, "idle")
        XCTAssertEqual(peer.health, .info)
    }

    func testZeroMeansNeverConnected() throws {
        // Distinct from an old handshake, and from having no status at all.
        let peer = WireGuardPeer(try dict("""
        {"tun": "tun_wg2", "public_key": "REDACTED", "enabled": true,
         "latest_handshake": "0", "endpoint": "", "transfer_rx": "0", "transfer_tx": "0"}
        """))
        XCTAssertNil(peer.handshakeDate)
        XCTAssertEqual(peer.statusLabel, "never connected")
        XCTAssertEqual(peer.health, .warn)
        XCTAssertEqual(peer.handshakeDescription, "never connected")
    }

    func testNoStatusAtAllIsNotAFailure() throws {
        let peer = WireGuardPeer(try dict("""
        {"tun": "tun_wg0", "public_key": "REDACTED", "enabled": true}
        """))
        XCTAssertFalse(peer.hasLiveStatus)
        XCTAssertEqual(peer.statusLabel, "configured")
        XCTAssertEqual(peer.health, .info)
    }

    func testNoSnippetReturnsAKey() {
        // wg_get_status() hands back the private key of every tunnel and the
        // preshared key of every peer. Nothing may carry them off the firewall.
        for snippet in PHPSnippet.all {
            for secret in ["privatekey", "private_key", "presharedkey", "preshared_key"] {
                let uses = snippet.script
                    .split(separator: "\n")
                    .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                    .contains { $0.contains(secret) }
                XCTAssertFalse(uses, "\(snippet.name) references \(secret)")
            }
        }
    }
}

extension NoticeTests {

    /// A failing snippet writes a notice every refresh. Left one-to-one, the
    /// alert list fills with the app's own bug and buries everything else.
    func testAppRaisedNoticesCollapseToOneAlert() throws {
        let ours = (0..<40).map { _ in
            SystemNotice(try! dict("""
            {"created_at": "1757253120",
             "notice": "PHP ERROR: Type: 1, File: /usr/local/www/xmlrpc.php(141) : eval()&#039;d code"}
            """))
        }
        XCTAssertTrue(ours.allSatisfy(\.isFromThisApp))
        XCTAssertEqual(Set(ours.map(\.summary)).count, 1,
                       "identical failures should share a summary")
    }

    func testAFirewallNoticeIsNotCollapsed() throws {
        let theirs = SystemNotice(try dict("""
        {"created_at": "1757253120", "notice": "Gateway alarm: WAN_DHCP is down"}
        """))
        XCTAssertFalse(theirs.isFromThisApp)
    }
}

extension NoticeTests {

    /// Notices persist on the firewall until somebody clears them, so a bug
    /// fixed twenty minutes ago still has eighty entries in the log. Reporting
    /// those as a current failure is false.
    func testOldAppNoticesAreNotACurrentFailure() throws {
        let old = Date().timeIntervalSince1970 - 3_600
        let notice = SystemNotice(try dict("""
        {"created_at": "\(Int(old))",
         "notice": "PHP ERROR: Type: 1, File: /usr/local/www/xmlrpc.php(141) : eval()&#039;d code"}
        """))
        XCTAssertTrue(notice.isFromThisApp)
        let age = Date().timeIntervalSince(try XCTUnwrap(notice.date))
        XCTAssertGreaterThan(age, 900, "an hour old is history, not a fault")
    }

    func testARecentAppNoticeIsACurrentFailure() throws {
        let justNow = Date().timeIntervalSince1970 - 30
        let notice = SystemNotice(try dict("""
        {"created_at": "\(Int(justNow))",
         "notice": "PHP ERROR: Type: 1, File: /usr/local/www/xmlrpc.php(141) : eval()&#039;d code"}
        """))
        let age = Date().timeIntervalSince(try XCTUnwrap(notice.date))
        XCTAssertLessThan(age, 900)
    }

    func testAnUndatedNoticeIsTreatedAsCurrent() throws {
        // Erring towards reporting: a notice with no timestamp might be now.
        let notice = SystemNotice(try dict(#"{"notice": "PHP ERROR: xmlrpc.php(141) : eval()"}"#))
        XCTAssertNil(notice.date)
        XCTAssertTrue(notice.isFromThisApp)
    }
}

/// Aliases, whose members are stored very differently by the two transports.
final class AliasShapeTests: XCTestCase {

    private func dict(_ json: String) throws -> JSONDict {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        return try XCTUnwrap(JSONDict(value))
    }

    func testMembersAreASpaceSeparatedStringInConfig() throws {
        // config.xml stores them as one string. Reading it as a list gave an
        // empty alias — the Firewall tab showed a member count of zero and no
        // client took a name from it.
        let alias = FirewallAliasEntry(try dict("""
        {"name": "alias_host_apple_homekit", "type": "host",
         "address": "172.16.1.50 172.16.1.51 172.16.1.52 172.16.1.53 172.16.1.54 172.16.1.55",
         "detail": "hub||tv||speaker||lamp||sensor||bridge"}
        """))
        XCTAssertEqual(alias.addresses.count, 6)
        XCTAssertEqual(alias.addresses.first, "172.16.1.50")
        XCTAssertEqual(alias.details.count, 6)
        XCTAssertEqual(alias.details[1], "tv")
    }

    func testASingleMemberStillParses() throws {
        let alias = FirewallAliasEntry(try dict("""
        {"name": "alias_host_app001", "type": "host", "address": "172.16.1.141"}
        """))
        XCTAssertEqual(alias.addresses, ["172.16.1.141"])
    }

    func testAListIsStillAccepted() throws {
        // What the REST transport returned, kept working so fixtures from
        // either transport decode.
        let alias = FirewallAliasEntry(try dict("""
        {"name": "a", "type": "host", "address": ["10.0.0.1", "10.0.0.2"]}
        """))
        XCTAssertEqual(alias.addresses, ["10.0.0.1", "10.0.0.2"])
    }

    func testAnAliasWithNoMembersIsEmptyNotACrash() throws {
        XCTAssertTrue(FirewallAliasEntry(try dict(#"{"name": "a", "type": "host"}"#)).addresses.isEmpty)
    }

    func testSpaceSeparatedMembersNameAClient() throws {
        // The whole point: 172.16.1.141 is alias_host_app001 on the firewall.
        let alias = FirewallAliasEntry(try dict("""
        {"name": "alias_host_app001", "type": "host", "address": "172.16.1.141"}
        """))
        let names = NetworkClient.aliasNamesByIP([alias])
        XCTAssertEqual(names["172.16.1.141"], "alias_host_app001")
    }
}

/// Dynamic DNS, whose config shapes are all slightly surprising.
final class DyndnsShapeTests: XCTestCase {

    private func dict(_ json: String) throws -> JSONDict {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        return try XCTUnwrap(JSONDict(value))
    }

    func testHostnameIsHostPlusDomain() throws {
        // config.xml keeps them apart; the webConfigurator shows them joined,
        // and "@" on its own names nothing.
        let entry = DyndnsEntry(try dict("""
        {"host": "@.example.se", "type": "cloudflare", "interface": "wan",
         "enabled": true, "cached_address": "198.51.100.9", "updated_at": 1788038229}
        """))
        XCTAssertEqual(entry.host, "@.example.se")
        XCTAssertEqual(entry.cachedAddress, "198.51.100.9")
    }

    func testCachedAddressIsSeparatedFromItsTimestamp() throws {
        // The cache file holds "<address>|<unix time>". Reading it whole put
        // "198.51.100.9|1788038229" on screen where an address belonged.
        let entry = DyndnsEntry(try dict("""
        {"host": "www.example.se", "enabled": true,
         "cached_address": "198.51.100.9", "updated_at": 1788038229}
        """))
        XCTAssertEqual(entry.cachedAddress, "198.51.100.9")
        XCTAssertFalse(entry.cachedAddress?.contains("|") ?? true)
        XCTAssertNotNil(entry.updatedAt)
    }

    func testAnEnabledEntryIsNotReportedAsDisabled() throws {
        // pfSense writes this as an empty element, which reads as false — so
        // every entry showed DISABLED while the web UI showed them all green.
        // The snippet now reports presence of the key.
        let on = DyndnsEntry(try dict(#"{"host": "a.example.se", "enabled": true}"#))
        XCTAssertTrue(on.enabled)

        let off = DyndnsEntry(try dict(#"{"host": "b.example.se", "enabled": false}"#))
        XCTAssertFalse(off.enabled)
    }

    func testAnEntryThatNeverPushedIsDistinctFromOneThatDid() throws {
        let never = DyndnsEntry(try dict("""
        {"host": "new.example.se", "enabled": true, "cached_address": "", "updated_at": 0}
        """))
        XCTAssertNil(never.cachedAddress)
        XCTAssertEqual(never.updatedDescription, "never updated")
    }
}

/// HAProxy, from a real 35-backend configuration.
final class HAProxyShapeTests: XCTestCase {

    private func dict(_ json: String) throws -> JSONDict {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        return try XCTUnwrap(JSONDict(value))
    }

    func testABasicCheckCountsAsMonitoring() throws {
        // "Basic" is a TCP connect check — the package's name for it, and the
        // most common setting. Reading it as "not HTTP, so not checked" would
        // have flagged most of a healthy configuration.
        let backend = HAProxyBackend(try dict("""
        {"name": "backend_www.example.se", "check_type": "Basic", "check_interval": "",
         "servers": [{"name": "web002", "address": "172.16.1.132", "port": "6661",
                      "enabled": true, "ssl": false}]}
        """))
        XCTAssertTrue(backend.isMonitored)
        XCTAssertEqual(backend.health, .ok)
        // A blank interval is HAProxy's default, not an absence.
        XCTAssertEqual(backend.checkDescription, "Basic · default interval")
    }

    func testAnHTTPCheckWithAnIntervalReadsInFull() throws {
        let backend = HAProxyBackend(try dict("""
        {"name": "backend_chat.example.nu", "check_type": "HTTP", "check_interval": "5000",
         "servers": [{"name": "app003", "address": "172.16.1.143", "port": "3000", "enabled": true}]}
        """))
        XCTAssertEqual(backend.checkDescription, "HTTP · every 5000ms")
    }

    func testAnUncheckedBackendIsFlagged() throws {
        // The condition worth surfacing: HAProxy keeps sending traffic to
        // these servers whether they answer or not.
        let backend = HAProxyBackend(try dict("""
        {"name": "backend_legacy", "check_type": "none",
         "servers": [{"name": "old", "address": "10.0.0.9", "port": "80", "enabled": true}]}
        """))
        XCTAssertFalse(backend.isMonitored)
        XCTAssertEqual(backend.health, .warn)
        XCTAssertEqual(backend.checkDescription, "no health check")
    }

    func testAnEmptyBackendIsIdleRatherThanUnchecked() throws {
        let backend = HAProxyBackend(try dict(#"{"name": "backend_empty", "check_type": ""}"#))
        XCTAssertEqual(backend.health, .idle)
    }

    func testServerEndpointAndTLS() throws {
        let server = HAProxyServer(try dict("""
        {"name": "ap001", "address": "172.16.1.10", "port": "443",
         "enabled": true, "ssl": true}
        """))
        XCTAssertEqual(server.endpoint, "172.16.1.10:443")
        XCTAssertTrue(server.ssl)
    }

    func testFrontendBindsComeFromAList() throws {
        // `extaddr` is a single field that holds nothing once more than one
        // address is possible; every frontend read as having no bind.
        let frontend = HAProxyFrontend(try dict("""
        {"name": "frontend-wan_1-https", "status": "active", "type": "http",
         "binds": ["wan_ipv4:443 ssl", "wan_ipv4:8443"], "acl_count": 12, "backend": ""}
        """))
        XCTAssertEqual(frontend.bindDescription, "wan_ipv4:443 ssl, wan_ipv4:8443")
        XCTAssertTrue(frontend.enabled)
    }

    func testAFrontendWithNoDefaultBackendRoutesByACL() throws {
        let frontend = HAProxyFrontend(try dict("""
        {"name": "frontend-http", "status": "active", "type": "http",
         "binds": [], "acl_count": 35, "backend": ""}
        """))
        XCTAssertEqual(frontend.routingDescription, "35 ACL rules")
        XCTAssertEqual(frontend.bindDescription, "no bind address")
    }

    func testADefaultBackendWinsOverACLCount() throws {
        let frontend = HAProxyFrontend(try dict("""
        {"name": "f", "status": "active", "binds": [], "acl_count": 3,
         "backend": "backend_www.example.se"}
        """))
        XCTAssertEqual(frontend.routingDescription, "backend_www.example.se")
    }
}

/// Package version checking, which is the one call that goes to the network.
final class PackageUpdateTests: XCTestCase {

    private func dict(_ json: String) throws -> JSONDict {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        return try XCTUnwrap(JSONDict(value))
    }

    func testAnUpdateIsFlaggedWhenVersionsDiffer() throws {
        let pkg = PackageInfo(try dict("""
        {"name": "acme", "descr": "ACME", "installed_version": "1.3.2",
         "latest_version": "1.4.0", "update_available": true}
        """))
        XCTAssertTrue(pkg.updateAvailable)
        XCTAssertEqual(pkg.versionLine, "1.3.2 → 1.4.0")
        XCTAssertEqual(pkg.health, .warn)
    }

    func testMatchingVersionsAreNotAnUpdate() throws {
        let pkg = PackageInfo(try dict("""
        {"name": "acme", "installed_version": "1.3.2", "latest_version": "1.3.2",
         "update_available": false}
        """))
        XCTAssertFalse(pkg.updateAvailable)
        XCTAssertEqual(pkg.versionLine, "1.3.2")
    }

    func testTheConfigurationListNeverClaimsAnUpdate() throws {
        // Read from $config, where both versions are the installed one. It must
        // not imply it has checked anything — saying "up to date" without
        // asking the repository is worse than saying nothing.
        let pkg = PackageInfo(try dict("""
        {"name": "haproxy", "installed_version": "0.64", "latest_version": "0.64",
         "update_available": false}
        """))
        XCTAssertFalse(pkg.updateAvailable)
    }

    func testTheSnippetOnlyRunsWhereTheFunctionExists() {
        // Calling a missing function raises an error pfSense keeps as a
        // permanent notice, so the guard is the whole design.
        let script = PHPSnippet.packageUpdates.script
        XCTAssertTrue(script.contains("function_exists(\"get_pkg_info\")"))
        XCTAssertTrue(script.contains("file_exists(\"/etc/inc/pkg-utils.inc\")"))
        XCTAssertTrue(script.contains("\"available\" => $available"))
        XCTAssertTrue(script.contains("\"update_name\" => strval($item[\"name\"])"))
    }
}

extension PackageUpdateTests {

    func testDescriptionsAreStrippedOfMarkup() throws {
        // Manifests carry <br /> and hard line breaks. pfBlockerNG's runs to
        // six lines, which renders as literal tags in a one-line summary.
        let pkg = PackageInfo(try dict("""
        {"name": "pfBlockerNG", "installed_version": "3.2.17_1",
         "descr": "Manage IPv4/v6 List Sources.<br />\\nGeoIP database by MaxMind.<br />\\nDe-Duplication."}
        """))
        let descr = try XCTUnwrap(pkg.descr)
        XCTAssertFalse(descr.contains("<br"))
        XCTAssertFalse(descr.contains("\n"))
        XCTAssertFalse(descr.contains("  "))
        XCTAssertEqual(descr, "Manage IPv4/v6 List Sources. GeoIP database by MaxMind. De-Duplication.")
    }

    func testTheRepositoryVersionDrivesTheFlag() throws {
        // What the firewall reported for every package: same version both
        // sides, so nothing is flagged and no alert fires.
        let current = [
            ("acme", "1.3.2", "1.3.2"),
            ("haproxy", "0.65.7", "0.65.7"),
            ("WireGuard", "0.2.13_4", "0.2.13_4"),
        ].map { name, installed, latest in
            PackageInfo(try! dict("""
            {"name": "\(name)", "installed_version": "\(installed)",
             "latest_version": "\(latest)", "update_available": false}
            """))
        }
        XCTAssertTrue(current.allSatisfy { !$0.updateAvailable })
        XCTAssertTrue(current.allSatisfy { $0.health == .ok })
    }
}
