import Foundation
import Observation

/// Tracks dashboard performance metrics for the performance metrics dashboard.
@MainActor
@Observable
final class PerformanceMetricsStore {
    
    struct APIRequest {
        let endpoint: String
        let duration: TimeInterval
        let success: Bool
        let timestamp: Date
    }
    
    struct RefreshEvent {
        let timestamp: Date
        let duration: TimeInterval
        let sectionsCompleted: Int
        let sectionsFailed: Int
        let success: Bool
    }
    
    struct SectionStats {
        var totalRequests: Int = 0
        var failedRequests: Int = 0
        var totalDuration: TimeInterval = 0
        var averageDuration: TimeInterval {
            totalRequests > 0 ? totalDuration / Double(totalRequests) : 0
        }
        var failureRate: Double {
            totalRequests > 0 ? Double(failedRequests) / Double(totalRequests) : 0
        }
    }
    
    private let maxHistory = 100
    private var apiHistory: [APIRequest] = []
    var refreshHistory: [RefreshEvent] = []
    private var sectionStats: [String: SectionStats] = [:]
    var totalRefreshes: Int = 0
    private var successfulRefreshes: Int = 0
    
    var currentAPILatency: TimeInterval? { apiHistory.last?.duration }
    var lastRefreshDuration: TimeInterval? { refreshHistory.last?.duration }
    var overallSuccessRate: Double {
        totalRefreshes > 0 ? Double(successfulRefreshes) / Double(totalRefreshes) : 1.0
    }
    var averageAPIResponseTime: TimeInterval {
        guard !apiHistory.isEmpty else { return 0 }
        return apiHistory.reduce(0) { $0 + $1.duration } / Double(apiHistory.count)
    }
    var recentRequests: [APIRequest] {
        Array(apiHistory.suffix(20))
    }
    var recentRefreshes: [RefreshEvent] {
        Array(refreshHistory.suffix(10))
    }
    
    func recordAPIRequest(endpoint: String, duration: TimeInterval, success: Bool) {
        let request = APIRequest(endpoint: endpoint, duration: duration, success: success, timestamp: Date())
        apiHistory.append(request)
        if apiHistory.count > maxHistory { apiHistory.removeFirst(apiHistory.count - maxHistory) }
        
        if sectionStats[endpoint] == nil {
            sectionStats[endpoint] = SectionStats()
        }
        sectionStats[endpoint]?.totalRequests += 1
        sectionStats[endpoint]?.totalDuration += duration
        if !success {
            sectionStats[endpoint]?.failedRequests += 1
        }
    }
    
    func recordRefresh(duration: TimeInterval, sectionsCompleted: Int, sectionsFailed: Int, success: Bool) {
        let event = RefreshEvent(
            timestamp: Date(),
            duration: duration,
            sectionsCompleted: sectionsCompleted,
            sectionsFailed: sectionsFailed,
            success: success
        )
        refreshHistory.append(event)
        if refreshHistory.count > maxHistory { refreshHistory.removeFirst(refreshHistory.count - maxHistory) }
        totalRefreshes += 1
        if success { successfulRefreshes += 1 }
    }
    
    func getSectionStats(for endpoint: String) -> SectionStats? {
        sectionStats[endpoint]
    }
    
    func getSlowestEndpoints(count: Int = 5) -> [(endpoint: String, avgDuration: TimeInterval, failureRate: Double)] {
        sectionStats
            .filter { $0.value.totalRequests > 0 }
            .sorted { $0.value.averageDuration > $1.value.averageDuration }
            .prefix(count)
            .map { ($0.key, $0.value.averageDuration, $0.value.failureRate) }
    }
    
    func getSlowestRequests(count: Int = 10) -> [APIRequest] {
        apiHistory
            .sorted { $0.duration > $1.duration }
            .prefix(count)
            .map { $0 }
    }
    
    func reset() {
        apiHistory.removeAll()
        refreshHistory.removeAll()
        sectionStats.removeAll()
        totalRefreshes = 0
        successfulRefreshes = 0
    }
}
