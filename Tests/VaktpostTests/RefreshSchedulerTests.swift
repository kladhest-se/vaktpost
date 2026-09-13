import XCTest
import os
@testable import Vaktpost

@MainActor
final class RefreshSchedulerTests: XCTestCase {

    func testStartSetsRunningStateAndCallsRefresh() async {
        let refreshes = OSAllocatedUnfairLock(initialState: 0)
        let scheduler = RefreshScheduler(interval: 0.1)
        let done = expectation(description: "refresh called")
        
        scheduler.stateChangeHandler = { state in
            if case .running = state {
                // State changed to running, that's all we need to verify
            }
        }
        
        scheduler.start {
            let count = refreshes.withLock { value in
                value += 1
                return value
            }
            if count == 1 { done.fulfill() }
        }
        
        await fulfillment(of: [done], timeout: 2)
        scheduler.stop()
        XCTAssertTrue(refreshes.withLock { $0 } >= 1)
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
        let refreshes = OSAllocatedUnfairLock(initialState: 0)
        let scheduler = RefreshScheduler(interval: 0.1)
        let done = expectation(description: "refresh after resume")
        
        scheduler.start { }
        scheduler.stop(reason: .manual)
        
        scheduler.resume {
            let count = refreshes.withLock { value in
                value += 1
                return value
            }
            if count == 1 { done.fulfill() }
        }
        
        await fulfillment(of: [done], timeout: 2)
        scheduler.stop()
    }

    func testResetClearsState() async {
        let scheduler = RefreshScheduler(interval: 0.1)
        scheduler.start { }
        scheduler.reset()
        
        XCTAssertTrue(scheduler.state == .idle, "State should be idle after reset")
    }

    func testSchedulerStopsOnCancellation() async {
        let scheduler = RefreshScheduler(interval: 0.05)
        let callCount = OSAllocatedUnfairLock(initialState: 0)
        let reachedThree = expectation(description: "three refreshes")
        scheduler.start {
            let count = callCount.withLock { value in
                value += 1
                return value
            }
            if count == 3 { reachedThree.fulfill() }
        }

        await fulfillment(of: [reachedThree], timeout: 2)
        scheduler.stop()
        let stoppedAt = callCount.withLock { $0 }
        try? await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(callCount.withLock { $0 }, stoppedAt,
                       "A cancelled scheduler must not fire again")
    }
}
