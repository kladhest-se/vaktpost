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
        // The announced hostname wins over the description now: it is what the
        // device is called on the network and what every other tool shows. The
        // description is still carried and appears on the detail sheet.
        XCTAssertEqual(clients[0].name, "BRW001122")
        XCTAssertEqual(clients[0].descr, "Office printer")
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

/// Naming, which is most of what the Clients list is for.
final class ClientNamingTests: XCTestCase {

    private func dict(_ raw: [String: Any]) -> JSONDict {
        let data = try! JSONSerialization.data(withJSONObject: raw)
        return JSONDict(try! JSONDecoder().decode(JSONValue.self, from: data))!
    }

    private func arp(ip: String, mac: String, hostname: String) -> ARPEntry {
        ARPEntry(dict(["ip-address": ip, "mac-address": mac, "hostname": hostname,
                       "interface": "lagg0.100"]))
    }

    func testQuestionMarkIsNotAHostname() {
        // system_get_arp_table writes "?" when the reverse lookup fails, which
        // on a LAN without internal DNS is nearly every entry — so the client
        // list showed ninety-seven devices all called "?".
        XCTAssertNil(NetworkClient.usableHostname("?"))
        XCTAssertNil(NetworkClient.usableHostname(""))
        XCTAssertNil(NetworkClient.usableHostname("  "))
        XCTAssertEqual(NetworkClient.usableHostname("nas001"), "nas001")
    }

    func testUnresolvedClientFallsBackToItsAddress() {
        let clients = NetworkClient.merge(
            leases: [], arp: [arp(ip: "172.16.1.141", mac: "6e:71:f1:fb:78:61", hostname: "?")],
            statics: []
        )
        XCTAssertEqual(clients.first?.name, "172.16.1.141")
    }

    func testHostOverrideNamesAnOtherwiseAnonymousClient() {
        let override = HostOverride(dict([
            "host": "nas001", "domain": "example.se", "ip": "172.16.1.141",
            "descr": "Storage", "source": "unbound",
        ]))
        let clients = NetworkClient.merge(
            leases: [], arp: [arp(ip: "172.16.1.141", mac: "6e:71:f1:fb:78:61", hostname: "?")],
            statics: [], overrides: [override]
        )
        XCTAssertEqual(clients.first?.name, "nas001.example.se")
    }

    func testAHostOverrideOutranksAStaticMappingDescription() {
        // Someone typed the description by hand against this exact device.
        let override = HostOverride(dict(["host": "generic", "domain": "lan",
                                          "ip": "172.16.1.50"]))
        let mapping = StaticMapping(dict(["mac": "aa:bb:cc:dd:ee:ff",
                                          "ipaddr": "172.16.1.50",
                                          "descr": "Office printer"]))
        let clients = NetworkClient.merge(
            leases: [], arp: [arp(ip: "172.16.1.50", mac: "aa:bb:cc:dd:ee:ff", hostname: "?")],
            statics: [mapping], overrides: [override]
        )
        // Reversed deliberately: a DNS host override outranks a hand-typed
        // description, because it is the name resolvable from anywhere else on
        // the network.
        XCTAssertEqual(clients.first?.name, "generic.lan")
    }

    func testOverrideWithNoDomainIsJustTheHost() {
        let override = HostOverride(dict(["host": "printer", "domain": "", "ip": "10.0.0.5"]))
        XCTAssertEqual(override.fqdn, "printer")
        XCTAssertTrue(override.isUsable)
    }

    func testAnOverrideWithNoAddressIsIgnored() {
        XCTAssertFalse(HostOverride(dict(["host": "orphan", "domain": "lan"])).isUsable)
    }

    func testThePrimaryEntryBeatsItsOwnAliases() {
        // The snippet emits aliases after the entry they belong to, and both
        // carry the same address.
        let primary = HostOverride(dict(["host": "nas001", "domain": "lan", "ip": "10.0.0.9"]))
        let alias = HostOverride(dict(["host": "storage", "domain": "lan", "ip": "10.0.0.9"]))
        let clients = NetworkClient.merge(
            leases: [], arp: [arp(ip: "10.0.0.9", mac: "11:22:33:44:55:66", hostname: "?")],
            statics: [], overrides: [primary, alias]
        )
        XCTAssertEqual(clients.first?.name, "nas001.lan")
    }
}

/// Naming from firewall aliases, using the shapes on a real firewall.
final class AliasNamingTests: XCTestCase {

    private func dict(_ raw: [String: Any]) -> JSONDict {
        let data = try! JSONSerialization.data(withJSONObject: raw)
        return JSONDict(try! JSONDecoder().decode(JSONValue.self, from: data))!
    }

    private func alias(_ name: String, _ addresses: [String],
                       descr: String? = nil, type: String = "host") -> FirewallAliasEntry {
        var raw: [String: Any] = ["name": name, "type": type, "address": addresses]
        if let descr { raw["descr"] = descr }
        return FirewallAliasEntry(dict(raw))
    }

    private func arp(ip: String, mac: String) -> ARPEntry {
        ARPEntry(dict(["ip-address": ip, "mac-address": mac, "hostname": "?"]))
    }

    func testAHostAliasNamesTheClient() {
        let clients = NetworkClient.merge(
            leases: [], arp: [arp(ip: "172.16.1.141", mac: "aa:bb:cc:dd:ee:01")],
            statics: [], overrides: [],
            aliases: [alias("alias_host_app001", ["172.16.1.141"])]
        )
        // The alias no longer titles a client — it is filing, not identity,
        // and an address at least says where the device is. It is still
        // carried, and the detail sheet shows it.
        XCTAssertEqual(clients.first?.name, "172.16.1.141")
        XCTAssertEqual(clients.first?.aliasName, "alias_host_app001")
    }

    func testADescriptionBeatsTheAliasName() {
        let clients = NetworkClient.merge(
            leases: [], arp: [arp(ip: "192.168.202.70", mac: "aa:bb:cc:dd:ee:02")],
            statics: [], overrides: [],
            aliases: [alias("alias_host_govee_h7025", ["192.168.202.70"],
                            descr: "Govee H7025 lights")]
        )
        XCTAssertEqual(clients.first?.name, "192.168.202.70")
        XCTAssertEqual(clients.first?.aliasName, "Govee H7025 lights")
    }

    func testTheMostSpecificAliasWins() {
        // 172.16.1.50 is its own host alias and also one of six in a group.
        // The single-address one names the device; the group is something it
        // belongs to.
        let names = NetworkClient.aliasNamesByIP([
            alias("alias_host_apple_homekit",
                  ["172.16.1.50", "172.16.1.51", "172.16.1.52",
                   "172.16.1.53", "172.16.1.54", "172.16.1.55"]),
            alias("alias_host_hub", ["172.16.1.50"]),
        ])
        XCTAssertEqual(names["172.16.1.50"], "alias_host_hub")
        // The others keep the group name, which is better than nothing.
        XCTAssertEqual(names["172.16.1.51"], "alias_host_apple_homekit")
    }

    func testNestedAliasesAreNotAddresses() {
        // alias_host_nas_hyperbackup holds the names of four other aliases.
        let names = NetworkClient.aliasNamesByIP([
            alias("alias_host_nas_hyperbackup",
                  ["alias_host_nas001_kak", "alias_host_nas001_etu",
                   "alias_host_nas002", "alias_host_nas003"]),
        ])
        XCTAssertTrue(names.isEmpty)
    }

    func testSubnetsAndRangesNameNoDevice() {
        XCTAssertFalse(NetworkClient.isSingleAddress("172.16.1.0/24"))
        XCTAssertFalse(NetworkClient.isSingleAddress("172.16.1.10-172.16.1.20"))
        XCTAssertFalse(NetworkClient.isSingleAddress("alias_host_nas002"))
        XCTAssertTrue(NetworkClient.isSingleAddress("172.16.1.141"))
        XCTAssertTrue(NetworkClient.isSingleAddress("172.16.1.141/32"))
        XCTAssertTrue(NetworkClient.isSingleAddress("fe80::1"))
    }

    func testPortAliasesAreIgnored() {
        let names = NetworkClient.aliasNamesByIP([
            alias("alias_port_web", ["443"], type: "port"),
        ])
        XCTAssertTrue(names.isEmpty)
    }

    func testAHostOverrideOutranksAnAlias() {
        // A DNS name is what the device is actually called on the network; an
        // alias is what a firewall rule calls it.
        let override = HostOverride(dict(["host": "app001", "domain": "example.se",
                                          "ip": "172.16.1.141"]))
        let clients = NetworkClient.merge(
            leases: [], arp: [arp(ip: "172.16.1.141", mac: "aa:bb:cc:dd:ee:03")],
            statics: [], overrides: [override],
            aliases: [alias("alias_host_app001", ["172.16.1.141"])]
        )
        XCTAssertEqual(clients.first?.name, "app001.example.se")
    }
}

/// ARP rows, which are the same devices the Clients tab shows.
final class ARPDisplayTests: XCTestCase {

    private func dict(_ raw: [String: Any]) -> JSONDict {
        let data = try! JSONSerialization.data(withJSONObject: raw)
        return JSONDict(try! JSONDecoder().decode(JSONValue.self, from: data))!
    }

    func testExpiryReadsAsADuration() {
        // The raw value is a count of seconds. "1181" tells nobody anything.
        func expiry(_ seconds: Int) -> String? {
            ARPEntry(dict(["ip-address": "10.0.0.1", "mac-address": "a", "expires": seconds]))
                .expiryDescription
        }
        XCTAssertEqual(expiry(1181), "19m")
        XCTAssertEqual(expiry(45), "45s")
        XCTAssertEqual(expiry(7_400), "2h 3m")
        XCTAssertEqual(expiry(0), "expired")
    }

    func testAPermanentEntryHasNoExpiry() {
        XCTAssertNil(ARPEntry(dict(["ip-address": "10.0.0.1", "mac-address": "a"])).expiryDescription)
    }

    func testUnresolvedARPHostnameIsNotShown() {
        // Same "?" the Clients tab already filters. A device should not be
        // called "?" on one screen and by its alias on another.
        let entry = ARPEntry(dict(["ip-address": "172.16.1.31", "mac-address": "00:11:32:c1:73:88",
                                   "hostname": "?", "interface": "lagg0.100"]))
        XCTAssertNil(NetworkClient.usableHostname(entry.hostname ?? ""))
    }
}

/// Which name wins, and what the detail sheet keeps.
final class ClientNamePriorityTests: XCTestCase {

    private func dict(_ raw: [String: Any]) -> JSONDict {
        let data = try! JSONSerialization.data(withJSONObject: raw)
        return JSONDict(try! JSONDecoder().decode(JSONValue.self, from: data))!
    }

    private func client(hostname: String?, descr: String?,
                        override: String?, alias: String?) -> NetworkClient {
        var c = NetworkClient.merge(
            leases: [],
            arp: [ARPEntry(dict(["ip-address": "172.16.1.41", "mac-address": "62:6e:4a:6b:4b:53",
                                 "hostname": hostname ?? "?"]))],
            statics: []
        ).first!
        c.descr = descr
        c.overrideName = override
        c.aliasName = alias
        return c
    }

    func testDNSNameOutranksEverything() {
        // What the device is called on the network, and what every other tool
        // will show. An alias is filing, not identity.
        let c = client(hostname: "srv001", descr: "Server 1",
                       override: "srv001.example.se", alias: "alias_host_srv001")
        XCTAssertEqual(c.name, "srv001.example.se")
        XCTAssertEqual(c.nameSource, "DNS host override")
    }

    func testAnnouncedHostnameBeatsAliasAndDescription() {
        let c = client(hostname: "Bathroom-2-HomePod-Mini", descr: "HomePod",
                       override: nil, alias: "alias_host_homepod")
        XCTAssertEqual(c.name, "Bathroom-2-HomePod-Mini")
    }

    func testAnAddressIsShownRatherThanAnAlias() {
        let c = client(hostname: nil, descr: nil, override: nil, alias: "alias_host_srv001")
        XCTAssertEqual(c.name, "172.16.1.41")
        XCTAssertEqual(c.aliasName, "alias_host_srv001")
    }

    func testTheAddressIsTheLastResort() {
        let c = client(hostname: nil, descr: nil, override: nil, alias: nil)
        XCTAssertEqual(c.name, "172.16.1.41")
        XCTAssertEqual(c.nameSource, "no DNS name — showing address")
    }

    func testEveryNameSurvivesOnTheDetailSheet() {
        // Ranking one above the others must not discard the rest — the alias
        // is what you would search a firewall rule for.
        let c = client(hostname: "srv001", descr: "Server 1",
                       override: "srv001.example.se", alias: "alias_host_srv001")
        let sources = c.knownNames.map(\.source)
        XCTAssertEqual(sources, ["DNS name", "Hostname", "Description", "Firewall alias"])
        XCTAssertEqual(c.knownNames.last?.value, "alias_host_srv001")
    }
}

/// Alias expansion, which has to cope with aliases containing aliases.
@MainActor
final class AliasExpansionTests: XCTestCase {

    private func dict(_ raw: [String: Any]) -> JSONDict {
        let data = try! JSONSerialization.data(withJSONObject: raw)
        return JSONDict(try! JSONDecoder().decode(JSONValue.self, from: data))!
    }

    private func alias(_ name: String, _ members: String) -> FirewallAliasEntry {
        FirewallAliasEntry(dict(["name": name, "type": "host", "address": members]))
    }

    private func store(_ aliases: [FirewallAliasEntry]) -> DashboardStore {
        let s = DashboardStore(registry: ServerRegistry(
            defaults: UserDefaults(suiteName: "vaktpost.tests.\(UUID().uuidString)")!))
        s.aliases = aliases
        return s
    }

    func testAFlatAliasResolvesToItsMembers() {
        let s = store([alias("alias_host_app001", "172.16.1.141")])
        XCTAssertEqual(s.resolveAlias("alias_host_app001"), ["172.16.1.141"])
    }

    func testNestedAliasesAreFlattened() {
        // The real one: alias_host_nas_hyperbackup holds four other aliases,
        // so a rule using it says nothing without following all four.
        let s = store([
            alias("alias_host_nas_hyperbackup",
                  "alias_host_nas001 alias_host_nas002 alias_host_nas003"),
            alias("alias_host_nas001", "172.16.1.31"),
            alias("alias_host_nas002", "172.16.1.32"),
            alias("alias_host_nas003", "172.16.1.33"),
        ])
        XCTAssertEqual(s.resolveAlias("alias_host_nas_hyperbackup"),
                       ["172.16.1.31", "172.16.1.32", "172.16.1.33"])
    }

    func testADuplicateHostAppearsOnce() {
        // Two nested aliases often share a host; listing it twice reads as a
        // mistake in the rule.
        let s = store([
            alias("group", "a b"),
            alias("a", "10.0.0.1"),
            alias("b", "10.0.0.1"),
        ])
        XCTAssertEqual(s.resolveAlias("group"), ["10.0.0.1"])
    }

    func testACycleTerminates() {
        // pfSense does not forbid one, and a stack overflow is a poor way to
        // render a firewall rule.
        let s = store([alias("a", "b"), alias("b", "a")])
        XCTAssertNotNil(s.resolveAlias("a"))
    }

    func testSomethingThatIsNotAnAliasReturnsNil() {
        // So a caller can tell a literal address from an alias that resolved
        // to nothing, and not label "172.16.1.1" as an expansion of itself.
        let s = store([alias("a", "10.0.0.1")])
        XCTAssertNil(s.resolveAlias("172.16.1.1"))
    }

    func testLongListsAreCappedWithAnHonestCount() {
        let members = (1...20).map { "10.0.0.\($0)" }.joined(separator: " ")
        let s = store([alias("big", members)])
        let expanded = s.expandedAlias("big", limit: 6)
        XCTAssertEqual(expanded?.contains("+14 more"), true)
    }
}

extension AliasExpansionTests {

    func testAnAddressBecomesItsMembers() {
        // What the Firewall screen shows in place of the name.
        let s = store([alias("alias_host_pms001", "172.16.1.43")])
        XCTAssertEqual(s.resolvedValue("alias_host_pms001"), "172.16.1.43")
    }

    func testAPortAliasResolvesSeparately() {
        // Address and port are resolved independently now, so a joined
        // `host:port` never has to be split — which is what made IPv6
        // impossible to handle.
        let s = store([alias("alias_port_plex", "32400")])
        XCTAssertEqual(s.resolvedValue("alias_port_plex"), "32400")
    }

    func testALiteralValueIsLeftAlone() {
        let s = store([alias("a", "10.0.0.1")])
        XCTAssertEqual(s.resolvedValue("any"), "any")
        XCTAssertEqual(s.resolvedValue("wanip"), "wanip")
        // An IPv6 address survives intact, which it did not when fields were
        // split on ":" to separate a port.
        XCTAssertEqual(s.resolvedValue("fe80::1"), "fe80::1")
    }

    func testALongListIsCappedInARuleRow() {
        // alias_url_cloudflare holds twenty-two networks; a rule row is not
        // the place for them.
        let members = (1...22).map { "10.\($0).0.0/16" }.joined(separator: " ")
        let s = store([alias("alias_url_cloudflare", members)])
        let text = s.resolvedValue("alias_url_cloudflare")
        XCTAssertTrue(text.hasSuffix("+19"))
        XCTAssertEqual(text.components(separatedBy: ", ").count, 3)
    }

    func testNestedAliasesResolveInAValue() {
        let s = store([
            alias("group", "a b"),
            alias("a", "10.0.0.1"),
            alias("b", "10.0.0.2"),
        ])
        XCTAssertEqual(s.resolvedValue("group"), "10.0.0.1, 10.0.0.2")
    }
}

/// Address and port, which used to be welded into one string.
final class FilterAddressTests: XCTestCase {

    private func value(_ raw: Any) -> JSONValue {
        let data = try! JSONSerialization.data(withJSONObject: ["v": raw])
        let dict = JSONDict(try! JSONDecoder().decode(JSONValue.self, from: data))!
        return dict.value("v")!
    }

    func testAddressAndPortStaySeparate() {
        let side = FilterAddress(value(["address": "172.16.1.43"]), port: value("32400"))
        XCTAssertEqual(side.address, "172.16.1.43")
        XCTAssertEqual(side.port, "32400")
        XCTAssertEqual(side.text, "172.16.1.43:32400")
    }

    func testAnIPv6AddressIsNotMangled() {
        // The reason for the split. Joined as `fe80::1:443`, no amount of
        // splitting on ":" gets the address back — and every rule with a v6
        // address was rendered through exactly that.
        let side = FilterAddress(value(["address": "fe80::1"]), port: value("443"))
        XCTAssertEqual(side.address, "fe80::1")
        XCTAssertEqual(side.port, "443")
    }

    func testAnyWithNoPort() {
        let side = FilterAddress(value(["any": true]))
        XCTAssertEqual(side.address, "any")
        XCTAssertNil(side.port)
        XCTAssertEqual(side.text, "any")
    }

    func testANetworkIsUsedWhenPresent() {
        let side = FilterAddress(value(["network": "lan"]))
        XCTAssertEqual(side.address, "lan")
    }

    func testAPortInsideTheObjectIsFound() {
        let side = FilterAddress(value(["address": "10.0.0.1", "port": "8080"]))
        XCTAssertEqual(side.port, "8080")
    }
}

extension FilterAddressTests {

    func testAPortForwardKeepsItsSource() {
        // The live firewall returns a `source` on every port forward; the
        // model was not reading it, and a comment asserted it did not exist.
        let raw: [String: Any] = [
            "interface": "wan",
            "protocol": "tcp",
            "source": ["any": true],
            "destination": ["network": "wanip"],
            "destination_port": "32400",
            "target": "172.16.1.43",
            "local-port": "32400",
            "descr": "Plex",
        ]
        let data = try! JSONSerialization.data(withJSONObject: raw)
        let pf = PortForward(JSONDict(try! JSONDecoder().decode(JSONValue.self, from: data))!)

        XCTAssertEqual(pf.sourceSide.address, "any")
        XCTAssertEqual(pf.destinationSide.address, "wanip")
        XCTAssertEqual(pf.destinationSide.port, "32400")
        XCTAssertEqual(pf.target, "172.16.1.43")
    }

    func testARestrictedSourceSurvives() {
        let raw: [String: Any] = [
            "interface": "wan",
            "source": ["address": "203.0.113.7"],
            "destination": ["network": "wanip"],
            "target": "172.16.1.43",
            "descr": "Restricted",
        ]
        let data = try! JSONSerialization.data(withJSONObject: raw)
        let pf = PortForward(JSONDict(try! JSONDecoder().decode(JSONValue.self, from: data))!)
        XCTAssertEqual(pf.sourceSide.address, "203.0.113.7")
    }
}

/// Searching the client list.
final class ClientSearchTests: XCTestCase {

    private func client(_ raw: [String: Any]) -> NetworkClient {
        let data = try! JSONSerialization.data(withJSONObject: raw)
        let dict = JSONDict(try! JSONDecoder().decode(JSONValue.self, from: data))!
        return NetworkClient(lease: DHCPLease(dict))
    }

    func testEveryKnownNameIsSearchable() {
        // A device titled by its DNS override is still findable by the
        // description on its static mapping — the title is a ranking, not the
        // only name the firewall has for it.
        var device = client(["ip": "172.16.1.31", "mac": "00:11:32:c1:73:88"])
        device.overrideName = "nas001.example.se"
        device.descr = "Backup target"

        let names = device.knownNames.map { $0.value.lowercased() }
        XCTAssertTrue(names.contains { $0.contains("backup") })
        XCTAssertTrue(names.contains { $0.contains("nas001") })
    }

    func testAnEmptyNameIsNotOffered() {
        // An empty description would match every query as a substring.
        var device = client(["ip": "172.16.1.31", "mac": "aa:bb:cc:dd:ee:ff"])
        device.descr = ""
        XCTAssertFalse(device.knownNames.contains { $0.value.isEmpty })
    }
}
