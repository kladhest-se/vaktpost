import SwiftUI

struct PerformanceView: View {
    @Environment(\.dashboardStore) private var store: DashboardStore
    @Environment(\.themeManager) private var theme: ThemeManager
    @State private var metrics = PerformanceMetricsStore()
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabPicker(selectedTab: $selectedTab)
                
                ScrollView {
                    VStack(spacing: 16) {
                        switch selectedTab {
                        case 0:
                            overviewMetrics
                        case 1:
                            endpointMetrics
                        case 2:
                            refreshHistory
                        default:
                            overviewMetrics
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Performance")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private var overviewMetrics: some View {
        VStack(spacing: 12) {
            HStack {
                MetricCard(title: "Overall Success", value: "\(Int(metrics.overallSuccessRate * 100))%", color: metrics.overallSuccessRate > 0.9 ? .green : metrics.overallSuccessRate > 0.7 ? .yellow : .red)
                MetricCard(title: "Avg API Latency", value: "\(String(format: "%.1f", metrics.averageAPIResponseTime * 1000))ms", color: metrics.averageAPIResponseTime < 1 ? .green : metrics.averageAPIResponseTime < 3 ? .yellow : .red)
            }
            
            HStack {
                MetricCard(title: "Total Refreshes", value: "\(metrics.totalRefreshes)", color: theme.label)
                MetricCard(title: "Failed Sections", value: "\(metrics.refreshHistory.reduce(0) { $0 + $1.sectionsFailed })", color: metrics.refreshHistory.reduce(0) { $0 + $1.sectionsFailed } > 0 ? .orange : theme.label)
            }
            
            if let lastLatency = metrics.currentAPILatency {
                MetricCard(title: "Current API Latency", value: "\(String(format: "%.1f", lastLatency * 1000))ms", color: lastLatency < 1 ? .green : lastLatency < 3 ? .yellow : .red)
            }
            
            if let lastDuration = metrics.lastRefreshDuration {
                MetricCard(title: "Last Refresh", value: "\(String(format: "%.1f", lastDuration))s", color: lastDuration < 10 ? .green : lastDuration < 20 ? .yellow : .red)
            }
        }
    }
    
    private var endpointMetrics: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Slowest Endpoints")
                .scaledFont(14, weight: .semibold)
                .foregroundStyle(theme.label)
            
            ForEach(metrics.getSlowestEndpoints(), id: \.0) { endpoint, avgDuration, failureRate in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(endpoint)
                            .scaledFont(13, weight: .medium)
                            .foregroundStyle(theme.label)
                        Spacer()
                        Text("\(String(format: "%.1f", avgDuration * 1000))ms avg")
                            .scaledFont(12)
                            .foregroundStyle(theme.labelMuted)
                    }
                    
                    if failureRate > 0 {
                        HStack {
                            Text("Failure rate: \(String(format: "%.0f", failureRate * 100))%")
                                .scaledFont(11)
                                .foregroundStyle(failureRate > 0.1 ? .red : .orange)
                            Spacer()
                        }
                    }
                }
                .padding(8)
                .background(theme.labelFaint.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            }
            
            if metrics.getSlowestEndpoints().isEmpty {
                Text("No endpoint data yet")
                    .scaledFont(13)
                    .foregroundStyle(theme.labelFaint)
                    .padding(.vertical, 20)
            }
        }
    }
    
    private var refreshHistory: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Refreshes")
                .scaledFont(14, weight: .semibold)
                .foregroundStyle(theme.label)
            
            ForEach(metrics.recentRefreshes.reversed(), id: \.timestamp) { event in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.timestamp.formatted(date: .abbreviated, time: .shortened))
                            .scaledFont(12)
                            .foregroundStyle(theme.label)
                        Text("\(event.sectionsCompleted) completed, \(event.sectionsFailed) failed")
                            .scaledFont(11)
                            .foregroundStyle(theme.labelMuted)
                    }
                    Spacer()
                    Text("\(String(format: "%.1f", event.duration))s")
                        .scaledFont(12, weight: .medium)
                        .foregroundStyle(event.success ? theme.ok : theme.bad)
                }
                .padding(8)
                .background(theme.labelFaint.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            }
            
            if metrics.recentRefreshes.isEmpty {
                Text("No refresh data yet")
                    .scaledFont(13)
                    .foregroundStyle(theme.labelFaint)
                    .padding(.vertical, 20)
            }
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .scaledFont(11)
                .foregroundStyle(Color.primary.opacity(0.6))
            Text(value)
                .scaledFont(18, weight: .bold)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.systemBackground).opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

private struct TabPicker: View {
    @Binding var selectedTab: Int
    
    var body: some View {
        HStack(spacing: 0) {
            TabButton(title: "Overview", isSelected: selectedTab == 0) { selectedTab = 0 }
            TabButton(title: "Endpoints", isSelected: selectedTab == 1) { selectedTab = 1 }
            TabButton(title: "History", isSelected: selectedTab == 2) { selectedTab = 2 }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground))
    }
}

private struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .scaledFont(13, weight: isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? Color.blue : .secondary)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
        }
        .background(isSelected ? Color(.systemGray5) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    PerformanceView()
}
