import SwiftUI

// MARK: - Hex color

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let r, g, b, a: UInt64
        switch h.count {
        case 8: (r, g, b, a) = (int >> 24 & 0xff, int >> 16 & 0xff, int >> 8 & 0xff, int & 0xff)
        default: (r, g, b, a) = (int >> 16 & 0xff, int >> 8 & 0xff, int & 0xff, 255)
        }
        self.init(.sRGB,
                  red: Double(r) / 255, green: Double(g) / 255,
                  blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

// MARK: - Design tokens (ported from the AfterMeet design system)

enum Theme {
    // surfaces
    static let white       = Color(hex: "ffffff")
    static let warmWhite   = Color(hex: "f6f5f4")
    static let warmWhite2  = Color(hex: "efeeea")
    static let paper300    = Color(hex: "e4e2dd")
    static let pageBg      = Color(hex: "f0efec")
    static let canvas      = Color(hex: "fbfaf9")
    static let sidebarBg   = Color(hex: "fdfcfa")
    static let searchBg    = Color(hex: "fafafa")

    // ink / text
    static let inkPrimary   = Color.black.opacity(0.95)
    static let inkSecondary = Color(hex: "615d59")
    static let inkTertiary  = Color(hex: "87857f")
    static let inkMuted     = Color(hex: "a39e98")
    static let ink1000      = Color(hex: "141413")
    static let ink900       = Color(hex: "1f1f1d")
    static let ink800       = Color(hex: "31302e")
    static let ink700       = Color(hex: "4d4c48")
    static let onDark       = Color(hex: "fafaf8")
    static let onDarkDim    = Color(hex: "c8c6c0")

    // blue (info)
    static let blue50  = Color(hex: "f2f9ff")
    static let blue100 = Color(hex: "d9ecff")
    static let blue500 = Color(hex: "0075de")
    static let blue600 = Color(hex: "005bab")
    static let blue700 = Color(hex: "003f78")

    // brand (warm accent)
    static let brand50  = Color(hex: "fbece2")
    static let brand300 = Color(hex: "e89a73")
    static let brand500 = Color(hex: "d06a3a")
    static let brand700 = Color(hex: "8e3d18")

    // green / accent (闭环 / 完成)
    static let green50  = Color(hex: "e6f2ea")
    static let green500 = Color(hex: "1f7a4c")
    static let green700 = Color(hex: "0f5131")
    static let accent        = Color(hex: "1f7a4c")
    static let accentInk     = Color(hex: "0f5131")
    static let accentSurface = Color(hex: "e6f2ea")

    // warn / danger
    static let warn50    = Color(hex: "fbeedb")
    static let warn500   = Color(hex: "a86a1a")
    static let danger50  = Color(hex: "f8e3e0")
    static let danger500 = Color(hex: "b53333")

    // hairlines
    static let borderWhisper = Color.black.opacity(0.08)
    static let borderDefault = Color.black.opacity(0.10)
    static let borderStrong  = Color.black.opacity(0.15)

    // radii
    static let rXS: CGFloat = 4
    static let rSM: CGFloat = 6
    static let rMD: CGFloat = 8
    static let rLG: CGFloat = 12
    static let rXL: CGFloat = 16
    static let r2XL: CGFloat = 24

    // type — Inter Tight falls back to SF Pro; JetBrains Mono to SF Mono.
    // Centralized so swapping in bundled fonts later is a one-line change.
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
    static func display(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight)
    }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Shadow & border helpers

extension View {
    /// Barely-there elevation used on cards.
    func whisperShadow() -> some View {
        self.shadow(color: .black.opacity(0.04), radius: 9, x: 0, y: 4)
            .shadow(color: .black.opacity(0.02), radius: 2, x: 0, y: 1)
    }
    /// Medium card elevation.
    func cardShadow() -> some View {
        self.shadow(color: .black.opacity(0.05), radius: 14, x: 0, y: 12)
            .shadow(color: .black.opacity(0.04), radius: 5, x: 0, y: 4)
    }
    /// Strong popover / floating bar elevation.
    func popShadow() -> some View {
        self.shadow(color: .black.opacity(0.05), radius: 26, x: 0, y: 20)
            .shadow(color: .black.opacity(0.04), radius: 12, x: 0, y: 8)
    }
    /// Hairline stroke on a rounded rect.
    func hairline(_ color: Color = Theme.borderWhisper, radius: CGFloat, width: CGFloat = 1) -> some View {
        self.overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(color, lineWidth: width))
    }
}
