import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var store: DashboardStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GroupHeading(text: "Appearance")
                themeModeSlab
                flavourSlab
                accentSlab

                GroupHeading(text: "About")
                aboutSlab
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationTitle("Settings")
    }

    private var themeModeSlab: some View {
        Slab(rail: .info, title: "Theme mode") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("", selection: Binding(
                    get: { theme.mode },
                    set: { theme.mode = $0 }
                )) {
                    ForEach(ThemeManager.Mode.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)

                Text(theme.mode == .followSystem
                     ? "Uses your light flavour in light mode and your dark flavour in dark mode."
                     : "Always uses the flavour you pick below, whatever iOS is set to.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.labelFaint)
            }
        }
    }

    private var flavourSlab: some View {
        Slab(rail: .info, title: "Flavour") {
            VStack(alignment: .leading, spacing: 14) {
                if theme.mode == .fixed {
                    flavourGrid(selection: Binding(
                        get: { theme.fixedFlavor },
                        set: { theme.fixedFlavor = $0 }
                    ))
                } else {
                    Text("Light appearance")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.labelMuted)
                    flavourGrid(selection: Binding(
                        get: { theme.lightFlavor },
                        set: { theme.lightFlavor = $0 }
                    ))
                    Hairline()
                    Text("Dark appearance")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.labelMuted)
                    flavourGrid(selection: Binding(
                        get: { theme.darkFlavor },
                        set: { theme.darkFlavor = $0 }
                    ))
                }
            }
        }
    }

    private func flavourGrid(selection: Binding<Flavor>) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(Flavor.allCases) { flavor in
                FlavorSwatch(flavor: flavor, isSelected: selection.wrappedValue == flavor)
                    .onTapGesture { selection.wrappedValue = flavor }
            }
        }
    }

    private var accentSlab: some View {
        Slab(rail: .info, title: "Accent") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 7), spacing: 12) {
                ForEach(Accent.allCases) { accent in
                    Circle()
                        .fill(accent.color(in: theme.palette))
                        .frame(height: 30)
                        .overlay(
                            Circle()
                                .strokeBorder(theme.label, lineWidth: theme.accent == accent ? 2.5 : 0)
                                .padding(-3)
                        )
                        .onTapGesture { theme.accent = accent }
                        .accessibilityLabel(accent.displayName)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var aboutSlab: some View {
        Slab(rail: .info, title: "Vaktpost") {
            VStack(alignment: .leading, spacing: 8) {
                Text("A read-only dashboard for pfSense CE and Plus, talking to the community REST API package over /api/v2.")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.labelMuted)
                Hairline()
                FieldRow(key: "Requires", value: "pfSense-pkg-RESTAPI", mono: false)
                FieldRow(key: "Auth", value: "X-API-Key", mono: false)
                FieldRow(key: "Writes", value: "none", mono: false)
                FieldRow(key: "Firewalls", value: "\(store.registry.servers.count)", mono: false)
                Text("Not affiliated with Netgate or the Catppuccin project. pfSense is a trademark of Netgate.")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.labelFaint)
            }
        }
    }
}

struct FlavorSwatch: View {
    @EnvironmentObject private var theme: ThemeManager
    let flavor: Flavor
    let isSelected: Bool

    var body: some View {
        let p = flavor.palette
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(flavor.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(p.text)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(p.green)
                }
            }
            HStack(spacing: 4) {
                ForEach([p.red, p.peach, p.yellow, p.green, p.sapphire, p.mauve], id: \.self) { c in
                    Capsule().fill(c).frame(height: 8)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(p.base)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? theme.accentColor : p.surface1, lineWidth: isSelected ? 2 : 1)
        )
    }
}
