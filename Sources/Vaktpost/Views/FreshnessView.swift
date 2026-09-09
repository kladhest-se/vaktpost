import SwiftUI

/// Shows the age of the data, never the time another section last succeeded.
struct FreshnessView: View {
    @EnvironmentObject private var store: DashboardStore
    @EnvironmentObject private var theme: ThemeManager
    let sections: [DashboardStore.Section]
    var showNames = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            VStack(alignment: .leading, spacing: 4) {
                ForEach(sections, id: \.self) { section in
                    let state = store.freshness[section] ?? SectionFreshness()
                    let stale = state.isStale(at: context.date,
                        interval: section == .rrd ? 150 : Double(store.profile.refreshSeconds))
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Image(systemName: state.failure != nil ? "exclamationmark.triangle" : "clock")
                        if showNames { Text("\(section.displayName):") }
                        if let date = state.lastSuccess {
                            Text(state.failure != nil ? "Update failed · last success" : stale ? "Stale · updated" : "Updated")
                            Text(date, style: .relative)
                            Text("ago")
                        } else {
                            Text(state.failure != nil ? "Could not load" : state.requestID != nil ? "Loading…" : "Not loaded")
                        }
                        if state.requestID != nil && state.lastSuccess != nil {
                            Text("· refreshing")
                        }
                    }
                    .scaledFont(10)
                    .foregroundStyle(state.failure != nil || (stale && state.lastSuccess != nil)
                                     ? theme.warn : theme.labelFaint)
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension View {
    func sectionFreshness(_ sections: [DashboardStore.Section]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            self
            FreshnessView(sections: sections)
                .padding(.horizontal, 4)
        }
    }
}

struct DataFreshnessView: View {
    @EnvironmentObject private var store: DashboardStore
    @EnvironmentObject private var theme: ThemeManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Each section keeps its own last successful update. A failed request keeps its earlier data and does not reset that time. Sections opened on demand may not have loaded yet.")
                    .scaledFont(12)
                    .foregroundStyle(theme.labelMuted)
                ForEach(DashboardStore.Section.allCases, id: \.self) { section in
                    Slab(rail: store.freshness[section]?.failure == nil ? .idle : .warn,
                         title: section.displayName) {
                        FreshnessView(sections: [section])
                        if let error = store.freshness[section]?.failure {
                            Text(error).scaledFont(11).foregroundStyle(theme.warn)
                        }
                    }
                }
            }
            .padding(16)
            .readableWidth()
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationTitle("Data freshness")
        .refreshable { await store.refreshManually() }
    }
}
