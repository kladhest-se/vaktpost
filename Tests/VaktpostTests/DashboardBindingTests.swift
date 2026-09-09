import XCTest
@testable import Vaktpost

@MainActor
final class DashboardBindingTests: XCTestCase {
    func testRebindClearsPreviousServerHistoryAndLoadingState() async {
        let suite = "vaktpost.binding.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let registry = ServerRegistry(defaults: defaults)
        let store = DashboardStore(registry: registry, defaults: defaults)
        await store.rrdLoader.load(.eightHours) { RRDHistory(JSONDict(["available": .bool(true)])) }
        store.widenedFromEmpty = true
        store.stateHistory.ingest(current: 100)
        store.liveInterfaceKey = "old-interface"
        store.liveError = "old error"
        store.isCheckingPackages = true
        store.packageCheckResult = "old result"
        store.isRefreshing = true
        let previousBinding = store.bindingID

        // No usable profile: this exercises rebind without network or keychain writes.
        await store.rebind()

        XCTAssertNotEqual(previousBinding, store.bindingID)
        XCTAssertNil(store.rrdHistory)
        XCTAssertEqual(store.rrdWindow, .week)
        XCTAssertFalse(store.widenedFromEmpty)
        XCTAssertFalse(store.isLoadingRRD)
        XCTAssertTrue(store.stateHistory.points.isEmpty)
        XCTAssertNil(store.liveInterfaceKey)
        XCTAssertNil(store.liveError)
        XCTAssertFalse(store.isCheckingPackages)
        XCTAssertNil(store.packageCheckResult)
        XCTAssertFalse(store.isRefreshing)
        await store.client.invalidate()
    }

    func testDelayedResultFromOldBindingIsRejected() async {
        let suite = "vaktpost.binding.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DashboardStore(registry: ServerRegistry(defaults: defaults), defaults: defaults)
        let binding = store.bindingID
        var continuation: CheckedContinuation<Int, Never>?
        let ready = expectation(description: "Old request suspended")
        let request = Task { @MainActor in
            try await store.checked(binding) {
                await withCheckedContinuation { pending in
                    continuation = pending
                    ready.fulfill()
                }
            }
        }
        await fulfillment(of: [ready], timeout: 2)
        await store.rebind()
        continuation?.resume(returning: 123)
        do { _ = try await request.value; XCTFail("Old result was accepted") }
        catch { XCTAssertEqual(error as? RPCError, .cancelled) }
        await store.client.invalidate()
    }

    func testDelayedErrorFromOldBindingIsRejected() async {
        let suite = "vaktpost.binding.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DashboardStore(registry: ServerRegistry(defaults: defaults), defaults: defaults)
        let binding = store.bindingID
        var continuation: CheckedContinuation<Int, Error>?
        let ready = expectation(description: "Old request suspended")
        let request = Task { @MainActor in
            try await store.checked(binding) {
                try await withCheckedThrowingContinuation { pending in
                    continuation = pending
                    ready.fulfill()
                }
            }
        }
        await fulfillment(of: [ready], timeout: 2)
        await store.rebind()
        continuation?.resume(throwing: RPCError.transport("old server failed"))
        do { _ = try await request.value; XCTFail("Expected obsolete-request cancellation") }
        catch { XCTAssertEqual(error as? RPCError, .cancelled) }
        XCTAssertTrue(store.errors.isEmpty)
        await store.client.invalidate()
    }
}
