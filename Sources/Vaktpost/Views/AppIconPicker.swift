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

    /// What `setAlternateIconName` wants: the icon *set* name from the asset
    /// catalog, which is what Xcode registers. `nil` restores the primary.
    var alternateName: String? {
        self == .coral ? nil : "AppIcon-\(rawValue)"
    }

    /// The preview shown in the picker. A separate image set, because an app
    /// icon set is not loadable as an ordinary image.
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
    @State private var isChanging = false

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

                if isChanging {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("Changing…")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.labelFaint)
                    }
                } else if let failure {
                    Text(failure)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.warn)
                }

                // What iOS registered, when nothing is wrong but it is worth
                // being able to see. Only shown if the build is missing icons,
                // which is the case a person cannot otherwise diagnose.
                if registeredNames.count < AppIcon.allCases.count - 1 {
                    Text("This build registered \(registeredNames.count) of \(AppIcon.allCases.count - 1) alternate icons.")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.labelFaint)
                }
            }
        }
    }

    /// Alternate icon names this build actually registered.
    ///
    /// Xcode writes these into `CFBundleIcons` from the catalog setting, and
    /// `setAlternateIconName` will only accept a name that appears here. If
    /// the build did not include the icon sets the call fails with a generic
    /// error that says nothing about why — so this checks first and says which
    /// problem it is.
    private var registeredNames: [String] {
        guard let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
              let alternates = icons["CFBundleAlternateIcons"] as? [String: Any] else {
            return []
        }
        return alternates.keys.sorted()
    }

    private func choose(_ icon: AppIcon) {
        guard icon != selected, !isChanging else { return }

        guard UIApplication.shared.supportsAlternateIcons else {
            failure = "This device does not allow changing the app icon."
            return
        }

        if let name = icon.alternateName, !registeredNames.contains(name) {
            // The build is missing the icon, which is a packaging problem and
            // not something tapping again will fix.
            failure = registeredNames.isEmpty
                ? "This build contains no alternate icons."
                : "This build has \(registeredNames.joined(separator: ", ")) but not \(name)."
            return
        }

        isChanging = true
        failure = nil
        apply(icon, retryOnBusy: true)
    }

    /// Sets the icon, retrying once if iOS says it is busy.
    ///
    /// `setAlternateIconName` returns `EAGAIN` — "resource temporarily
    /// unavailable" — when it is called while the app is not fully in the
    /// foreground or while another change is still settling. That is a
    /// transient condition rather than a refusal, and one retry after a moment
    /// usually clears it. Deferring to the next runloop turn matters too: the
    /// call is made from inside a SwiftUI update otherwise, which is one of
    /// the states it declines from.
    private func apply(_ icon: AppIcon, retryOnBusy: Bool) {
        DispatchQueue.main.async {
            UIApplication.shared.setAlternateIconName(icon.alternateName) { error in
                Task { @MainActor in
                    guard let error else {
                        failure = nil
                        selected = icon
                        isChanging = false
                        return
                    }

                    let code = (error as NSError).code
                    if retryOnBusy, code == Int(EAGAIN) {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            apply(icon, retryOnBusy: false)
                        }
                        return
                    }

                    failure = code == Int(EAGAIN)
                        ? "iOS was busy and would not change the icon. Try again in a moment, or from the Home Screen rather than while the app is opening."
                        : error.localizedDescription
                    selected = .current
                    isChanging = false
                }
            }
        }
    }
}
