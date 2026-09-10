import SwiftUI

/// Shows the age of the data, never the time another section last succeeded.
struct FreshnessView: View {
    @Environment(\.dashboardStore) private var store: DashboardStore
    @Environment(\.themeManager) private var theme: ThemeManager
    let sections: [DashboardStore.Section]
    var showNames = false

    var body: some View {
        EmptyView()
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
