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

/// A pfSense address selector which preserves how the value is represented in
/// `config.xml`. System selectors are closed choices; only literal addresses,
/// networks and user aliases use free text.
struct EditAddress: View {
    @Environment(\.themeManager) private var theme: ThemeManager

    let label: String
    @Binding var text: String
    @Binding var storageKind: FilterAddress.StorageKind
    let interfaces: [InterfaceStat]

    private enum Choice: Hashable {
        case any
        case address
        case network
        case system(String)
    }

    private var interfaceKeys: [String] {
        interfaces.compactMap(\.internalName)
    }

    private var knownSystemValues: Set<String> {
        var values: Set<String> = ["self", "pptp", "pppoe", "l2tp"]
        for key in interfaceKeys {
            values.insert(key.lowercased())
            values.insert("\(key.lowercased())ip")
        }
        return values
    }

    private var selectedChoice: Choice {
        switch storageKind {
        case .any:
            return .any
        case .network:
            return .system(text)
        case .address:
            return text.contains("/") ? .network : .address
        }
    }

    private var choice: Binding<Choice> {
        Binding(
            get: { selectedChoice },
            set: { selected in
                switch selected {
                case .any:
                    text = "any"
                    storageKind = .any
                case .address, .network:
                    if selectedChoice != selected { text = "" }
                    // Literal networks are stored as address/mask by pfSense;
                    // `network` is reserved for its system selectors.
                    storageKind = .address
                case .system(let value):
                    text = value
                    storageKind = .network
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .scaledFont(9, weight: .semibold)
                .foregroundStyle(theme.labelFaint)

            Picker("", selection: choice) {
                Text("Any").tag(Choice.any)
                Text("Address or Alias").tag(Choice.address)
                Text("Network").tag(Choice.network)
                Text("This Firewall (self)").tag(Choice.system("self"))
                Text("PPTP clients").tag(Choice.system("pptp"))
                Text("PPPoE clients").tag(Choice.system("pppoe"))
                Text("L2TP clients").tag(Choice.system("l2tp"))
                ForEach(interfaces) { interface in
                    if let key = interface.internalName {
                        Text("\(interface.name) address").tag(Choice.system("\(key)ip"))
                        Text("\(interface.name) subnets").tag(Choice.system(key))
                    }
                }
                if storageKind == .network && !knownSystemValues.contains(text.lowercased()) {
                    Text("Existing system selector: \(text)").tag(Choice.system(text))
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

            if selectedChoice == .address || selectedChoice == .network {
                TextField(selectedChoice == .network ? "192.0.2.0/24" : "Address or alias",
                          text: $text)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .scaledFont(14, design: .monospaced)
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
