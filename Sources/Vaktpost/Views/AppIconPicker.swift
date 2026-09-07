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

    /// An icon iOS refused, kept until it will accept it.
    @State private var pending: AppIcon?
    @Environment(\.scenePhase) private var scenePhase

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
                } else if let pending {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath")
                            .scaledFont(11)
                        Text("\(pending.displayName) will be applied when the app next becomes active.")
                            .scaledFont(11)
                    }
                    .foregroundStyle(theme.labelMuted)
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
                         : "Registered: \(registeredNames.joined(separator: ", "))")
                        .scaledFont(10, design: .monospaced)
                        .foregroundStyle(theme.labelFaint)
                        .textSelection(.enabled)
                }
            }
        }
        // The moment iOS said it was not ready for. Coming back to the app is
        // reliably `.foregroundActive`, which a tap inside a pushed screen
        // apparently is not always.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, let icon = pending else { return }
            pending = nil
            apply(icon)
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
        apply(icon)
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
    /// Sets the icon once the app is genuinely able to accept it.
    ///
    /// `EAGAIN` from `setAlternateIconName` means iOS declined at that moment,
    /// and the moment that matters is the scene's state. The call is refused
    /// unless the app is `.foregroundActive` — which it is not during a
    /// navigation push, a sheet presentation, or while Settings is still
    /// animating in. A tap that lands in one of those windows fails, and
    /// retrying 0.6s later fails again if the animation is still running.
    ///
    /// So this waits for the app to actually be active rather than guessing at
    /// a delay, and only then calls. If it is already active the wait is a
    /// single runloop turn.
    /// Sets the icon, and remembers the request if iOS refuses.
    ///
    /// `setAlternateIconName` returns `EAGAIN` when it will not act now. The
    /// documented reason is that the app is not `.foregroundActive`, but that
    /// has not been the whole story here: it kept refusing on a device where
    /// the app was plainly in front, with all five alternates registered.
    ///
    /// Rather than keep guessing at delays, an unhappy attempt is *stored* and
    /// retried when the app next becomes active. Leaving Settings and coming
    /// back applies it. That turns a failure the person cannot do anything
    /// about into one they can, and it costs nothing when the call works
    /// first time.
    private func apply(_ icon: AppIcon, attempt: Int = 0) {
        DispatchQueue.main.async {
            guard UIApplication.shared.applicationState == .active else {
                guard attempt < 6 else {
                    pending = icon
                    failure = "Waiting until the app is active — leave Settings and come back."
                    isChanging = false
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    apply(icon, attempt: attempt + 1)
                }
                return
            }

            UIApplication.shared.setAlternateIconName(icon.alternateName) { error in
                Task { @MainActor in
                    guard let error else {
                        pending = nil
                        failure = nil
                        selected = icon
                        isChanging = false
                        return
                    }

                    let ns = error as NSError
                    if ns.code == Int(EAGAIN), attempt < 6 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            apply(icon, attempt: attempt + 1)
                        }
                        return
                    }

                    if isSimulator {
                        // Not worth retrying and not the person's problem.
                        // Saying "try again in a moment" here would be a
                        // suggestion that can never work.
                        pending = nil
                        failure = "The simulator cannot change app icons. This works on a device."
                    } else if ns.code == Int(EAGAIN) {
                        pending = icon
                        failure = "iOS would not change it just now. Leave Settings and come back and it will be applied."
                    } else {
                        // Domain and code as well as the message: "the
                        // operation couldn't be completed" is the same
                        // sentence for a dozen different problems, and
                        // knowing which one is the whole difficulty here.
                        failure = "\(ns.localizedDescription) (\(ns.domain) \(ns.code))"
                        pending = nil
                    }
                    selected = .current
                    isChanging = false
                }
            }
        }
    }
}
