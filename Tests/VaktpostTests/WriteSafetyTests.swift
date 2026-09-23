import XCTest
@testable import Vaktpost

final class WriteSafetyTests: XCTestCase {

    func testMonitorOnlyClientRejectsMutationBeforeTransport() async {
        let profile = ServerProfile(baseURL: "https://unreachable.example", username: "test")
        let client = FirewallClient(profile: profile) { _, _ in false }

        do {
            _ = try await client.reloadFirewall()
            XCTFail("Monitor-only client accepted a mutation")
        } catch {
            XCTAssertEqual(error as? RPCError, .administrationDisabled)
        }
    }

    func testPortForwardUsesTrackerAsStableIdentity() {
        let forward = PortForward(JSONDict([
            "tracker": .string("1730000001"),
            "interface": .string("wan"),
            "destination": .object(["address": .string("wanip")]),
            "destination_port": .string("443"),
            "target": .string("192.0.2.10")
        ]))

        XCTAssertEqual(forward.tracker, "1730000001")
        XCTAssertEqual(forward.id, "1730000001")
        XCTAssertEqual(PortForwardEditForm(from: forward).toDict(interface: "lan").string("tracker"),
                       "1730000001")
    }

    func testPortForwardWithoutTrackerKeepsDisplayIdentityFallback() {
        let forward = PortForward(JSONDict([
            "interface": .string("wan"),
            "destination": .object(["address": .string("wanip")]),
            "destination_port": .string("443"),
            "target": .string("192.0.2.10")
        ]))

        XCTAssertTrue(forward.tracker.isEmpty)
        XCTAssertEqual(forward.id, "wan-wanip:443-192.0.2.10")
    }

    func testNatReorderItemIdentifiesATrackerlessForwardByItsOriginalSlot() {
        let forward = PortForward(JSONDict([
            "interface": .string("wan"),
            "destination": .object(["address": .string("wanip")]),
            "destination_port": .string("443"),
            "target": .string("192.0.2.10")
        ]))
        let item = FirewallClient.NatReorderItem(originalIndex: 2, forward: forward)

        XCTAssertTrue(item.matches(forward, at: 2))
        XCTAssertFalse(item.matches(forward, at: 1))
        guard let json = JSONDict(item.json) else {
            return XCTFail("expected an object payload")
        }
        XCTAssertEqual(json.int("original_index"), 2)
        XCTAssertEqual(json.string("tracker"), "")
    }

    func testNatReorderItemRejectsAChangedForward() {
        let original = PortForward(JSONDict([
            "tracker": .string("1730000001"),
            "interface": .string("wan"),
            "destination": .object(["address": .string("wanip")]),
            "destination_port": .string("443"),
            "target": .string("192.0.2.10")
        ]))
        let changed = PortForward(JSONDict([
            "tracker": .string("1730000001"),
            "interface": .string("wan"),
            "destination": .object(["address": .string("wanip")]),
            "destination_port": .string("8443"),
            "target": .string("192.0.2.10")
        ]))

        let item = FirewallClient.NatReorderItem(originalIndex: 0, forward: original)
        XCTAssertFalse(item.matches(changed, at: 0))
    }

    func testWriteResponseRequiresExplicitOK() throws {
        let accepted = JSONDict(["status": .string("ok")])
        XCTAssertNoThrow(try FirewallClient.validatedWriteResponse(accepted, operation: "Test"))

        for rejected in [
            JSONDict(["status": .string("not_found")]),
            JSONDict(["status": .string("failed"), "error": .string("reload rejected")]),
            JSONDict([:])
        ] {
            XCTAssertThrowsError(
                try FirewallClient.validatedWriteResponse(rejected, operation: "Test")
            )
        }
    }

    /// "missing status" told nobody anything. A reply that is not the one the
    /// snippet writes has to say what it was instead, or the next report of
    /// this failure is as unactionable as the last.
    func testAnUnrecognisedWriteReplyNamesWhatCameBack() {
        let noStatus = JSONDict(["apply_pending": .bool(true), "rule": .string("x")])
        let named = FirewallClient.writeFailureMessage(noStatus, operation: "Quick block")
        XCTAssertTrue(named.contains("apply_pending, rule"), named)
        XCTAssertFalse(named.contains("missing status"), named)

        let empty = FirewallClient.writeFailureMessage(JSONDict([:]), operation: "Quick block")
        XCTAssertTrue(empty.contains("empty result"), empty)
        XCTAssertTrue(empty.contains("may or may not"), empty)

        let reported = JSONDict(["status": .string("validation_failed"), "error": .string("bad address")])
        let detail = FirewallClient.writeFailureMessage(reported, operation: "Quick block")
        XCTAssertTrue(detail.contains("validation_failed"), detail)
        XCTAssertTrue(detail.contains("bad address"), detail)
    }

    func testTheQuickBlockSnippetReportsAnUnfinishedRun() {
        let snippet = PHPSnippet.quickBlock(interface: "wan", address: "192.0.2.44", description: "test")
        // Set before the work and overwritten by every ending, so a run that
        // stops partway is distinguishable from an unknown reply shape.
        XCTAssertTrue(snippet.body.contains("$toreturn[\"status\"] = \"incomplete\";"))
        XCTAssertTrue(snippet.body.contains("$toreturn[\"status\"] = \"ok\";"))
    }

    func testSaveResponseCarriesTheIdentityNeededForReadBack() throws {
        let created = JSONDict([
            "status": .string("ok"), "apply_pending": .bool(true),
            "created": .bool(true), "tracker": .string("1730000002")
        ])
        XCTAssertNoThrow(try FirewallClient.validatedSaveResponse(
            created, operation: "Rule save", requestedTracker: "", isCreate: true
        ))

        let edited = JSONDict([
            "status": .string("ok"), "apply_pending": .bool(true),
            "created": .bool(false), "tracker": .string("1730000001")
        ])
        XCTAssertNoThrow(try FirewallClient.validatedSaveResponse(
            edited, operation: "Rule save", requestedTracker: "1730000001", isCreate: false
        ))

        for invalid in [
            JSONDict(["status": .string("ok"), "created": .bool(true)]),
            JSONDict(["status": .string("ok"), "created": .bool(false), "tracker": .string("different")]),
            JSONDict(["status": .string("ok"), "created": .bool(false), "tracker": .string("")])
        ] {
            XCTAssertThrowsError(try FirewallClient.validatedSaveResponse(
                invalid, operation: "Rule save", requestedTracker: "expected", isCreate: false
            ))
        }
    }

    func testCreationUsesAddAuditCategories() {
        let create = JSONDict(["create": .bool(true)])
        let edit = JSONDict(["create": .bool(false), "tracker": .string("1")])
        let move = JSONDict([
            "create": .bool(false), "tracker": .string("1"), "placement": .string("last")
        ])

        XCTAssertEqual(AdministrativeWrite.saveRule(rule: create, displayName: "new").action, .addRule)
        XCTAssertEqual(AdministrativeWrite.saveRule(rule: edit, displayName: "old").action, .editRule)
        XCTAssertEqual(AdministrativeWrite.saveRule(rule: move, displayName: "old").action, .reorderRules)
        XCTAssertEqual(AdministrativeWrite.saveNatRule(rule: create, displayName: "new").action, .addPortForward)
        XCTAssertEqual(AdministrativeWrite.saveNatRule(rule: edit, displayName: "old").action, .editPortForward)
        XCTAssertEqual(AdministrativeWrite.saveFilterSeparator(
            separator: create, displayName: "new"
        ).action, .addSeparator)
        XCTAssertEqual(AdministrativeWrite.saveFilterSeparator(
            separator: edit, displayName: "old"
        ).action, .editSeparator)
        XCTAssertEqual(AdministrativeWrite.deleteFilterSeparator(
            interface: "lan", key: "sep0", displayName: "old"
        ).action, .deleteSeparator)
        XCTAssertEqual(AdministrativeWrite.saveNatSeparator(
            separator: create, displayName: "new NAT group"
        ).action, .addSeparator)
        XCTAssertEqual(AdministrativeWrite.saveNatSeparator(
            separator: edit, displayName: "old NAT group"
        ).action, .editSeparator)
        XCTAssertEqual(AdministrativeWrite.deleteNatSeparator(
            key: "sep0", displayName: "old NAT group"
        ).action, .deleteSeparator)
    }

    func testAdministrativePreviewNamesNativeSystemSelectors() {
        let rule = JSONDict([
            "interface": .string("wan"), "type": .string("block"),
            "source": .object(["network": .string("wanip")]),
            "destination": .object(["network": .string("lan")])
        ])
        let preview = AdministrativeWrite.saveRule(rule: rule, displayName: "test").preview
        XCTAssertTrue(preview.contains("wanip (system selector)"))
        XCTAssertTrue(preview.contains("lan (system selector)"))
    }

    func testRuleEditReplacesOriginalSlotInsteadOfDroppingIt() {
        let body = PHPSnippet.saveRule(rule: JSONDict([:])).body
        XCTAssertTrue(body.contains("$rules[$vaktpost_index] = $rule;"))
        XCTAssertFalse(body.contains("unset($rules[$idx]);"))
    }

    func testRulePlacementUsesStableTrackerAnchorsAndFailsClosed() {
        let body = PHPSnippet.saveRule(rule: JSONDict([:])).body

        XCTAssertTrue(body.contains("before_tracker"))
        XCTAssertTrue(body.contains("position_not_found"))
        XCTAssertTrue(body.contains("$toreturn[\"placement\"] = $vaktpost_placement;"))
        XCTAssertTrue(body.contains("$toreturn[\"before_tracker\"] = $vaktpost_before;"))
    }

    func testSaveSnippetsUseNativeAddressShapesAndFirewallValidation() {
        for body in [PHPSnippet.saveRule(rule: JSONDict([:])).body,
                     PHPSnippet.saveNatRule(rule: JSONDict([:])).body] {
            XCTAssertTrue(body.contains("get_specialnet("))
            XCTAssertTrue(body.contains("is_ipaddroralias("))
            XCTAssertTrue(body.contains("is_port_or_alias("))
            XCTAssertTrue(body.contains("validation_failed"))
            XCTAssertTrue(body.contains("$vaktpost_sides[$vaktpost_side_name] = [\"any\" => true];"))
            XCTAssertTrue(body.contains("[\"network\" => $vaktpost_value]"))
            XCTAssertTrue(body.contains("[\"address\" => $vaktpost_value]"))
        }
    }

    func testQuickBlockWritesNativeFilterRuleShape() {
        let body = PHPSnippet.quickBlock(interface: "wan", address: "192.0.2.7", description: "test").body
        XCTAssertTrue(body.contains("$config['filter']['rule']"))
        XCTAssertTrue(body.contains("get_configured_interface_with_descr()"))
        XCTAssertTrue(body.contains("is_ipaddrv4("))
        XCTAssertTrue(body.contains("is_ipaddrv6("))
        XCTAssertTrue(body.contains("'source' => ['address' => $vaktpost_addr]"))
        XCTAssertTrue(body.contains("'destination' => ['any' => true]"))
        XCTAssertTrue(body.contains("'tracker' => $vaktpost_tracker"))
        XCTAssertFalse(body.contains("[\"network\" => $vaktpost_addr]"))
        XCTAssertFalse(body.contains("$config['rules']"))
    }

    func testInterfaceStateFlushFailsClosedForAnUnknownDevice() {
        let body = PHPSnippet.flushStates(interface: "igb0").body
        XCTAssertTrue(body.contains("does_interface_exist($vaktpost_if)"))
        XCTAssertTrue(body.contains("validation_failed"))
    }

    func testCreatedLabFixturesKeepTheirSuppliedTracker() {
        let rule = PHPSnippet.saveRule(rule: JSONDict(["tracker": .string("123")])).body
        let nat = PHPSnippet.saveNatRule(rule: JSONDict(["tracker": .string("456")])).body
        XCTAssertTrue(rule.contains("$rule[\"tracker\"] = $tracker;"))
        XCTAssertTrue(nat.contains("$rule[\"tracker\"] = $tracker;"))
    }

    func testBothCreateSnippetsAllocateAndReturnTrackers() {
        let rule = PHPSnippet.saveRule(rule: JSONDict([:])).body
        let nat = PHPSnippet.saveNatRule(rule: JSONDict([:])).body

        for body in [rule, nat] {
            XCTAssertTrue(body.contains("$vaktpost_collision = true;"))
            XCTAssertTrue(body.contains("$toreturn[\"tracker\"] = $tracker;"))
            XCTAssertTrue(body.contains("if (!$vaktpost_create && !$found)"))
        }

        // Filter-rule creates always allocate. NAT also allocates when healing
        // a trackerless legacy row, so its equivalent guard is intentionally
        // based on the row's tracker rather than create/edit mode alone.
        XCTAssertTrue(rule.contains("if ($vaktpost_create)"))
        XCTAssertTrue(nat.contains("if (empty($rule[\"tracker\"] ?? \"\"))"))
    }
}
