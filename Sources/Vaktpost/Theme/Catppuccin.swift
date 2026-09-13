import SwiftUI

// MARK: - Hex helper

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: 1.0
        )
    }
}

// MARK: - Flavour

/// The four themes, taken from Catppuccin. Latte is the light one.
enum Theme: String, CaseIterable, Identifiable, Codable {
    case latte, frappe, macchiato, mocha

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .latte: return "Latte"
        case .frappe: return "Frappé"
        case .macchiato: return "Macchiato"
        case .mocha: return "Mocha"
        }
    }

    var isLight: Bool { self == .latte }

    var colorScheme: ColorScheme { isLight ? .light : .dark }

    var palette: Palette { Palette.all[self]! }
}

// MARK: - Accent

/// Every Catppuccin accent colour, selectable independently of the theme.
enum Accent: String, CaseIterable, Identifiable, Codable {
    case rosewater, flamingo, pink, mauve, red, maroon, peach
    case yellow, green, teal, sky, sapphire, blue, lavender

    var id: String { rawValue }

    var displayName: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    func color(in palette: Palette) -> Color {
        switch self {
        case .rosewater: return palette.rosewater
        case .flamingo:  return palette.flamingo
        case .pink:      return palette.pink
        case .mauve:     return palette.mauve
        case .red:       return palette.red
        case .maroon:    return palette.maroon
        case .peach:     return palette.peach
        case .yellow:    return palette.yellow
        case .green:     return palette.green
        case .teal:      return palette.teal
        case .sky:       return palette.sky
        case .sapphire:  return palette.sapphire
        case .blue:      return palette.blue
        case .lavender:  return palette.lavender
        }
    }
}

// MARK: - Palette

struct Palette {
    let rosewater, flamingo, pink, mauve, red, maroon, peach, yellow: Color
    let green, teal, sky, sapphire, blue, lavender: Color
    let text, subtext1, subtext0: Color
    let overlay2, overlay1, overlay0: Color
    let surface2, surface1, surface0: Color
    let base, mantle, crust: Color

    init(_ hexes: [UInt32]) {
        rosewater = Color(hex: hexes[0])
        flamingo  = Color(hex: hexes[1])
        pink      = Color(hex: hexes[2])
        mauve     = Color(hex: hexes[3])
        red       = Color(hex: hexes[4])
        maroon    = Color(hex: hexes[5])
        peach     = Color(hex: hexes[6])
        yellow    = Color(hex: hexes[7])
        green     = Color(hex: hexes[8])
        teal      = Color(hex: hexes[9])
        sky       = Color(hex: hexes[10])
        sapphire  = Color(hex: hexes[11])
        blue      = Color(hex: hexes[12])
        lavender  = Color(hex: hexes[13])
        text      = Color(hex: hexes[14])
        subtext1  = Color(hex: hexes[15])
        subtext0  = Color(hex: hexes[16])
        overlay2  = Color(hex: hexes[17])
        overlay1  = Color(hex: hexes[18])
        overlay0  = Color(hex: hexes[19])
        surface2  = Color(hex: hexes[20])
        surface1  = Color(hex: hexes[21])
        surface0  = Color(hex: hexes[22])
        base      = Color(hex: hexes[23])
        mantle    = Color(hex: hexes[24])
        crust     = Color(hex: hexes[25])
    }

    static let all: [Theme: Palette] = [
        .latte: Palette([
            0xdc8a78, 0xdd7878, 0xea76cb, 0x8839ef, 0xd20f39, 0xe64553, 0xfe640b, 0xdf8e1d,
            0x40a02b, 0x179299, 0x04a5e5, 0x209fb5, 0x1e66f5, 0x7287fd,
            0x4c4f69, 0x5c5f77, 0x6c6f85,
            0x7c7f93, 0x8c8fa1, 0x9ca0b0,
            0xacb0be, 0xbcc0cc, 0xccd0da,
            0xeff1f5, 0xe6e9ef, 0xdce0e8,
        ]),
        .frappe: Palette([
            0xf2d5cf, 0xeebebe, 0xf4b8e4, 0xca9ee6, 0xe78284, 0xea999c, 0xef9f76, 0xe5c890,
            0xa6d189, 0x81c8be, 0x99d1db, 0x85c1dc, 0x8caaee, 0xbabbf1,
            0xc6d0f5, 0xb5bfe2, 0xa5adce,
            0x949cbb, 0x838ba7, 0x737994,
            0x626880, 0x51576d, 0x414559,
            0x303446, 0x292c3c, 0x232634,
        ]),
        .macchiato: Palette([
            0xf4dbd6, 0xf0c6c6, 0xf5bde6, 0xc6a0f6, 0xed8796, 0xee99a0, 0xf5a97f, 0xeed49f,
            0xa6da95, 0x8bd5ca, 0x91d7e3, 0x7dc4e4, 0x8aadf4, 0xb7bdf8,
            0xcad3f5, 0xb8c0e0, 0xa5adcb,
            0x939ab7, 0x8087a2, 0x6e738d,
            0x5b6078, 0x494d64, 0x363a4f,
            0x24273a, 0x1e2030, 0x181926,
        ]),
        .mocha: Palette([
            0xf5e0dc, 0xf2cdcd, 0xf5c2e7, 0xcba6f7, 0xf38ba8, 0xeba0ac, 0xfab387, 0xf9e2af,
            0xa6e3a1, 0x94e2d5, 0x89dceb, 0x74c7ec, 0x89b4fa, 0xb4befe,
            0xcdd6f4, 0xbac2de, 0xa6adc8,
            0x9399b2, 0x7f849c, 0x6c7086,
            0x585b70, 0x45475a, 0x313244,
            0x1e1e2e, 0x181825, 0x11111b,
        ]),
    ]
}
