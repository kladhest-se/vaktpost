import XCTest
@testable import Vaktpost

/// Most of these assert that nothing is reported.
///
/// A warning here is shown immediately before a firewall changes, and one
/// false alarm at that moment teaches somebody to dismiss the next one.
/// Silence costs a missed hint; a wrong warning costs the warning system.
///
/// The type this replaces failed all three of the first tests below.
final class RulePlacementTests: XCTestCase {

    private func rule(_ interface: String = "lan", type: String = "pass",
                      source: String = "any", destination: String = "any",
                      destinationPort: String? = nil, proto: String? = nil,
                      family: String = "inet", disabled: Bool = false,
                      tracker: String = UUID().uuidString) -> FirewallRule {
        var raw: [String: JSONValue] = [
            "tracker": .string(tracker),
            "interface": .string(interface),
            "type": .string(type),
            "ipprotocol": .string(family),
            "disabled": .bool(disabled),
            "descr": .string(""),
            "source": .object(["address": .string(source)]),
            "destination": .object(["address": .string(destination)])
        ]
        if let destinationPort {
            raw["destination"] = .object(["address": .string(destination),
                                          "port": .string(destinationPort)])
        }
        if let proto { raw["protocol"] = .string(proto) }
        return FirewallRule(JSONDict(raw))
    }

    // MARK: The three faults in the type this replaces

    func testShadowingIsOnlyClaimedForRulesThatComeBefore() {
        // The old detector asked whether the *earlier* rule was shadowed by the
        // later one. Every finding it produced named the wrong rule.
        let specific = rule(destination: "10.0.0.5")
        let broad = rule()
        let placement = RulePlacement.analyse(specific, in: [specific, broad])
        XCTAssertTrue(placement.findings.isEmpty,
                      "a rule cannot be shadowed by one that comes after it")
    }

    func testRulesOnOtherInterfacesAreNotCompared() {
        // Fifteen interfaces of `any → any` rules that can never interact is
        // the noise that made the old type unusable.
        let wan = rule("wan")
        let lan = rule("lan")
        XCTAssertTrue(RulePlacement.analyse(lan, in: [wan, lan]).findings.isEmpty)
    }

    func testADisabledRuleShadowsNothing() {
        let off = rule(disabled: true)
        let target = rule(destination: "10.0.0.5")
        XCTAssertTrue(RulePlacement.analyse(target, in: [off, target]).findings.isEmpty)
    }

    // MARK: What it does report

    func testAnEarlierAnyRuleShadowsALaterOne() {
        let broad = rule()
        let specific = rule(destination: "10.0.0.5")
        let placement = RulePlacement.analyse(specific, in: [broad, specific])
        XCTAssertEqual(placement.findings.count, 1)
        XCTAssertEqual(placement.findings.first?.kind, .shadowed)
        XCTAssertEqual(placement.findings.first?.otherPosition, 1)
    }

    func testAnEarlierBlockContradictsALaterPass() {
        // Same coverage, opposite action. Separated from plain shadowing
        // because the traffic is being handled — just not the way this rule
        // says, which is the more alarming of the two.
        let block = rule(type: "block")
        let pass = rule(type: "pass", destination: "10.0.0.5")
        let placement = RulePlacement.analyse(pass, in: [block, pass])
        XCTAssertEqual(placement.findings.first?.kind, .contradicted)
    }

    func testAnIdenticalEarlierRuleIsADuplicate() {
        let first = rule(destination: "10.0.0.5", tracker: "a")
        let second = rule(destination: "10.0.0.5", tracker: "b")
        let placement = RulePlacement.analyse(second, in: [first, second])
        XCTAssertEqual(placement.findings.map(\.kind), [.duplicate],
                       "a duplicate is also a shadow; saying both is padding")
    }

    // MARK: What it refuses to guess

    func testASupersetNetworkIsNotReported() {
        // No subnet arithmetic. A /24 above a host inside it really does
        // shadow it, and saying so would require address maths this does not
        // do — so it says nothing rather than guessing.
        let wide = rule(destination: "10.0.0.0/24")
        let host = rule(destination: "10.0.0.5")
        XCTAssertTrue(RulePlacement.analyse(host, in: [wide, host]).findings.isEmpty)
    }

    func testDifferentPortsDoNotShadow() {
        let https = rule(destination: "10.0.0.5", destinationPort: "443", proto: "tcp")
        let ssh = rule(destination: "10.0.0.5", destinationPort: "22", proto: "tcp")
        XCTAssertTrue(RulePlacement.analyse(ssh, in: [https, ssh]).findings.isEmpty)
    }

    func testDifferentAddressFamiliesDoNotShadow() {
        let v4 = rule(family: "inet")
        let v6 = rule(destination: "2001:db8::5", family: "inet6")
        XCTAssertTrue(RulePlacement.analyse(v6, in: [v4, v6]).findings.isEmpty)
    }

    func testAnInet46RuleCoversBothFamilies() {
        let both = rule(family: "inet46")
        let v6 = rule(destination: "2001:db8::5", family: "inet6")
        XCTAssertEqual(RulePlacement.analyse(v6, in: [both, v6]).findings.count, 1)
    }

    func testEmptyAndAnyAreTheSameThing() {
        // pfSense writes an absent port as a missing key and this app reads it
        // as an empty string. Treating those as different would hide a real
        // shadow behind a spelling.
        let broad = rule(proto: nil)
        let narrow = rule(destination: "10.0.0.5", proto: "any")
        XCTAssertEqual(RulePlacement.analyse(narrow, in: [broad, narrow]).findings.count, 1)
    }

    // MARK: Position

    func testPositionIsCountedWithinTheInterface() {
        // Not the index in the whole ruleset. "Rule 40 of 98" across fifteen
        // interfaces is a number about nothing.
        let wan = rule("wan")
        let first = rule("lan", destination: "10.0.0.1")
        let second = rule("lan", destination: "10.0.0.2")
        let placement = RulePlacement.analyse(second, in: [wan, first, second])
        XCTAssertEqual(placement.position, 2)
        XCTAssertEqual(placement.proposedPosition, 2)
        XCTAssertEqual(placement.total, 2)
    }

    func testARuleNotInTheRulesetReadsAsNewAndAppended() {
        let existing = rule("lan", destination: "10.0.0.1")
        let fresh = rule("lan", destination: "10.0.0.2")
        let placement = RulePlacement.analyse(fresh, in: [existing])
        XCTAssertTrue(placement.isNew)
        XCTAssertEqual(placement.proposedPosition, 2)
        XCTAssertEqual(placement.total, 2, "it would land last")
    }

    func testEverythingBeforeANewRuleIsConsidered() {
        // A new rule is appended, so the whole interface precedes it.
        let broad = rule("lan")
        let fresh = rule("lan", destination: "10.0.0.9")
        XCTAssertEqual(RulePlacement.analyse(fresh, in: [broad]).findings.count, 1)
    }

    func testAnEmptyRulesetPlacesTheFirstRuleWithoutComplaint() {
        let only = rule("lan")
        let placement = RulePlacement.analyse(only, in: [])
        XCTAssertTrue(placement.isNew)
        XCTAssertTrue(placement.findings.isEmpty)
    }

    func testANewRuleCanBePreviewedBeforeAStableAnchor() {
        let first = rule("lan", destination: "10.0.0.1", tracker: "first")
        let second = rule("lan", destination: "10.0.0.2", tracker: "second")
        let fresh = rule("lan", destination: "10.0.0.3", tracker: "draft")
        let placement = RulePlacement.analyse(
            fresh, in: [first, second], target: .before(tracker: "second")
        )

        XCTAssertTrue(placement.isNew)
        XCTAssertEqual(placement.proposedPosition, 2)
        XCTAssertEqual(placement.total, 3)
    }

    func testMovingBeforeABroadRuleRemovesItsShadowWarning() {
        let broad = rule("lan", tracker: "broad")
        let specific = rule("lan", destination: "10.0.0.5", tracker: "specific")
        let placement = RulePlacement.analyse(
            specific, in: [broad, specific], target: .before(tracker: "broad")
        )

        XCTAssertEqual(placement.position, 2)
        XCTAssertEqual(placement.proposedPosition, 1)
        XCTAssertTrue(placement.findings.isEmpty)
    }

    func testMovingAnEarlierRuleLastPreviewsNewShadowing() {
        let specific = rule("lan", destination: "10.0.0.5", tracker: "specific")
        let broad = rule("lan", tracker: "broad")
        let placement = RulePlacement.analyse(
            specific, in: [specific, broad], target: .last
        )

        XCTAssertEqual(placement.position, 1)
        XCTAssertEqual(placement.proposedPosition, 2)
        XCTAssertEqual(placement.findings.first?.kind, .shadowed)
    }
}

/// Creating and duplicating, where the danger is that a "new" rule quietly
/// replaces an existing one instead of being added.
final class RuleCreationTests: XCTestCase {

    private func existing() -> FirewallRule {
        FirewallRule(JSONDict([
            "tracker": .string("1700000000"),
            "interface": .string("lan"),
            "type": .string("pass"),
            "descr": .string("Web"),
            "source": .object(["address": .string("any")]),
            "destination": .object(["address": .string("10.0.0.5")])
        ]))
    }

    func testANewRuleSendsNoTrackerAndAsksToCreate() {
        // The tracker is left to the firewall. One picked on the phone is
        // chosen against a ruleset fetched seconds ago, and a collision does
        // not append — it replaces whatever already held that tracker.
        let form = RuleEditForm.blank(interface: "lan")
        let dict = form.toDict(tracker: "whatever-the-caller-passed", interface: "lan")
        XCTAssertEqual(dict.string("tracker"), "")
        XCTAssertEqual(dict.bool("create"), true)
        XCTAssertEqual(dict.string("placement"), "last")
    }

    func testAnEditKeepsItsTrackerAndDoesNotAskToCreate() {
        let form = RuleEditForm(from: existing())
        let dict = form.toDict(tracker: "1700000000", interface: "lan")
        XCTAssertEqual(dict.string("tracker"), "1700000000")
        XCTAssertEqual(dict.bool("create"), false)
        XCTAssertNil(dict.string("placement"))
    }

    func testARuleCanRequestPlacementBeforeAStableTracker() {
        var form = RuleEditForm(from: existing())
        form.placementTarget = .before(tracker: "anchor-2")
        let dict = form.toDict(tracker: "1700000000", interface: "lan")

        XCTAssertEqual(dict.string("placement"), "before")
        XCTAssertEqual(dict.string("before_tracker"), "anchor-2")
    }

    func testADuplicateIsACreateRatherThanAnEdit() {
        // The failure this guards: a copy that carries the original's tracker
        // matches it and overwrites it, so "duplicate" deletes what it copied.
        let form = RuleEditForm.duplicating(existing())
        let dict = form.toDict(tracker: existing().tracker, interface: "lan")
        XCTAssertEqual(dict.string("tracker"), "")
        XCTAssertEqual(dict.bool("create"), true)
    }

    func testADuplicateIsDistinguishableFromItsOriginal() {
        // Two rules with the same description in a list of ninety-eight is how
        // somebody edits the wrong one later.
        XCTAssertEqual(RuleEditForm.duplicating(existing()).descr, "Web (copy)")
    }

    func testAnUndescribedRuleStillGetsACopyLabel() {
        let bare = JSONDict([
            "tracker": .string("1"), "interface": .string("lan"),
            "type": .string("pass"), "descr": .string(""),
            "source": .object(["address": .string("any")]),
            "destination": .object(["address": .string("any")])
        ])
        XCTAssertEqual(RuleEditForm.duplicating(FirewallRule(bare)).descr, "Copy")
    }

    func testNewAndDuplicatedRulesStartDisabled() {
        // The one thing that cannot be undone from a phone is traffic that got
        // through while a rule was being written.
        XCTAssertTrue(RuleEditForm.blank(interface: "lan").disabled)
        XCTAssertTrue(RuleEditForm.duplicating(existing()).disabled)
    }

    func testABlankRuleCarriesTheInterfaceItWasStartedOn() {
        XCTAssertEqual(RuleEditForm.blank(interface: "opt7").interface, "opt7")
    }

    func testADraftIsIdentifiedSeparatelyFromAnEdit() {
        // `sheet(item:)` keys on this, so a draft and an edit of the same rule
        // must not look like the same sheet.
        XCTAssertNotEqual(RuleEditForm.blank(interface: "lan").id,
                          RuleEditForm(from: existing()).id)
    }
}

/// Creating and duplicating port forwards.
///
/// The stakes are higher here than for a filter rule. A forward with no
/// tracker is matched back by interface, destination, port and target — and a
/// copy is identical to its original in all four. Without the create flag a
/// duplicate matches what it was copied from and replaces it, so "duplicate"
/// deletes the thing it duplicated.
final class PortForwardCreationTests: XCTestCase {

    private func existing() -> PortForward {
        PortForward(JSONDict([
            "tracker": .string("1700000000"),
            "interface": .string("wan"),
            "protocol": .string("tcp"),
            "ipprotocol": .string("inet"),
            "descr": .string("Web"),
            "source": .object(["address": .string("any")]),
            "destination": .object(["address": .string("any")]),
            "destination_port": .string("443"),
            "target": .string("10.0.0.5")
        ]))
    }

    func testANewForwardSendsNoTrackerAndAsksToCreate() {
        let dict = PortForwardEditForm.blank(interface: "wan").toDict(interface: "wan")
        XCTAssertEqual(dict.string("tracker"), "")
        XCTAssertEqual(dict.bool("create"), true)
        XCTAssertEqual(dict.dict("destination")?.string("address"), "wanip")
    }

    func testAnEditKeepsItsTrackerAndDoesNotAskToCreate() {
        let dict = PortForwardEditForm(from: existing()).toDict(interface: "wan")
        XCTAssertEqual(dict.string("tracker"), "1700000000")
        XCTAssertEqual(dict.bool("create"), false)
    }

    func testADuplicateIsACreateAndDropsTheOriginalTracker() {
        let form = PortForwardEditForm.duplicating(existing())
        let dict = form.toDict(interface: "wan")
        XCTAssertEqual(dict.bool("create"), true)
        XCTAssertEqual(dict.string("tracker"), "")
    }

    func testADuplicateClearsTheDestinationPort() {
        // Two forwards on one interface sharing a destination port is a
        // conflict pfSense accepts and only one of them will work. A copy that
        // keeps its original's port is exactly that, made by accident.
        XCTAssertEqual(PortForwardEditForm.duplicating(existing()).destinationPort, "")
    }

    func testADuplicateIsDistinguishableFromItsOriginal() {
        XCTAssertEqual(PortForwardEditForm.duplicating(existing()).descr, "Web (copy)")
    }

    func testNewAndDuplicatedForwardsStartDisabled() {
        XCTAssertTrue(PortForwardEditForm.blank(interface: "wan").disabled)
        XCTAssertTrue(PortForwardEditForm.duplicating(existing()).disabled)
    }

    func testABlankForwardHasNoTargetSoValidationBlocksIt() {
        // A forward with nowhere to send traffic must not be saveable, and the
        // validator already refuses an empty target.
        let form = PortForwardEditForm.blank(interface: "wan")
        let problems = FieldValidator.problems(inForward: form, aliases: [], interfaces: ["wan"])
        XCTAssertTrue(problems.contains { $0.field == "Target address" })
        XCTAssertFalse(problems.contains { $0.field == "Destination address" })
    }

    func testADraftIsIdentifiedSeparatelyFromAnEdit() {
        XCTAssertNotEqual(PortForwardEditForm.blank(interface: "wan").id,
                          PortForwardEditForm(from: existing()).id)
    }
}
