import SwiftUI
import UIKit

/// The six icons the app ships with.
///
/// Coral is the primary one in the asset catalog; the other five are loose
/// files in the bundle, which is what `setAlternateIconName` resolves. Coral is
/// therefore represented by `nil` — asking iOS for "coral" by name would fail,
/// because the primary icon is not an alternate.
enum AppIcon: String, CaseIterable, Identifiable {
    case coral, ocean, mint, amber, lavender, silver

    var id: String { rawValue }

    var displayName: String { rawValue.capitalized }

    /// What `setAlternateIconName` wants. `nil` restores the primary.
    var alternateName: String? {
        self == .coral ? nil : "Icon-\(rawValue)"
    }

    /// The preview image in the picker, read from the bundle rather than the
    /// asset catalog so the same files serve both purposes.
    var previewName: String { "Preview-\(rawValue)" }

    static var current: AppIcon {
        guard let name = UIApplication.shared.alternateIconName else { return .coral }
        return allCases.first { $0.alternateName == name } ?? .coral
    }
}

struct AppIconPicker: View {
    @EnvironmentObject private var theme: ThemeManager

    @State private var selected: AppIcon = .current
    @State private var failure: String?

    private let columns = [GridItem(.adaptive(minimum: 62), spacing: 12)]

    var body: some View {
        Slab(rail: .info) {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(AppIcon.allCases) { icon in
                        Button { choose(icon) } label: {
                            VStack(spacing: 5) {
                                Image(icon.previewName)
                                    .resizable()
                                    .frame(width: 54, height: 54)
                                    .clipShape(RoundedRectangle(cornerRadius: 12,
                                                               style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(selected == icon
                                                    ? theme.accentColor : .clear,
                                                    lineWidth: 2)
                                    )
                                Text(icon.displayName)
                                    .font(.system(size: 10))
                                    .foregroundStyle(selected == icon
                                                     ? theme.label : theme.labelFaint)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let failure {
                    Text(failure)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.warn)
                }
            }
        }
    }

    private func choose(_ icon: AppIcon) {
        guard icon != selected else { return }
        // Not supported on every device iOS 17 runs on, and the call reports
        // that rather than silently doing nothing — so the failure is shown
        // instead of leaving a tap that appears to have worked.
        guard UIApplication.shared.supportsAlternateIcons else {
            failure = "This device does not allow changing the app icon."
            return
        }
        UIApplication.shared.setAlternateIconName(icon.alternateName) { error in
            Task { @MainActor in
                if let error {
                    failure = error.localizedDescription
                    selected = .current
                } else {
                    failure = nil
                    selected = icon
                }
            }
        }
        selected = icon
    }
}
