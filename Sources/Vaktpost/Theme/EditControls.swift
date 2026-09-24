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
    /// How an option reads, when the stored value is not what to show.
    ///
    /// pfSense stores an interface as `lan` or `opt4`; the webConfigurator,
    /// the tab bar and the address pickers all say LAN and VLAN_100. The
    /// picker stores the key and shows the name.
    var display: ((String) -> String)?

    private func displayText(for option: String) -> String {
        display?(option) ?? option
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .scaledFont(9, weight: .semibold)
                .foregroundStyle(theme.labelFaint)

            Picker("", selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(option.isEmpty ? emptyLabel : displayText(for: option)).tag(option)
                }
                // A value the firewall already holds that is not in the list
                // stays selectable rather than being silently rewritten to the
                // first option the moment somebody opens the editor.
                if !options.contains(selection) {
                    Text(selection.isEmpty ? emptyLabel : displayText(for: selection)).tag(selection)
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
    let aliases: [FirewallAliasEntry]

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

    private var addressAliases: [FirewallAliasEntry] {
        aliases.filter(\.isAddressAlias)
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

            if selectedChoice == .address && !addressAliases.isEmpty {
                AliasPickerButton(
                    title: "Choose address alias",
                    aliases: addressAliases,
                    selection: text
                ) { alias in
                    text = alias.name
                    storageKind = .address
                }
            }
        }
    }
}

/// Free text with an optional searchable alias catalogue underneath. Literal
/// values remain editable; choosing an alias fills the same field rather than
/// introducing a second source of truth.
struct EditAliasField: View {
    let label: String
    @Binding var text: String
    var prompt = ""
    var mono = true
    var keyboard: UIKeyboardType = .default
    let aliases: [FirewallAliasEntry]
    var aliasButtonTitle = "Choose alias"

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            EditField(label: label, text: $text, prompt: prompt,
                      mono: mono, keyboard: keyboard)
            if !aliases.isEmpty {
                AliasPickerButton(title: aliasButtonTitle,
                                  aliases: aliases,
                                  selection: text) { alias in
                    text = alias.name
                }
            }
        }
    }
}

/// Opens a searchable list without forcing every alias into a menu. A large
/// firewall can have hundreds of aliases; a menu that tall is effectively not
/// a picker at all.
struct AliasPickerButton: View {
    @Environment(\.themeManager) private var theme: ThemeManager

    let title: String
    let aliases: [FirewallAliasEntry]
    let selection: String
    let onSelect: (FirewallAliasEntry) -> Void

    @State private var showingAliases = false

    private var selectedAlias: FirewallAliasEntry? {
        aliases.first { $0.name == selection }
    }

    var body: some View {
        Button {
            showingAliases = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "tag")
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .scaledFont(12, weight: .semibold)
                    if let selectedAlias {
                        Text("Selected: \(selectedAlias.name)")
                            .scaledFont(10, design: .monospaced)
                            .foregroundStyle(theme.labelFaint)
                    }
                }
                Spacer()
                Image(systemName: "magnifyingglass")
            }
            .foregroundStyle(theme.accentColor)
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .background(theme.accentColor.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingAliases) {
            AliasSelectionSheet(aliases: aliases, selectedName: selection) { alias in
                onSelect(alias)
                showingAliases = false
            }
        }
    }
}

private struct AliasSelectionSheet: View {
    @Environment(\.themeManager) private var theme: ThemeManager
    @Environment(\.dismiss) private var dismiss

    let aliases: [FirewallAliasEntry]
    let selectedName: String
    let onSelect: (FirewallAliasEntry) -> Void

    @State private var query = ""

    private var matches: [FirewallAliasEntry] {
        aliases.filter { $0.matches(search: query) }
    }

    var body: some View {
        NavigationStack {
            List {
                if matches.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(matches) { alias in
                        Button {
                            onSelect(alias)
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(alias.name)
                                        .scaledFont(14, weight: .semibold,
                                                    design: .monospaced)
                                        .foregroundStyle(theme.label)
                                    HStack(spacing: 7) {
                                        Text(alias.type.isEmpty ? "alias" : alias.type)
                                        Text("\(alias.addresses.count) member\(alias.addresses.count == 1 ? "" : "s")")
                                    }
                                    .scaledFont(10, design: .monospaced)
                                    .foregroundStyle(theme.labelFaint)
                                    if let description = alias.descr, !description.isEmpty {
                                        Text(description)
                                            .scaledFont(11)
                                            .foregroundStyle(theme.labelMuted)
                                    }
                                }
                                Spacer()
                                if alias.name == selectedName {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(theme.accentColor)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(theme.card)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.bg.ignoresSafeArea())
            .searchable(text: $query, prompt: "Name, type, description or member")
            .navigationTitle("Choose alias")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
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
