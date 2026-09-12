import Foundation
import Observation

/// Detects traffic anomalies by analyzing firewall log patterns.
///
/// Compares current traffic counts against historical baselines to flag
/// sudden spikes in blocked, rejected, or passed traffic.
@MainActor
@Observable
final class TrafficAnomalyDetector {
    
    struct Anomaly: Identifiable {
        let id = UUID()
        let type: AnomalyType
        let metric: String
        let currentValue: Int
        let baselineValue: Int
        let spikePercent: Double
        let timestamp: Date
        let severity: Severity
        
        enum AnomalyType: String {
            case blockedTrafficSpike = "blocked_traffic_spike"
            case rejectedTrafficSpike = "rejected_traffic_spike"
            case passedTrafficSpike = "passed_traffic_spike"
            case trafficDrop = "traffic_drop"
        }
        
        enum Severity: String {
            case low = "low"
            case medium = "medium"
            case high = "high"
            case critical = "critical"
        }
        
        var message: String {
            switch type {
            case .blockedTrafficSpike, .rejectedTrafficSpike, .passedTrafficSpike:
                return "\(metric) traffic spiked \(String(format: "%.0f", spikePercent))% above baseline (\(currentValue) vs \(baselineValue))"
            case .trafficDrop:
                return "\(metric) traffic dropped \(String(format: "%.0f", spikePercent))% below baseline (\(currentValue) vs \(baselineValue))"
            }
        }
    }
    
    private let baselineWindow: TimeInterval
    private let spikeThreshold: Double
    private let dropThreshold: Double
    
    private(set) var currentCounts = TrafficCounts()
    private(set) var baselineCounts = TrafficCounts()
    private(set) var anomalies: [Anomaly] = []
    
    struct TrafficCounts {
        var blocked: Int = 0
        var rejected: Int = 0
        var passed: Int = 0
        var timestamp: Date = Date()
    }
    
    init(baselineWindow: TimeInterval = 300, spikeThreshold: Double = 2.0, dropThreshold: Double = 0.5) {
        self.baselineWindow = baselineWindow
        self.spikeThreshold = spikeThreshold
        self.dropThreshold = dropThreshold
    }
    
    func analyze(currentCounts: TrafficCounts, previousCounts: TrafficCounts) -> [Anomaly] {
        self.currentCounts = currentCounts
        
        // Calculate baseline from previous counts
        baselineCounts = previousCounts
        
        var detectedAnomalies: [Anomaly] = []
        
        // Check for blocked traffic spike
        if let anomaly = checkSpike(
            metric: "Blocked",
            current: currentCounts.blocked,
            baseline: baselineCounts.blocked,
            type: .blockedTrafficSpike
        ) {
            detectedAnomalies.append(anomaly)
        }
        
        // Check for rejected traffic spike
        if let anomaly = checkSpike(
            metric: "Rejected",
            current: currentCounts.rejected,
            baseline: baselineCounts.rejected,
            type: .rejectedTrafficSpike
        ) {
            detectedAnomalies.append(anomaly)
        }
        
        // Check for passed traffic spike
        if let anomaly = checkSpike(
            metric: "Passed",
            current: currentCounts.passed,
            baseline: baselineCounts.passed,
            type: .passedTrafficSpike
        ) {
            detectedAnomalies.append(anomaly)
        }
        
        // Check for traffic drops
        if let anomaly = checkDrop(
            metric: "Blocked",
            current: currentCounts.blocked,
            baseline: baselineCounts.blocked
        ) {
            detectedAnomalies.append(anomaly)
        }
        
        if let anomaly = checkDrop(
            metric: "Rejected",
            current: currentCounts.rejected,
            baseline: baselineCounts.rejected
        ) {
            detectedAnomalies.append(anomaly)
        }
        
        if let anomaly = checkDrop(
            metric: "Passed",
            current: currentCounts.passed,
            baseline: baselineCounts.passed
        ) {
            detectedAnomalies.append(anomaly)
        }
        
        anomalies = detectedAnomalies
        return detectedAnomalies
    }
    
    private func checkSpike(metric: String, current: Int, baseline: Int, type: Anomaly.AnomalyType) -> Anomaly? {
        guard baseline > 0, current > baseline else { return nil }
        
        let spikePercent = Double(current - baseline) / Double(baseline)
        
        guard spikePercent >= spikeThreshold else { return nil }
        
        let severity: Anomaly.Severity = {
            if spikePercent >= 5.0 { return .critical }
            if spikePercent >= 3.0 { return .high }
            if spikePercent >= 2.0 { return .medium }
            return .low
        }()
        
        return Anomaly(
            type: type,
            metric: metric,
            currentValue: current,
            baselineValue: baseline,
            spikePercent: spikePercent * 100,
            timestamp: Date(),
            severity: severity
        )
    }
    
    private func checkDrop(metric: String, current: Int, baseline: Int) -> Anomaly? {
        guard baseline > 0, current < baseline else { return nil }
        
        let dropPercent = Double(baseline - current) / Double(baseline)
        
        guard dropPercent >= dropThreshold else { return nil }
        
        let severity: Anomaly.Severity = {
            if dropPercent >= 0.8 { return .critical }
            if dropPercent >= 0.6 { return .high }
            if dropPercent >= 0.4 { return .medium }
            return .low
        }()
        
        return Anomaly(
            type: .trafficDrop,
            metric: metric,
            currentValue: current,
            baselineValue: baseline,
            spikePercent: dropPercent * 100,
            timestamp: Date(),
            severity: severity
        )
    }
    
    func reset() {
        currentCounts = TrafficCounts()
        baselineCounts = TrafficCounts()
        anomalies.removeAll()
    }
}
