import XCTest
@testable import Vaktpost

/// The matching is the part of this feature with all the mistakes in it, and
/// it is a pure function over arrays specifically so it can be tested without
/// a firewall.
///
/// The failure that matters is not "missed a result" — it is a *wrong* result.
/// A search that says a rule applies to a device when it does not is worse
/// than one that finds nothing, because the whole point is to stop somebody
/// checking five screens by hand.
final class InvestigationTests: XCTestCase {

    private func decode<T>(_ raw: [String: Any], _ make: (JSONDict) -> T) -> T {
        let data = try! JSONSerialization.data(withJSONObject: raw)
        let value = try! JSONDecoder().decode(JSONValue.self, from: data)
        return make(JSONDict(value)!)
    }

    private func arp(ip: String, mac: String) -> ARPEntry {
        decode(["ip": ip, "mac": mac, "interface": "lagg0.100"], ARPEntry.init)
    }

    private func alias(_ name: String, _ addresses: [String]) -> FirewallAliasEntry {
        decode(["name": name, "type": "network", "address": addresses.joined(separator: " ")],
               FirewallAliasEntry.init)
    }

    private func rule(source: String, destination: String, descr: String = "",
                      destinationPort: String? = nil) -> FirewallRule {
        var raw: [String: Any] = ["interface": "lan", "type": "pass", "descr": descr,
                                  "source": ["address": source],
                                  "destination": ["address": destination]]
        if let destinationPort {
            raw["destination"] = ["address": destination, "port": destinationPort]
        }
        return decode(raw, FirewallRule.init)
    }

    private func find(_ query: String,
                      arp: [ARPEntry] = [], aliases: [FirewallAliasEntry] = [],
                      rules: [FirewallRule] = []) -> [Investigation.Finding] {
        guard let subject = Investigation.subject(query) else { return [] }
        return Investigation.findings(for: subject, in: Investigation.Sources(
            clients: [], arp: arp, leases: [],
            staticMappings: [], hostOverrides: [], aliases: aliases,
            rules: rules, portForwards: [], openvpnServers: [],
            wireguardPeers: [], dnsblClients: []
        ))
    }

    // MARK: Classifying the query

    func testAnAddressIsRecognisedAsOne() {
        XCTAssertEqual(Investigation.subject("172.16.1.32"), .address("172.16.1.32"))
        XCTAssertEqual(Investigation.subject("2001:db8::1"), .address("2001:db8::1"))
    }

    func testAMACIsRecognisedAsOne() {
        XCTAssertEqual(Investigation.subject("AC:10:01:01:02:03"), .mac("ac:10:01:01:02:03"))
        XCTAssertFalse(Investigation.isMAC("ac:10:01:01:02"), "five octets is not a MAC")
        XCTAssertFalse(Investigation.isMAC("zz:10:01:01:02:03"), "nor is one with non-hex in it")
    }

    func testHyphenAndCiscoMACFormatsAreRecognised() {
        XCTAssertEqual(Investigation.subject("AC-10-01-01-02-03"), .mac("ac-10-01-01-02-03"))
        XCTAssertEqual(Investigation.subject("AC10.0101.0203"), .mac("ac10.0101.0203"))
        XCTAssertFalse(Investigation.isMAC("ac-10-01-01-02"))
        XCTAssertFalse(Investigation.isMAC("AC10.010.0203"))
    }

    func testAnythingElseIsText() {
        XCTAssertEqual(Investigation.subject("nas001"), .text("nas001"))
    }

    func testASingleCharacterIsNotASearch() {
        // Everything matches one character, and a screen of everything is not
        // an answer.
        XCTAssertNil(Investigation.subject("1"))
        XCTAssertNil(Investigation.subject(" "))
    }

    // MARK: Addresses match exactly, not textually

    func testAPrefixOfAnAddressIsNotThatAddress() {
        // The mistake a substring search makes: "10.0.0.1" inside "10.0.0.100".
        // Reporting the wrong host's firewall rules is worse than reporting
        // none.
        let hits = find("10.0.0.1", arp: [arp(ip: "10.0.0.100", mac: "aa:bb:cc:dd:ee:01")])
        XCTAssertTrue(hits.isEmpty)
    }

    func testEquivalentSpellingsOfOneAddressMatch() {
        let hits = find("2001:db8::1", arp: [arp(ip: "2001:db8:0:0:0:0:0:1", mac: "aa:bb:cc:dd:ee:02")])
        XCTAssertEqual(hits.count, 1)
    }

    func testAnAddressInsideAListOfThemMatches() {
        // Firewall fields hold lists, so comparing whole fields would miss
        // nearly everything a rule actually says.
        let hits = find("10.0.0.5", rules: [rule(source: "10.0.0.4 10.0.0.5", destination: "any")])
        XCTAssertEqual(hits.count, 1)
    }

    func testASingleHostPrefixIsThatHost() {
        // A rule naming 10.253.21.10/32 is about that host, and WireGuard
        // writes its allowed IPs that way.
        let hits = find("10.253.21.10", rules: [rule(source: "10.253.21.10/32", destination: "any")])
        XCTAssertEqual(hits.count, 1)
    }

    func testASubnetIsNotClaimedToContainTheAddress() {
        // This does no subnet arithmetic and must not appear to. Saying a
        // /24 rule applies would be a guess dressed as a result.
        let hits = find("10.0.0.5", rules: [rule(source: "10.0.0.0/24", destination: "any")])
        XCTAssertTrue(hits.isEmpty)
    }

    func testARuleWithAPortStillMatchesItsAddress() {
        // `FilterAddress.text` renders "10.0.0.5:443" for display, so matching
        // against it fails on exactly the rules most worth finding — the ones
        // specific enough to name a port.
        let hits = find("10.0.0.5",
                        rules: [rule(source: "any", destination: "10.0.0.5",
                                     destinationPort: "443")])
        XCTAssertEqual(hits.count, 1)
    }

    // MARK: The reason this feature is worth having

    func testARuleIsFoundThroughAnAliasThatContainsTheAddress() {
        // The answer nothing else in the app gives: which of my rules actually
        // applies to this device. A rule names an alias, the alias holds the
        // address, and neither screen alone makes the connection.
        let hits = find("172.16.1.32",
                        aliases: [alias("SERVERS", ["172.16.1.32", "172.16.1.33"])],
                        rules: [rule(source: "SERVERS", destination: "any", descr: "Servers out")])

        XCTAssertEqual(hits.filter { $0.kind == .alias }.count, 1)
        let ruleHit = hits.first { $0.kind == .rule }
        XCTAssertNotNil(ruleHit)
        XCTAssertEqual(ruleHit?.via, "via alias SERVERS", "a result has to say why it matched")
    }

    func testAnAliasThatDoesNotContainTheAddressDragsNoRulesIn() {
        let hits = find("172.16.1.99",
                        aliases: [alias("SERVERS", ["172.16.1.32"])],
                        rules: [rule(source: "SERVERS", destination: "any")])
        XCTAssertTrue(hits.isEmpty)
    }

    func testMatchingAnAliasByNameAlsoFindsItsRules() {
        let hits = find("SERVERS",
                        aliases: [alias("SERVERS", ["172.16.1.32"])],
                        rules: [rule(source: "SERVERS", destination: "any")])
        XCTAssertEqual(hits.filter { $0.kind == .rule }.count, 1)
    }

    // MARK: Identity

    func testFindingsHaveUniqueIdentifiers() {
        // ForEach over duplicate ids is undefined behaviour, and these ids are
        // built from firewall data this app does not control.
        let hits = find("172.16.1.32",
                        arp: [arp(ip: "172.16.1.32", mac: "aa:bb:cc:dd:ee:03")],
                        aliases: [alias("A", ["172.16.1.32"]), alias("B", ["172.16.1.32"])],
                        rules: [rule(source: "A", destination: "any", descr: "one"),
                                rule(source: "B", destination: "any", descr: "two")])
        XCTAssertEqual(Set(hits.map(\.id)).count, hits.count)
    }
}
