import XCTest
import Security
@testable import Vaktpost

final class AuditCoreTests: XCTestCase {
    private actor Activity {
        var active = 0
        var peak = 0
        var calls: [Int] = []
        func perform(_ id: Int) async throws -> Int {
            active += 1
            peak = max(peak, active)
            calls.append(id)
            defer { active -= 1 }
            try await Task.sleep(nanoseconds: 40_000_000)
            return id
        }
        func snapshot() -> (Int, [Int]) { (peak, calls) }
    }

    func testConcurrentRequestsRemainSerial() async throws {
        let queue = SerialRequestQueue()
        let activity = Activity()
        try await withThrowingTaskGroup(of: Int.self) { group in
            for id in 0..<12 {
                group.addTask { try await queue.run { try await activity.perform(id) } }
            }
            for try await _ in group { }
        }
        let (peak, calls) = await activity.snapshot()
        XCTAssertEqual(peak, 1)
        XCTAssertEqual(Set(calls), Set(0..<12))
    }

    func testCancelledQueuedRequestDoesNotRunOrReleaseSuccessorEarly() async throws {
        let queue = SerialRequestQueue()
        let activity = Activity()
        let first = Task { try await queue.run { try await activity.perform(1) } }
        try await Task.sleep(nanoseconds: 5_000_000)
        let second = Task { try await queue.run { try await activity.perform(2) } }
        try await Task.sleep(nanoseconds: 5_000_000)
        let third = Task { try await queue.run { try await activity.perform(3) } }
        second.cancel()
        _ = try await first.value
        do { _ = try await second.value; XCTFail("Cancelled operation succeeded") }
        catch is CancellationError { }
        _ = try await third.value
        let (peak, calls) = await activity.snapshot()
        XCTAssertEqual(peak, 1)
        XCTAssertEqual(calls, [1, 3])
    }

    func testInvalidatedQueueCancelsActiveWorkAndRejectsNewWork() async throws {
        let queue = SerialRequestQueue()
        let activity = Activity()
        let first = Task { try await queue.run { try await activity.perform(1) } }
        try await Task.sleep(nanoseconds: 5_000_000)
        await queue.invalidate()
        do { _ = try await first.value; XCTFail("Active operation survived invalidation") }
        catch is CancellationError { }
        do { _ = try await queue.run { try await activity.perform(2) }; XCTFail("Invalid queue accepted work") }
        catch is CancellationError { }
        let (_, calls) = await activity.snapshot()
        XCTAssertFalse(calls.contains(2))
    }

    func testFailedRequestDoesNotBlockNextRequest() async throws {
        enum Failure: Error { case expected }
        let queue = SerialRequestQueue()
        do { let _: Int = try await queue.run { throw Failure.expected }; XCTFail("Expected failure") }
        catch Failure.expected { }
        let value = try await queue.run { 42 }
        XCTAssertEqual(value, 42)
    }

    func testCompetingPromptDecisionsCompleteOnlyOnce() {
        let lock = NSLock()
        var calls = 0
        let once = Once<Int> { _ in
            lock.lock()
            calls += 1
            lock.unlock()
        }
        DispatchQueue.concurrentPerform(iterations: 100) { once.resolve($0) }
        XCTAssertEqual(calls, 1)
    }

    func testCancelledPromptCannotLaterTrust() {
        var decisions: [String] = []
        let once = Once<String> { decisions.append($0) }
        once.resolve("cancel")
        once.resolve("trust")
        XCTAssertEqual(decisions, ["cancel"])
    }

    func testPinSurvivesRegistryReload() async {
        await MainActor.run {
            let suite = "vaktpost.audit.\(UUID())"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let registry = ServerRegistry(defaults: defaults)
            let profile = ServerProfile(baseURL: "https://a.example", username: "test")
            registry.upsert(profile)
            XCTAssertTrue(registry.pinCertificate("abc123", for: profile))
            let restored = ServerRegistry(defaults: defaults)
            XCTAssertEqual(restored.active?.pinnedFingerprint, "abc123")
            XCTAssertEqual(restored.active?.allowUntrustedTLS, false)
        }
    }

    func testObsoletePinCannotOverwriteEditedEndpoint() async {
        await MainActor.run {
            let suite = "vaktpost.audit.\(UUID())"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let registry = ServerRegistry(defaults: defaults)
            let original = ServerProfile(baseURL: "https://a.example", username: "test")
            registry.upsert(original)
            var edited = original
            edited.baseURL = "https://b.example"
            registry.upsert(edited)
            XCTAssertFalse(registry.pinCertificate("old-certificate", for: original))
            XCTAssertEqual(registry.active?.pinnedFingerprint, "")
        }
    }

    func testEmptyPasswordNeverTouchesStorage() {
        let result = Keychain.setPassword("", for: UUID(), update: { _, _ in
            XCTFail("Validation must precede mutation")
            return errSecSuccess
        }, add: { _ in XCTFail("Empty password was inserted"); return errSecSuccess })
        if case .success = result { XCTFail("Empty password was accepted") }
    }

    func testPasswordWhitespaceReachesStorageUnchanged() throws {
        let password = " leading and trailing \n"
        var stored: Data?
        try Keychain.setPassword(password, for: UUID(), update: { _, attributes in
            stored = (attributes as NSDictionary)[kSecValueData] as? Data
            return errSecSuccess
        }, add: { _ in XCTFail("Existing item should be updated"); return errSecSuccess }).get()
        XCTAssertEqual(stored, password.data(using: .utf8))
    }

    func testFailedUpdateDoesNotTryReplacingTheExistingItem() {
        var addCalls = 0
        let result = Keychain.setPassword("new", for: UUID(), update: { _, _ in
            errSecInteractionNotAllowed
        }, add: { _ in addCalls += 1; return errSecSuccess })
        XCTAssertEqual(addCalls, 0)
        if case .success = result { XCTFail("Failed update was reported as successful") }
    }

    func testDuplicateInsertRequiresSuccessfulUpdate() {
        var updates = 0
        let result = Keychain.setPassword("new", for: UUID(), update: { _, _ in
            updates += 1
            return updates == 1 ? errSecItemNotFound : errSecInteractionNotAllowed
        }, add: { _ in errSecDuplicateItem })
        XCTAssertEqual(updates, 2)
        if case .success = result { XCTFail("Duplicate item was mistaken for a successful save") }
    }
}
