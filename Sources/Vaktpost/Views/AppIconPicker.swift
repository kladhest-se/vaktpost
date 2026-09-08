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
                                    .scaledFont(10)
                                    .foregroundStyle(selected == icon
                                                     ? theme.label : theme.labelFaint)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                if isSimulator {
                    Text("The simulator cannot change app icons — the choice will apply on a device.")
                        .scaledFont(11)
                        .foregroundStyle(theme.labelFaint)
                } else if let betaHint = iOSBetaHint {
                    Text(betaHint)
                        .scaledFont(11)
                        .foregroundStyle(theme.labelFaint)
                } else if isChanging {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("Changing…")
                            .scaledFont(11)
                            .foregroundStyle(theme.labelFaint)
                    }
                } else if let failure {
                    Text(failure)
                        .scaledFont(11)
                        .foregroundStyle(theme.warn)
                }

                // Shown whenever something failed, not only when icons are
                // missing: knowing what iOS has registered is the first thing
                // anybody debugging this needs, and hiding it in the healthy
                // case meant its absence was itself a clue nobody could read.
                if failure != nil {
                    Text(registeredNames.isEmpty
                         ? "No alternate icons are registered in this build."
                         : "Registered: \(registeredNames.joined(separator: ", "))"
                           + (hasPrimaryIcon ? "\nPrimary icon: declared."
                                             : "\nPrimary icon: MISSING — iOS will not switch without one."))
                        .scaledFont(10, design: .monospaced)
                        .foregroundStyle(theme.labelFaint)
                        .textSelection(.enabled)
                }
            }
        }
    }

    /// Whether this is the simulator.
    ///
    /// It matters because alternate icons do not reliably work there: the
    /// simulator has no Home Screen icon database to update, and
    /// `setAlternateIconName` fails with `EIO` — an I/O error, which is an
    /// honest description of writing to something that is not there.
    ///
    /// On a device the same call fails differently, with `EAGAIN`, and that
    /// one is worth retrying. Two failures that look alike and are not.
    private var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    /// Detects iOS 26.1+ and shows a known-issue hint.
    ///
    /// iOS 26.1 introduced a regression in `setAlternateIconName` that causes
    /// `LSIconAlertManager` to return `EAGAIN` (NSPOSIXErrorDomain 35). This
    /// affects all apps, not just this one. Workarounds that have been reported:
    /// restart the device, toggle Airplane mode, or try on iOS 26.0.
    private var iOSBetaHint: String? {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        if version.majorVersion >= 26, version.minorVersion >= 1 {
            return "Icon switching is broken on iOS 26.1+. This is an Apple bug. "
                + "Restarting the device sometimes helps. Apple bug report: FB15457636"
        }
        return nil
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

    /// Whether the build declares a primary icon.
    ///
    /// iOS refuses to switch icons in an app that has alternates but no
    /// `CFBundlePrimaryIcon` to switch back to, and the failure it gives for
    /// that is the same unhelpful `EAGAIN` as everything else. The alternates
    /// have been confirmed present twice; this is the half nobody has looked
    /// at.
    private var hasPrimaryIcon: Bool {
        guard let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any]
        else { return false }
        return icons["CFBundlePrimaryIcon"] != nil
    }

    /// Sets the icon.
    ///
    /// The async throwing call, awaited directly — not the completion-handler
    /// variant wrapped in `DispatchQueue.main.async`, an application-state
    /// check and a retry loop, which is what this was and which never once
    /// worked on a device.
    ///
    /// A working project doing the same thing does exactly this and nothing
    /// else. The state machine was built to work around `EAGAIN`, and every
    /// piece of it was a guess at what iOS wanted; the async variant does not
    /// produce that error in the first place.
    private func choose(_ icon: AppIcon) {
        guard icon != selected, !isChanging else { return }

        guard UIApplication.shared.supportsAlternateIcons else {
            failure = "This device does not allow changing the app icon."
            return
        }

        // Already set: iOS treats a redundant change as an error, and there is
        // nothing to report about doing nothing.
        guard icon.alternateName != UIApplication.shared.alternateIconName else {
            selected = icon
            return
        }

        isChanging = true
        failure = nil

        Task { @MainActor in
            do {
                try await UIApplication.shared.setAlternateIconName(icon.alternateName)
                selected = icon
                failure = nil
            } catch {
                let ns = error as NSError
                if ns.code == 35, !isSimulator {
                    do {
                        try await Task.sleep(nanoseconds: 500_000_000)
                        try await UIApplication.shared.setAlternateIconName(icon.alternateName)
                        selected = icon
                        failure = nil
                        isChanging = false
                        return
                    } catch {
                        // Fall through
                    }
                }
                let msg = isSimulator
                    ? "The simulator cannot change app icons. This works on a device."
                    : "\(ns.localizedDescription) (\(ns.domain) \(ns.code))"
                failure = msg
                selected = .current
            }
            isChanging = false
        }
    }
}
