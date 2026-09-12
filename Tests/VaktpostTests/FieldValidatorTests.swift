import XCTest
@testable import Vaktpost

/// Nothing validated these fields before. They went from a text field to
/// `write_config`, so pfSense was the first thing to find out about a typo —
/// and a rule pfSense refuses to load is a rule enforcing nothing while the app
/// says "saved".
///
/// The failure to guard against is the *accepted* bad value, not the rejected
/// good one: a rule that loads and matches nothing is worse than one that fails
/// loudly, because nobody goes looking for it.
/// The payload encoding is tested here too, because it is the thing standing
/// between a text field and `write_config` and it has no other home yet.
final class PayloadEncodingTests: XCTestCase {

    private func decoded(_ dict: JSONDict) -> [String: Any]? {
        let encoded = PHPSnippet.payload(dict)
        guard let data = Data(base64Encoded: encoded) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    func testThePayloadIsBase64AndNothingElse() {
        // The whole safety argument. Base64's alphabet cannot terminate a PHP
        // string literal, so the snippet text stays what was reviewed whatever
        // somebody types into the editor.
        let hostile = "a\" ; system(\"rm -rf /\") ; $x = \"'"
        let encoded = PHPSnippet.payload(JSONDict(["descr": .string(hostile)]))

        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=")
        XCTAssertFalse(encoded.isEmpty)
        XCTAssertTrue(encoded.unicodeScalars.allSatisfy { allowed.contains($0) },
                      "a payload that can contain a quote is a payload that can end a string")
    }

    func testAHostileDescriptionSurvivesIntactRatherThanBeingMangled() {
        // Encoding is not sanitising. The value has to arrive exactly as typed
        // — somebody's rule description may legitimately contain a quote.
        let hostile = "web \"prod\" ; drop $all \\ done"
        let round = decoded(JSONDict(["descr": .string(hostile)]))
        XCTAssertEqual(round?["descr"] as? String, hostile)
    }

    func testNestedValuesAndTypesRoundTrip() {
        let payload = JSONDict([
            "tracker": .string("1700000000"),
            "disabled": .bool(true),
            "source": .object(["address": .string("any")]),
            "ports": .array([.string("80"), .string("443")])
        ])
        let round = decoded(payload)
        XCTAssertEqual(round?["tracker"] as? String, "1700000000")
        XCTAssertEqual(round?["disabled"] as? Bool, true)
        XCTAssertEqual((round?["source"] as? [String: Any])?["address"] as? String, "any")
        XCTAssertEqual((round?["ports"] as? [Any])?.count, 2)
    }

    func testNullIsEncodedRatherThanDropped() {
        // A key that vanishes and a key that is null mean different things to
        // pfSense. The snippet decides what to drop, not the encoder.
        let round = decoded(JSONDict(["ipprotocol": .null]))
        XCTAssertTrue(round?.keys.contains("ipprotocol") ?? false)
    }

    func testEveryWriteSnippetCarriesItsPayloadAsOneLiteral() {
        // If a write snippet ever interpolates something else, this is where
        // it shows up — the gate checks the file, and this checks the output.
        let snippets = [
            PHPSnippet.saveRule(rule: JSONDict(["tracker": .string("1")])),
            PHPSnippet.saveNatRule(rule: JSONDict(["target": .string("10.0.0.1")])),
            PHPSnippet.deleteRule(tracker: "1"),
            PHPSnippet.deleteNatRule(tracker: "1"),
            PHPSnippet.quickBlock(interface: "wan", address: "10.0.0.1", description: "x"),
            PHPSnippet.flushStates(interface: "wan"),
            PHPSnippet.restartService(serviceName: "dhcpd")
        ]
        for snippet in snippets {
            XCTAssertTrue(snippet.body.contains("$vaktpost_payload = \""),
                          "\(snippet.name) does not carry an encoded payload")
            XCTAssertTrue(PHPSnippet.writeOperations.contains(snippet.name),
                          "\(snippet.name) writes but is not declared")
        }
    }
}

final class FieldValidatorTests: XCTestCase {

    private let aliases: Set<String> = ["SERVERS", "WEB_PORTS"]

    private func problem(_ text: String, _ kind: FieldValidator.Kind) -> String? {
        FieldValidator.problem(in: text, kind: kind, field: "f", aliases: aliases)?.message
    }

    // MARK: Addresses

    func testOrdinaryAddressesPass() {
        XCTAssertNil(problem("172.16.1.32", .address))
        XCTAssertNil(problem("2001:db8::1", .address))
        XCTAssertNil(problem("10.0.0.0/24", .address))
        XCTAssertNil(problem("2001:db8::/64", .address))
        XCTAssertNil(problem("any", .address))
        XCTAssertNil(problem("  172.16.1.32  ", .address), "a pasted address keeps its spaces")
    }

    func testAnOctetOverTwoFiveFiveIsRejected() {
        // The example everybody uses, and it reached the firewall.
        XCTAssertNotNil(problem("10.0.0.256", .address))
    }

    func testAddressesThatAreNearlyRightAreRejected() {
        XCTAssertNotNil(problem("10.0.0", .address))
        XCTAssertNotNil(problem("10.0.0.1.1", .address))
        XCTAssertNotNil(problem("10.0.0.", .address))
        XCTAssertNotNil(problem("10.0.0.-1", .address))
        // `Int("+1")` is 1, so a permissive parse takes this.
        XCTAssertNotNil(problem("10.0.0.+1", .address))
    }

    func testAPrefixMustFitItsFamily() {
        XCTAssertNotNil(problem("10.0.0.0/33", .address))
        XCTAssertNotNil(problem("2001:db8::/129", .address))
        XCTAssertNil(problem("10.0.0.1/32", .address))
    }

    func testAnEmptyAddressIsRejectedRatherThanTreatedAsAny() {
        // pfSense would take it and the rule would not do what was meant.
        XCTAssertNotNil(problem("", .address))
    }

    // MARK: Aliases

    func testAnAliasThatExistsPasses() {
        XCTAssertNil(problem("SERVERS", .address))
        XCTAssertNil(problem("WEB_PORTS", .port))
    }

    func testAnAliasThatDoesNotExistIsRejected() {
        // The likeliest typo in the editor and the worst one: it looks
        // entirely correct, pfSense accepts the rule, and the rule matches
        // nothing for as long as nobody checks.
        XCTAssertEqual(problem("SERVER", .address),
                       "No alias called \"SERVER\" on this firewall.")
    }

    func testAnAliasNameCannotStartWithADigit() {
        XCTAssertNotNil(problem("1SERVERS", .address))
    }

    // MARK: Ports

    func testPortsAndRangesPass() {
        XCTAssertNil(problem("443", .port))
        XCTAssertNil(problem("8000-8100", .port))
        XCTAssertNil(problem("", .port), "empty means any, which is a normal thing to want")
    }

    func testPortsOutsideTheRangeAreRejected() {
        XCTAssertNotNil(problem("0", .port))
        XCTAssertNotNil(problem("65536", .port))
        XCTAssertNotNil(problem("-1", .port))
    }

    func testAReversedRangeIsRejected() {
        // pfSense accepts it and it matches nothing — an hour of debugging
        // that the editor can prevent in a line.
        XCTAssertNotNil(problem("8100-8000", .port))
    }

    // MARK: NAT targets

    func testATargetMustBeSomewhere() {
        XCTAssertNil(problem("172.16.1.32", .target))
        XCTAssertNil(problem("SERVERS", .target))
        XCTAssertNotNil(problem("", .target))
    }

    func testATargetCannotBeAny() {
        // Accepted by pfSense and almost never meant: it forwards to whatever
        // the packet was already addressed to.
        XCTAssertNotNil(problem("any", .target))
    }

    func testATargetCannotBeANetwork() {
        // A forward goes to one host. A /24 has no single destination.
        XCTAssertNotNil(problem("10.0.0.0/24", .target))
    }

    // MARK: Whole forms

    private func rule(source: String = "any", sourcePort: String = "",
                      destination: String = "any", destinationPort: String = "",
                      proto: String = "tcp") -> RuleEditForm {
        let raw: [String: JSONValue] = [
            "tracker": .string("1"), "interface": .string("lan"),
            "type": .string("pass"), "protocol": .string(proto),
            "source": .object(["address": .string(source)]),
            "source_port": .string(sourcePort),
            "destination": .object(["address": .string(destination)]),
            "destination_port": .string(destinationPort),
            "descr": .string("test")
        ]
        return RuleEditForm(from: FirewallRule(JSONDict(raw)))
    }

    func testAValidRuleHasNoProblems() {
        XCTAssertTrue(FieldValidator.problems(inRule: rule(destination: "SERVERS",
                                                           destinationPort: "443"),
                                              aliases: aliases).isEmpty)
    }

    func testPortsNeedAProtocolThatHasThem() {
        // pfSense will not load a rule with a port on ICMP, and the editor
        // offered both without comment.
        let problems = FieldValidator.problems(inRule: rule(destinationPort: "443", proto: "icmp"),
                                               aliases: aliases)
        XCTAssertTrue(problems.contains { $0.field == "Protocol" })
    }

    func testNoProtocolComplaintWhenThereAreNoPorts() {
        XCTAssertTrue(FieldValidator.problems(inRule: rule(proto: "icmp"),
                                              aliases: aliases).isEmpty)
    }

    func testEveryBadFieldIsReportedNotJustTheFirst() {
        // Fixing one and being told about the next is the slow way to learn
        // the form is wrong in four places.
        let problems = FieldValidator.problems(inRule: rule(source: "10.0.0.256",
                                                            sourcePort: "99999",
                                                            destination: "NOPE",
                                                            destinationPort: "8100-8000"),
                                               aliases: aliases)
        XCTAssertEqual(problems.count, 4)
    }

    // MARK: Port forwards

    private func forward(target: String = "172.16.1.32", destinationPort: String = "443",
                         localPort: String = "", proto: String = "tcp") -> PortForwardEditForm {
        let raw: [String: JSONValue] = [
            "interface": .string("wan"), "protocol": .string(proto),
            "ipprotocol": .string("inet"),
            "source": .object(["address": .string("any")]),
            "destination": .object(["address": .string("any")]),
            "destination_port": .string(destinationPort),
            "target": .string(target),
            "local_port": .string(localPort),
            "descr": .string("test")
        ]
        return PortForwardEditForm(from: PortForward(JSONDict(raw)))
    }

    func testAValidForwardHasNoProblems() {
        XCTAssertTrue(FieldValidator.problems(inForward: forward(), aliases: aliases).isEmpty)
    }

    func testAForwardWithoutATargetIsRejected() {
        XCTAssertFalse(FieldValidator.problems(inForward: forward(target: ""),
                                               aliases: aliases).isEmpty)
    }

    func testMismatchedRangesAreRejected() {
        // A range onto a range of a different size is not expressible and is
        // silently truncated, which is the kind of thing that works for the
        // first few ports and not the rest.
        let problems = FieldValidator.problems(
            inForward: forward(destinationPort: "8000-8100", localPort: "9000-9050"),
            aliases: aliases)
        XCTAssertTrue(problems.contains { $0.field == "Local port" })
    }

    func testMatchingRangesArePermitted() {
        XCTAssertTrue(FieldValidator.problems(
            inForward: forward(destinationPort: "8000-8100", localPort: "9000-9100"),
            aliases: aliases).isEmpty)
    }

    func testASingleLocalPortBehindARangeIsPermitted() {
        // pfSense's way of saying "map the range onto a range starting here".
        XCTAssertTrue(FieldValidator.problems(
            inForward: forward(destinationPort: "8000-8100", localPort: "9000"),
            aliases: aliases).isEmpty)
    }
}
