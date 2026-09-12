import SwiftUI

/// Text input that looks like the rest of the app.
///
/// The editors were bare SwiftUI `Form`s, which is why they arrived in system
/// grey with system fonts in the middle of a Catppuccin dashboard: `Form`
/// brings its own background, its own row insets and its own typography, and
/// none of them can be reached from the theme.
///
/// These are built from the same tokens every other surface uses, so the
/// editor is the app rather than a sheet that escaped it.
struct EditField: View {
    @Environment(\.themeManager) private var theme: ThemeManager

    let label: String
    @Binding var text: String
    var prompt: String = ""
    /// Addresses, ports and protocols are monospaced; a description is not.
    var mono: Bool = true
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .scaledFont(9, weight: .semibold)
                .foregroundStyle(theme.labelFaint)

            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                // Off for all of these. Autocorrect on an address field turns
                // `10.0.0.1` into prose and a typo here is pushed to a
                // firewall.
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(keyboard)
                .scaledFont(14, design: mono ? .monospaced : .default)
                .foregroundStyle(theme.label)
                .padding(.vertical, 9)
                .padding(.horizontal, 10)
                .background(theme.cardRaised)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(theme.hairline, lineWidth: 1)
                )
        }
    }
}

/// A choice between known values.
///
/// The editors took `type`, `protocol` and `interface` as free text, with the
/// accepted values written into the placeholder — "Type (pass/block/reject)".
/// A typo in any of them is a malformed rule sent to a firewall, and the
/// firewall is the thing that finds out. Where the vocabulary is closed, the
/// control should be too.
struct EditChoice: View {
    @Environment(\.themeManager) private var theme: ThemeManager

    let label: String
    let options: [String]
    @Binding var selection: String
    /// Shown for the empty option, which usually means "any".
    var emptyLabel = "any"

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .scaledFont(9, weight: .semibold)
                .foregroundStyle(theme.labelFaint)

            Picker("", selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(option.isEmpty ? emptyLabel : option).tag(option)
                }
                // A value the firewall already holds that is not in the list
                // stays selectable rather than being silently rewritten to the
                // first option the moment somebody opens the editor.
                if !options.contains(selection) {
                    Text(selection.isEmpty ? emptyLabel : selection).tag(selection)
                }
            }
            .pickerStyle(.menu)
            .tint(theme.accentColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
            .padding(.horizontal, 6)
            .background(theme.cardRaised)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(theme.hairline, lineWidth: 1)
            )
        }
    }
}

/// A labelled switch in the app's own type and colour.
struct EditToggle: View {
    @Environment(\.themeManager) private var theme: ThemeManager

    let label: String
    var detail: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .scaledFont(14)
                    .foregroundStyle(theme.label)
                if let detail {
                    Text(detail)
                        .scaledFont(11)
                        .foregroundStyle(theme.labelFaint)
                }
            }
        }
        .tint(theme.accentColor)
    }
}

/// The vocabularies the firewall accepts.
///
/// Kept next to the controls that offer them rather than spelled out in a
/// placeholder string in each editor.
enum FirewallVocabulary {
    static let ruleTypes = ["pass", "block", "reject"]
    static let protocols = ["any", "tcp", "udp", "tcp/udp", "icmp", "esp", "gre"]
    static let addressFamilies = ["inet", "inet6", "inet46"]

    static func familyLabel(_ raw: String) -> String {
        switch raw {
        case "inet": return "IPv4"
        case "inet6": return "IPv6"
        case "inet46": return "IPv4 + IPv6"
        default: return raw
        }
    }
}
