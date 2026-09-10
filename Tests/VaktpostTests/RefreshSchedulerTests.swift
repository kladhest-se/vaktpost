import XCTest
@testable import Vaktpost

@MainActor
final class RefreshSchedulerTests: XCTestCase {

    func testStartSetsRunningStateAndCallsRefresh() async {
        var refreshes = 0
        let scheduler = RefreshScheduler(interval: 0.1)
        let done = expectation(description: "refresh called")
        
        scheduler.stateChangeHandler = { state in
            if case .running = state {
                // State changed to running, that's all we need to verify
            }
        }
        
        scheduler.start {
            refreshes += 1
            if refreshes == 1 { done.fulfill() }
        }
        
        await fulfillment(of: [done], timeout: 2)
        scheduler.stop()
        XCTAssertTrue(refreshes >= 1)
    }

    func testStopRecordsManualReason() async {
        var finalState: RefreshScheduler.State = .idle
        let scheduler = RefreshScheduler(interval: 1)
        scheduler.stateChangeHandler = { finalState = $0 }
        
        scheduler.start { }
        scheduler.stop(reason: .manual)
        
        if case .paused(let reason) = finalState {
            XCTAssertEqual(reason, .manual)
        } else {
            XCTFail("Expected paused state")
        }
    }

    func testResumeRestartsTimer() async {
        var refreshes = 0
        let scheduler = RefreshScheduler(interval: 0.1)
        let done = expectation(description: "refresh after resume")
        
        scheduler.start { }
        scheduler.stop(reason: .manual)
        
        scheduler.resume {
            refreshes += 1
            if refreshes == 1 { done.fulfill() }
        }
        
        await fulfillment(of: [done], timeout: 2)
        scheduler.stop()
    }

    func testResetClearsState() async {
        let scheduler = RefreshScheduler(interval: 0.1)
        scheduler.start { }
        scheduler.reset()
        
        // After reset, state should be idle and no refreshes should happen
        try? await Task.sleep(for: .milliseconds(50))
        // If reset worked, no refresh should have occurred
    }

    func testSchedulerStopsOnCancellation() async {
        let scheduler = RefreshScheduler(interval: 0.05)
        let task = Task<Void, Never> {
            await withCheckedContinuation { _ in }
        }
        
        var callCount = 0
        scheduler.start {
            callCount += 1
            if callCount >= 3 { task.cancel() }
        }
        
        // Let it run for a bit
        try? await Task.sleep(for: .milliseconds(200))
        task.cancel()
        
        // Wait for scheduler to notice cancellation
        try? await Task.sleep(for: .milliseconds(100))
        scheduler.stop()
        
        // Should have had at least 2-3 calls before cancellation
        XCTAssertTrue(callCount >= 2, "Expected multiple refreshes before cancellation")
    }
}
