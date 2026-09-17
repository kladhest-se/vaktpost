import SwiftUI

/// A sign-in failure, stated plainly with what to do next.
///
/// Used where a firewall is added or edited and in place of the dashboard, so
/// the same failure reads the same way wherever it is met. Status is carried
/// by the symbol and the title as well as the colour.
struct AuthenticationProblemCard: View {
    @Environment(\.themeManager) private var theme: ThemeManager

    let problem: AuthenticationProblem

    var body: some View {
        Slab(rail: .bad) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: problem.symbol)
                        .scaledFont(17, weight: .semibold)
                        .foregroundStyle(theme.bad)
                        .accessibilityHidden(true)
                    Text(problem.title)
                        .scaledFont(17, weight: .semibold)
                        .foregroundStyle(theme.label)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)

                Text(problem.summary)
                    .scaledFont(13)
                    .foregroundStyle(theme.labelMuted)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(problem.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1).")
                                .scaledFont(12, weight: .semibold, design: .rounded)
                                .foregroundStyle(theme.label)
                            Text(step)
                                .scaledFont(12)
                                .foregroundStyle(theme.label)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }

                if let note = problem.note {
                    Text(note)
                        .scaledFont(11)
                        .foregroundStyle(theme.labelFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
