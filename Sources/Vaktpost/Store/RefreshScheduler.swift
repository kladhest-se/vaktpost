import Foundation

/// Schedules periodic refreshes of a DashboardStore.
///
/// Replaces the old `Task.sleep` loop in `DashboardStore.startAutoRefresh()`
/// with a dedicated, testable scheduler that can be swapped out or mocked.
@MainActor
final class RefreshScheduler {

    /// Describes why the scheduler was (or will be) stopped.
    enum StopReason: Equatable {
        case manual
        case firewallDisconnected
        case configurationChanged
        case appDidEnterBackground
    }

    /// High-level state of the scheduler.
    enum State: Equatable {
        case idle
        case running(interval: TimeInterval)
        case paused(reason: StopReason)
    }

    // MARK: - Public API

    /// The current state.
    var state: State = .idle {
        didSet { stateChangeHandler?(state) }
    }

    /// The interval between refreshes (read-only after creation).
    let interval: TimeInterval

    /// Called whenever the scheduler state changes.
    var stateChangeHandler: ((State) -> Void)?

    /// Starts or restarts the refresh timer.
    func start(_ refresh: @escaping @Sendable () async -> Void) {
        stop()
        self.refresh = refresh
        state = .running(interval: interval)
        timer = Task { [interval] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch {
                    break
                }
                guard !Task.isCancelled else { break }
                await refresh()
            }
        }
    }

    /// Stops the scheduler and records the reason.
    func stop(reason: StopReason = .manual) {
        timer?.cancel()
        timer = nil
        if case .running = state {
            state = .paused(reason: reason)
        }
    }

    /// Transitions from a paused state back to running.
    func resume(_ refresh: @escaping @Sendable () async -> Void) {
        stop()
        self.refresh = refresh
        state = .running(interval: interval)
        timer = Task { [interval] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch {
                    break
                }
                guard !Task.isCancelled else { break }
                await refresh()
            }
        }
    }

    /// Resets the scheduler to a clean idle state.
    func reset() {
        stop()
        state = .idle
    }

    // MARK: - Private

    private var refresh: (@Sendable () async -> Void)?
    private var timer: Task<Void, Never>?

    // MARK: - Init

    init(interval: TimeInterval = 30) {
        self.interval = interval
    }

    deinit {
        timer?.cancel()
    }
}
