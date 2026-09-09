import Foundation

extension FleetStore {
    convenience init() {
        self.init(fetch: Self.readFirewall)
    }

    /// No interactive trust dialogs or package-repository checks while scanning
    /// the fleet. A firewall needing approval can be opened explicitly.
    private static func readFirewall(_ profile: ServerProfile) async throws -> FleetReading {
        guard profile.isConfigured else { throw RPCError.badURL }
        guard profile.hasCredentials else { throw RPCError.noCredentials }
        let client = FirewallClient(profile: profile, allowsTrustPrompt: false) { _, _ in false }
        do {
            let batch = try await client.batchCore()
            try Task.checkCancellation()
            let system = SystemStatus(batch.object("telemetry"))
            let gateways = batch.rows("gateways").map(GatewayStatus.init)
            let services = batch.rows("services").map(ServiceStatus.init)
            var reading = FleetReading(
                cpuUsage: system.cpuUsage, memoryUsage: system.memUsage,
                diskUsage: system.diskUsage, uptimeSeconds: system.uptimeSeconds,
                cpuTicksTotal: system.cpuTicksTotal, cpuTicksIdle: system.cpuTicksIdle,
                gatewayProblems: gateways.filter { $0.health == .bad || $0.health == .warn }.count,
                unknownGateways: gateways.filter { $0.health == .idle }.count,
                stoppedServices: services.filter { $0.health == .bad }.count)
            do {
                let certificates = try await client.certificates()
                try Task.checkCancellation()
                reading.certificateWarnings = certificates.filter {
                    $0.health == .warn || $0.health == .bad
                }.count
            } catch {
                try Task.checkCancellation()
                reading.certificateError = error.localizedDescription
            }
            await client.invalidate()
            return reading
        } catch {
            await client.invalidate()
            throw error
        }
    }
}
