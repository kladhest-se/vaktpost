import Foundation
import Observation

struct FleetReading: Sendable {
    var cpuUsage: Double?
    var memoryUsage: Double?
    var diskUsage: Double?
    var uptimeSeconds: Int?
    var cpuTicksTotal: Int?
    var cpuTicksIdle: Int?
    var gatewayProblems = 0
    var unknownGateways = 0
    var stoppedServices = 0
    var interfaceProblems = 0
    var gatewayWorstLatencyMS: Double?
    var gatewayWorstLossPercent: Double?
    var firewallStatesCurrent: Int?
    var firewallStatesMaximum: Int?
    var firmwareUpdateAvailable: Bool?
    var packageUpdates = 0
    var systemNotices = 0
    var certificateWarnings: Int?
    var certificateError: String?

    /// Stable administrative facts should be visible immediately. Runtime
    /// telemetry is intentionally separate so one noisy sample can be
    /// confirmed before the fleet card changes to a warning.
    var immediateAttention: Bool {
        firmwareUpdateAvailable == true || packageUpdates > 0
            || systemNotices > 0 || (certificateWarnings ?? 0) > 0
    }

    var transientAttention: Bool {
        (cpuUsage ?? 0) >= 90 || (memoryUsage ?? 0) >= 90 || (diskUsage ?? 0) >= 90
            || gatewayProblems > 0 || unknownGateways > 0 || stoppedServices > 0
            || interfaceProblems > 0 || stateUsage >= 0.9 || certificateError != nil
    }

    var needsAttention: Bool { immediateAttention || transientAttention }

    var stateUsage: Double {
        guard let current = firewallStatesCurrent, let maximum = firewallStatesMaximum,
              maximum > 0 else { return 0 }
        return Double(current) / Double(maximum)
    }
}

struct FleetSnapshot {
    let profile: ServerProfile
    var reading: FleetReading?
    var lastSuccess: Date?
    var lastAttempt: Date?
    var failure: String?
    var consecutiveFailures = 0
    var consecutiveAttentionReadings = 0
    var nextAutomaticAttempt: Date?

    var hasConfirmedTransientAttention: Bool { consecutiveAttentionReadings >= 2 }
    var needsAttention: Bool {
        reading?.immediateAttention == true || hasConfirmedTransientAttention
    }
    var isConfirmingIssue: Bool {
        consecutiveFailures == 1
            || (reading?.transientAttention == true && !hasConfirmedTransientAttention)
    }
}

enum FleetRetryPolicy {
    static func delay(consecutiveFailures: Int, baseSeconds: Int = 10) -> TimeInterval {
        guard consecutiveFailures > 0 else { return 0 }
        let exponent = min(5, consecutiveFailures - 1)
        return TimeInterval(min(300, max(10, baseSeconds) * (1 << exponent)))
    }
}

/// Independent snapshots: polling never changes the selected dashboard server.
/// Sequential checks cap firewall load and one failure does not stop the others.
@MainActor
final class FleetStore: Observable {
    typealias Fetch = @MainActor (ServerProfile) async throws -> FleetReading
    private(set) var snapshots: [UUID: FleetSnapshot] = [:]
    private(set) var isRefreshing = false
    private(set) var checkingID: UUID?
    private var requestID = UUID()
    private var monitorID: UUID?
    private var task: Task<Void, Never>?
    private let fetch: Fetch
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init, fetch: @escaping Fetch) {
        self.now = now
        self.fetch = fetch
    }

    func refresh(_ profiles: [ServerProfile], automatic: Bool = false) async {
        task?.cancel()
        let request = UUID()
        requestID = request
        let ids = Set(profiles.map(\.id))
        snapshots = snapshots.filter { ids.contains($0.key) }
        for profile in profiles where snapshots[profile.id]?.profile != profile {
            snapshots[profile.id] = FleetSnapshot(profile: profile)
        }
        isRefreshing = true
        let task = Task { @MainActor in
            for profile in profiles {
                guard self.requestID == request, !Task.isCancelled else { return }
                if automatic, let retryAt = self.snapshots[profile.id]?.nextAutomaticAttempt,
                   retryAt > self.now() {
                    continue
                }
                self.checkingID = profile.id
                self.snapshots[profile.id]?.lastAttempt = self.now()
                do {
                    var reading = try await self.fetch(profile)
                    guard self.requestID == request, !Task.isCancelled else { return }
                    let previous = self.snapshots[profile.id]
                    if reading.cpuUsage == nil,
                       let date = previous?.lastSuccess, self.now().timeIntervalSince(date) <= 180,
                       let total = reading.cpuTicksTotal, let idle = reading.cpuTicksIdle,
                       let oldTotal = previous?.reading?.cpuTicksTotal,
                       let oldIdle = previous?.reading?.cpuTicksIdle,
                       total > oldTotal, idle >= oldIdle {
                        let cpuPct = 100 * (1 - Double(idle - oldIdle) / Double(total - oldTotal))
                        reading.cpuUsage = min(100, max(0, cpuPct))
                    }
                    self.snapshots[profile.id]?.reading = reading
                    self.snapshots[profile.id]?.lastSuccess = self.now()
                    self.snapshots[profile.id]?.failure = nil
                    self.snapshots[profile.id]?.consecutiveFailures = 0
                    self.snapshots[profile.id]?.nextAutomaticAttempt = nil
                    if reading.transientAttention {
                        self.snapshots[profile.id]?.consecutiveAttentionReadings += 1
                    } else {
                        self.snapshots[profile.id]?.consecutiveAttentionReadings = 0
                    }
                } catch {
                    guard self.requestID == request, !Task.isCancelled else { return }
                    let failures = (self.snapshots[profile.id]?.consecutiveFailures ?? 0) + 1
                    self.snapshots[profile.id]?.consecutiveFailures = failures
                    self.snapshots[profile.id]?.nextAutomaticAttempt = self.now().addingTimeInterval(
                        FleetRetryPolicy.delay(consecutiveFailures: failures)
                    )
                    // One failed request is a retry, not yet an outage. Keep
                    // the last good reading and only raise a failure after the
                    // second consecutive attempt fails.
                    self.snapshots[profile.id]?.failure = failures >= 2 ? error.localizedDescription : nil
                }
            }
        }
        self.task = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: { task.cancel() }
        if requestID == request {
            isRefreshing = false
            checkingID = nil
            self.task = nil
        }
    }

    func monitor(_ profiles: [ServerProfile], interval: Duration = .seconds(10)) async {
        let id = UUID()
        monitorID = id
        defer { if monitorID == id { stop() } }
        while monitorID == id && !Task.isCancelled {
            await refresh(profiles, automatic: true)
            do { try await Task.sleep(for: interval) } catch { return }
        }
    }

    func stop() {
        monitorID = nil
        requestID = UUID()
        task?.cancel()
        task = nil
        isRefreshing = false
        checkingID = nil
    }
}
