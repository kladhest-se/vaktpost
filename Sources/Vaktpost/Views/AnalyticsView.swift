import SwiftUI

/// View displaying analytics for write operations on the firewall.
///
/// Shows success rates per operation type and overall statistics to help
/// diagnose reliability issues.
struct AnalyticsView: View {

    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dashboardStore) private var store: DashboardStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    overviewCard
                    statisticsByOperation
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(theme.bg.ignoresSafeArea())
            .navigationTitle("Analytics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Overview

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overview")
                .scaledFont(16, weight: .semibold)
                .foregroundStyle(theme.label)

            if store.analytics.totalOperations == 0 {
                Text("No write operations recorded yet.")
                    .scaledFont(13)
                    .foregroundStyle(theme.labelMuted)
            } else {
                HStack(spacing: 20) {
                    statItem(
                        label: "Total",
                        value: "\(store.analytics.totalOperations)",
                        color: theme.label
                    )
                    statItem(
                        label: "Success",
                        value: "\(store.analytics.successfulOperations)",
                        color: theme.ok
                    )
                    statItem(
                        label: "Failed",
                        value: "\(store.analytics.failedOperations)",
                        color: theme.bad
                    )
                }

                if let rate = store.analytics.overallSuccessRate {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Overall success rate")
                                .scaledFont(12)
                                .foregroundStyle(theme.labelMuted)
                            Spacer()
                            Text(formatPercent(rate))
                                .scaledFont(13, weight: .semibold)
                                .foregroundStyle(rate >= 0.9 ? theme.ok : rate >= 0.7 ? theme.warn : theme.bad)
                        }
                        progressBar(rate)
                    }
                }
            }
        }
        .padding(16)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Statistics by Operation

    private var statisticsByOperation: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Operations")
                .scaledFont(14, weight: .semibold)
                .foregroundStyle(theme.label)
                .padding(.horizontal, 4)

            let stats = store.analytics.statisticsByOperation
            let sortedStats = stats.sorted { $0.value.count > $1.value.count }

            ForEach(sortedStats, id: \.key) { operation, stat in
                operationRow(operation: operation, stat: stat)
            }
        }
    }

    private func operationRow(operation: String, stat: WriteAnalytics.OperationStats) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(operation.replacingOccurrences(of: "_", with: " ").capitalized)
                    .scaledFont(13, weight: .medium)
                    .foregroundStyle(theme.label)
                Spacer()
                Text("\(stat.count)")
                    .scaledFont(12, weight: .semibold)
                    .foregroundStyle(theme.labelMuted)
            }

            let rate = Double(stat.successes) / Double(stat.count)
            HStack(spacing: 8) {
                progressBar(rate)
                Text(formatPercent(rate))
                    .scaledFont(11, weight: .medium)
                    .foregroundStyle(rate >= 0.9 ? theme.ok : rate >= 0.7 ? theme.warn : theme.bad)
            }
        }
        .padding(12)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Helpers

    private func statItem(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .center, spacing: 4) {
            Text(value)
                .scaledFont(20, weight: .bold)
                .foregroundStyle(color)
            Text(label)
                .scaledFont(11)
                .foregroundStyle(theme.labelMuted)
        }
    }

    private func progressBar(_ value: Double) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(theme.labelFaint.opacity(0.2))
                Rectangle()
                    .fill(value >= 0.9 ? theme.ok : value >= 0.7 ? theme.warn : theme.bad)
                    .frame(width: geometry.size.width * value)
            }
            .frame(height: 6)
            .cornerRadius(3)
        }
        .frame(height: 6)
    }

    private func formatPercent(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }
}
