import XCTest
@testable import Vaktpost

@MainActor
final class FreshnessIntegrationTests: XCTestCase {
    func testSuccessInOneSectionCannotRefreshAFailedSection() async throws {
        let suite = "vaktpost.freshness.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DashboardStore(registry: ServerRegistry(defaults: defaults), defaults: defaults)
        let binding = store.bindingID
        _ = try await store.checked(binding, sections: [.interfaces]) { 1 }
        let lastInterfaces = store.freshness[.interfaces]?.lastSuccess
        do { _ = try await store.checked(binding, sections: [.interfaces]) { throw RPCError.offline("offline") } }
        catch { }
        _ = try await store.checked(binding, sections: [.system]) { 2 }
        XCTAssertEqual(store.freshness[.interfaces]?.lastSuccess, lastInterfaces)
        XCTAssertNotNil(store.freshness[.interfaces]?.failure)
        XCTAssertNotNil(store.freshness[.system]?.lastSuccess)
        XCTAssertNil(store.freshness[.system]?.failure)
        await store.rebind()
        XCTAssertTrue(store.freshness.isEmpty)
        await store.client.invalidate()
    }

    func testPackageVersionCheckDoesNotRefreshInstalledPackageData() async throws {
        let suite = "vaktpost.freshness.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DashboardStore(registry: ServerRegistry(defaults: defaults), defaults: defaults)
        _ = try await store.checked(store.bindingID, sections: [.packageUpdates]) { 1 }
        XCTAssertNotNil(store.freshness[.packageUpdates]?.lastSuccess)
        XCTAssertNil(store.freshness[.packages]?.lastSuccess)
        await store.client.invalidate()
    }

    func testBatchValidationRejectsMissingSectionButAllowsEmptyLists() async throws {
        let batch = FirewallClient.Batch(JSONDict(["sections": .object(["services": .array([])])]))
        XCTAssertNoThrow(try batch.require(["services"]))
        XCTAssertThrowsError(try batch.require(["interfaces"]))
    }

    func testBatchValidationRejectsNestedError() async throws {
        let batch = FirewallClient.Batch(JSONDict(["sections": .object([
            "services": .object(["__error": .string("failed")])
        ])]))
        XCTAssertThrowsError(try batch.require(["services"]))
    }
}
