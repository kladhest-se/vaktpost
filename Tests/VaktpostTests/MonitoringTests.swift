import XCTest
@testable import Vaktpost

@MainActor
final class MonitoringTests: XCTestCase {
    func testGaugeRecordsFirstReadingAndKeepsDecreases() async {
        let tracker = MetricTracker<String, Double>()
        let start = Date()
        tracker.ingest(key: "cpu", value: 70, at: start)
        XCTAssertEqual(tracker.latest(for: "cpu")?.value, 70)
        tracker.ingest(key: "cpu", value: 40, at: start.addingTimeInterval(1))
        tracker.ingest(key: "cpu", value: 65, at: start.addingTimeInterval(2))
        XCTAssertEqual(tracker.points(for: "cpu").map(\.value), [70, 40, 65])
        tracker.ingest(key: "cpu", value: 99, at: start)
        XCTAssertEqual(tracker.points(for: "cpu").count, 3)
    }

    func testGaugeCapacityAndReset() async {
        let tracker = MetricTracker<String, Double>()
        let start = Date()
        for index in 0..<100 {
            tracker.ingest(key: "memory", value: Double(index % 2), at: start.addingTimeInterval(Double(index)))
        }
        XCTAssertEqual(tracker.points(for: "memory").count, 60)
        tracker.reset()
        XCTAssertTrue(tracker.points(for: "memory").isEmpty)
    }

    func testOldHistoryResponseCannotReplaceNewSelection() async {
        let loader = HistoryLoader<String, Int>()
        let ready = expectation(description: "old range pending")
        var pending: CheckedContinuation<Int, Never>?
        let old = Task { await loader.load("week") {
            await withCheckedContinuation { pending = $0; ready.fulfill() }
        } }
        await fulfillment(of: [ready], timeout: 2)
        let current = await loader.load("month") { 2 }
        XCTAssertTrue(current)
        pending?.resume(returning: 1)
        let accepted = await old.value
        XCTAssertFalse(accepted)
        XCTAssertEqual(loader.key, "month")
        XCTAssertEqual(loader.value, 2)
        XCTAssertFalse(loader.isLoading)
    }

    func testHistoryCacheExpiresAndForceBypassesIt() async {
        var clock = Date(timeIntervalSince1970: 1000)
        let loader = HistoryLoader<String, Int>(lifetime: 300) { clock }
        var calls = 0
        _ = await loader.load("week") { calls += 1; return calls }
        let firstDate = loader.fetchedAt
        clock = clock.addingTimeInterval(299)
        _ = await loader.load("week") { calls += 1; return calls }
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(loader.fetchedAt, firstDate)
        clock = clock.addingTimeInterval(2)
        _ = await loader.load("week") { calls += 1; return calls }
        XCTAssertEqual(calls, 2)
        _ = await loader.load("week", force: true) { calls += 1; return calls }
        XCTAssertEqual(calls, 3)
    }

    func testHistoryFailureKeepsLastValueAndRetries() async {
        enum Failure: Error { case offline }
        let loader = HistoryLoader<String, Int>()
        _ = await loader.load("week") { 1 }
        let date = loader.fetchedAt
        _ = await loader.load("week", force: true) { throw Failure.offline }
        XCTAssertEqual(loader.value, 1)
        XCTAssertEqual(loader.fetchedAt, date)
        XCTAssertNotNil(loader.error)
        _ = await loader.load("week") { 2 }
        XCTAssertEqual(loader.value, 2)
        XCTAssertNil(loader.error)
    }

    func testHistoryRangeChangeDoesNotShowPreviousRangeWhileLoading() async {
        let loader = HistoryLoader<String, Int>()
        _ = await loader.load("week") { 1 }
        let ready = expectation(description: "month pending")
        var pending: CheckedContinuation<Int, Never>?
        let request = Task { await loader.load("month") {
            await withCheckedContinuation { pending = $0; ready.fulfill() }
        } }
        await fulfillment(of: [ready], timeout: 2)
        XCTAssertEqual(loader.key, "month")
        XCTAssertNil(loader.value)
        XCTAssertNil(loader.fetchedAt)
        XCTAssertTrue(loader.isLoading)
        pending?.resume(returning: 2)
        _ = await request.value
    }

    func testResetRejectsLateHistoryResponse() async {
        let loader = HistoryLoader<String, Int>()
        let ready = expectation(description: "request pending")
        var pending: CheckedContinuation<Int, Never>?
        let request = Task { await loader.load("week") {
            await withCheckedContinuation { pending = $0; ready.fulfill() }
        } }
        await fulfillment(of: [ready], timeout: 2)
        loader.reset()
        pending?.resume(returning: 1)
        let accepted = await request.value
        XCTAssertFalse(accepted)
        XCTAssertNil(loader.value)
        XCTAssertNil(loader.key)
        XCTAssertFalse(loader.isLoading)
        XCTAssertTrue(loader.cache.isEmpty)
    }

    func testFreshnessFailurePreservesLastSuccessfulDate() async {
        var state = SectionFreshness()
        let first = UUID(), second = UUID()
        let date = Date()
        state.begin(first, at: date)
        state.succeed(first, at: date)
        state.begin(second, at: date.addingTimeInterval(30))
        state.fail(second, message: "offline")
        XCTAssertEqual(state.lastSuccess, date)
        XCTAssertTrue(state.isStale(at: date.addingTimeInterval(31), interval: 30))
        XCTAssertNil(state.requestID)
    }

    func testOldFailureCannotOverwriteNewSuccessfulFreshness() async {
        var state = SectionFreshness()
        let old = UUID(), current = UUID(), date = Date()
        state.begin(old, at: date)
        state.begin(current, at: date)
        state.succeed(current, at: date)
        state.fail(old, message: "old failure")
        XCTAssertNil(state.failure)
        XCTAssertFalse(state.isStale(at: date, interval: 30))
        XCTAssertTrue(state.isStale(at: date.addingTimeInterval(61), interval: 30))
    }

    func testFleetFailurePreservesEarlierReadingAndChecksOtherServers() async {
        enum Failure: Error { case offline }
        let a = ServerProfile(baseURL: "https://a.example")
        let b = ServerProfile(baseURL: "https://b.example")
        var clock = Date(timeIntervalSince1970: 1000)
        // Safe despite the warning this silences: every mutation happens
        // between two `await store.refresh(...)` calls in this one test,
        // never while the closure is actually running, so there's no real
        // race for the compiler's static analysis to catch — just nothing
        // in the type system proves it the way it would for an actor.
        nonisolated(unsafe) var failA = false
        let store = FleetStore(now: { clock }) { profile in
            if failA && profile.id == a.id { throw Failure.offline }
            return FleetReading(memoryUsage: 40)
        }
        await store.refresh([a, b])
        let firstDate = store.snapshots[a.id]?.lastSuccess
        clock = clock.addingTimeInterval(60)
        failA = true
        await store.refresh([a, b])
        XCTAssertEqual(store.snapshots[a.id]?.lastSuccess, firstDate)
        XCTAssertEqual(store.snapshots[a.id]?.reading?.memoryUsage, 40)
        XCTAssertNil(store.snapshots[a.id]?.failure)
        XCTAssertEqual(store.snapshots[a.id]?.consecutiveFailures, 1)
        await store.refresh([a, b])
        XCTAssertNotNil(store.snapshots[a.id]?.failure)
        XCTAssertEqual(store.snapshots[b.id]?.lastSuccess, clock)
        XCTAssertNil(store.snapshots[b.id]?.failure)
    }

    func testFleetLateResponseCannotOverwriteEditedProfile() async {
        let a = ServerProfile(baseURL: "https://a.example")
        var edited = a
        edited.baseURL = "https://b.example"
        let ready = expectation(description: "old firewall pending")
        var pending: CheckedContinuation<FleetReading, Never>?
        let store = FleetStore { profile in
            if profile.baseURL == a.baseURL {
                return await withCheckedContinuation { pending = $0; ready.fulfill() }
            }
            return FleetReading(memoryUsage: 20)
        }
        let old = Task { await store.refresh([a]) }
        await fulfillment(of: [ready], timeout: 2)
        await store.refresh([edited])
        pending?.resume(returning: FleetReading(memoryUsage: 99))
        await old.value
        XCTAssertEqual(store.snapshots[a.id]?.reading?.memoryUsage, 20)
        XCTAssertEqual(store.snapshots[a.id]?.profile.baseURL, edited.baseURL)
        XCTAssertFalse(store.isRefreshing)
    }

    func testFleetCPUUsesSeparateBaselinesAndRemovedServersAreDiscarded() async {
        let a = ServerProfile(baseURL: "https://a.example")
        let b = ServerProfile(baseURL: "https://b.example")
        // Same reasoning as failA above: mutated only between sequential
        // awaited refreshes, never concurrently with the closure running.
        nonisolated(unsafe) var second = false
        let store = FleetStore { profile in
            let offset = profile.id == a.id ? 0 : 10000
            return FleetReading(cpuTicksTotal: offset + (second ? 1100 : 1000),
                                cpuTicksIdle: offset + (second ? 940 : 900))
        }
        await store.refresh([a, b])
        XCTAssertNil(store.snapshots[a.id]?.reading?.cpuUsage)
        second = true
        await store.refresh([a, b])
        XCTAssertEqual(store.snapshots[a.id]?.reading?.cpuUsage ?? -1, 60, accuracy: 0.001)
        XCTAssertEqual(store.snapshots[b.id]?.reading?.cpuUsage ?? -1, 60, accuracy: 0.001)
        await store.refresh([b])
        XCTAssertNil(store.snapshots[a.id])
    }
}
