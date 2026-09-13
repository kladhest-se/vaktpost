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

    func testSaveResponseCarriesTheIdentityNeededForReadBack() throws {
        let created = JSONDict([
            "status": .string("ok"), "created": .bool(true), "tracker": .string("1730000002")
        ])
        XCTAssertNoThrow(try FirewallClient.validatedSaveResponse(
            created, operation: "Rule save", requestedTracker: "", isCreate: true
        ))

        let edited = JSONDict([
            "status": .string("ok"), "created": .bool(false), "tracker": .string("1730000001")
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

        XCTAssertEqual(AdministrativeWrite.saveRule(rule: create, displayName: "new").action, .addRule)
        XCTAssertEqual(AdministrativeWrite.saveRule(rule: edit, displayName: "old").action, .editRule)
        XCTAssertEqual(AdministrativeWrite.saveNatRule(rule: create, displayName: "new").action, .addPortForward)
        XCTAssertEqual(AdministrativeWrite.saveNatRule(rule: edit, displayName: "old").action, .editPortForward)
    }

    func testRuleEditReplacesOriginalSlotInsteadOfDroppingIt() {
        let body = PHPSnippet.saveRule(rule: JSONDict([:])).body
        XCTAssertTrue(body.contains("$rules[$vaktpost_index] = $rule;"))
        XCTAssertFalse(body.contains("unset($rules[$idx]);"))
    }

    func testQuickBlockWritesNativeFilterRuleShape() {
        let body = PHPSnippet.quickBlock(interface: "wan", address: "192.0.2.7", description: "test").body
        XCTAssertTrue(body.contains("$config['filter']['rule']"))
        XCTAssertTrue(body.contains("'destination' => ['any' => true]"))
        XCTAssertTrue(body.contains("'tracker' => $vaktpost_tracker"))
        XCTAssertFalse(body.contains("$config['rules']"))
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
            XCTAssertTrue(body.contains("if ($vaktpost_create)"))
            XCTAssertTrue(body.contains("$vaktpost_collision = true;"))
            XCTAssertTrue(body.contains("$toreturn[\"tracker\"] = $tracker;"))
            XCTAssertTrue(body.contains("if (!$vaktpost_create && !$found)"))
        }
    }
}
