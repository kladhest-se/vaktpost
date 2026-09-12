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
}
