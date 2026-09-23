import Foundation
import XCTest
@testable import Vaktpost

@MainActor
final class AuditTrailPersistenceTests: XCTestCase {

    func testEntriesAreEncryptedDurableAndSeparatedByFirewall() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vaktpost-audit-tests-\(UUID().uuidString)", isDirectory: true)
        let suite = "vaktpost-audit-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }

        let key = Data(repeating: 0x5a, count: 32)
        let firstFirewall = UUID()
        let secondFirewall = UUID()
        let operation = UUID()
        let preview = "Delete secret target 192.0.2.15"

        let trail = AuditTrail(storageDirectory: directory,
                               encryptionKeyData: key,
                               defaults: defaults)
        trail.bind(to: firstFirewall)
        try trail.begin(
            id: operation,
            firewallID: firstFirewall,
            action: .deleteRule,
            summary: "Delete rule",
            target: "secret target",
            preview: preview,
            beforeHash: AuditTrail.hash("before")
        )
        try trail.finish(
            id: operation,
            firewallID: firstFirewall,
            responseStatus: "ok",
            verification: .verified,
            detail: "Rule is absent.",
            afterHash: AuditTrail.hash("after")
        )

        let file = directory.appendingPathComponent("\(firstFirewall.uuidString.lowercased()).audit")
        let ciphertext = try Data(contentsOf: file)
        XCTAssertNil(ciphertext.range(of: Data(preview.utf8)))

        let reloaded = AuditTrail(storageDirectory: directory,
                                  encryptionKeyData: key,
                                  defaults: defaults)
        reloaded.bind(to: firstFirewall)
        XCTAssertEqual(reloaded.entries.count, 1)
        XCTAssertEqual(reloaded.entries.first?.id, operation)
        XCTAssertEqual(reloaded.entries.first?.verification, .verified)

        reloaded.bind(to: secondFirewall)
        XCTAssertTrue(reloaded.entries.isEmpty)
    }
    func testAdministrativeOperationProvidesSpecificPreview() {
        let operation = AdministrativeWrite.quickBlock(
            interface: "wan",
            address: "192.0.2.7",
            description: "test block"
        )

        XCTAssertTrue(operation.preview.contains("192.0.2.7"))
        XCTAssertTrue(operation.preview.contains("wan"))
        XCTAssertEqual(operation.action, .quickBlock)
    }
}
