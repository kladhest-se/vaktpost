import Foundation
import Combine

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
    var certificateWarnings: Int?
    var certificateError: String?

    var needsAttention: Bool {
        (cpuUsage ?? 0) >= 90 || (memoryUsage ?? 0) >= 90 || (diskUsage ?? 0) >= 90
            || gatewayProblems > 0 || unknownGateways > 0 || stoppedServices > 0
            || (certificateWarnings ?? 0) > 0 || certificateError != nil
    }
}

struct FleetSnapshot {
    let profile: ServerProfile
    var reading: FleetReading?
    var lastSuccess: Date?
    var lastAttempt: Date?
    var failure: String?
}

/// Independent snapshots: polling never changes the selected dashboard server.
/// Sequential checks cap firewall load and one failure does not stop the others.
@MainActor
final class FleetStore: ObservableObject {
    typealias Fetch = @MainActor (ServerProfile) async throws -> FleetReading
    @Published private(set) var snapshots: [UUID: FleetSnapshot] = [:]
    @Published private(set) var isRefreshing = false
    @Published private(set) var checkingID: UUID?
    private var requestID = UUID()
    private var monitorID: UUID?
    private var task: Task<Void, Never>?
    private let fetch: Fetch
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init, fetch: @escaping Fetch) {
        self.now = now
        self.fetch = fetch
    }

    func refresh(_ profiles: [ServerProfile]) async {
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
                        reading.cpuUsage = min(100, max(0,
                            100 * (1 - Double(idle - oldIdle) / Double(total - oldTotal))))
                    }
                    self.snapshots[profile.id]?.reading = reading
                    self.snapshots[profile.id]?.lastSuccess = self.now()
                    self.snapshots[profile.id]?.failure = nil
                } catch {
                    guard self.requestID == request, !Task.isCancelled else { return }
                    self.snapshots[profile.id]?.failure = error.localizedDescription
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

    func monitor(_ profiles: [ServerProfile], interval: Duration = .seconds(60)) async {
        let id = UUID()
        monitorID = id
        defer { if monitorID == id { stop() } }
        while monitorID == id && !Task.isCancelled {
            await refresh(profiles)
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
