import SwiftUI
import AppKit

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

// MARK: - Design tokens（玻璃拟态版：冷墨 + 闭环绿；框架玻璃、工作区纯白）

enum Theme {
    // surfaces — 工作区纯白，浅灰全部偏冷
    static let white       = Color(hex: "ffffff")
    static let warmWhite   = Color(hex: "f6f7fc")
    static let warmWhite2  = Color(hex: "eef0f8")
    static let paper300    = Color(hex: "e2e5f0")
    static let pageBg      = Color(hex: "f2f3fb")
    static let canvas      = Color(hex: "ffffff")
    static let sidebarBg   = Color.white.opacity(0.34)
    static let searchBg    = Color(hex: "f6f7fc")

    // ink / text — 冷夜蓝墨
    static let inkPrimary   = Color(hex: "1b1d2a")
    static let inkSecondary = Color(hex: "575c70")
    static let inkTertiary  = Color(hex: "8a8fa4")
    static let inkMuted     = Color(hex: "abafc2")
    static let ink1000      = Color(hex: "1b1d2a")
    static let ink900       = Color(hex: "23263a")
    static let ink800       = Color(hex: "31354c")
    static let ink700       = Color(hex: "4a4f68")
    static let onDark       = Color(hex: "fbfcff")
    static let onDarkDim    = Color(hex: "ebefff").opacity(0.72)

    // blue (info)
    static let blue50  = Color(hex: "eef4ff")
    static let blue100 = Color(hex: "d9e7ff")
    static let blue500 = Color(hex: "3f7ef7")
    static let blue600 = Color(hex: "2f63cc")
    static let blue700 = Color(hex: "1d4fa8")

    // brand (warm accent, 深度要点等暖橘点缀)
    static let brand50  = Color(hex: "fbf1e8")
    static let brand300 = Color(hex: "efb08a")
    static let brand500 = Color(hex: "e0905a")
    static let brand700 = Color(hex: "9c5526")

    // green / accent (闭环 / 完成)
    static let green50  = Color(hex: "eaf7f0")
    static let green500 = Color(hex: "0f9d63")
    static let green700 = Color(hex: "0a6b45")
    static let accent        = Color(hex: "0f9d63")
    static let accentBright  = Color(hex: "12b573")
    static let accentInk     = Color(hex: "0a6b45")
    static let accentSurface = Color(hex: "e2f6ec")
    static let accentGlow    = Color(hex: "35dc96")

    // warn / danger
    static let warn50    = Color(hex: "fdf3e1")
    static let warn500   = Color(hex: "b3761c")
    static let danger50  = Color(hex: "fdecee")
    static let danger500 = Color(hex: "e0485c")

    // hairlines — 冷灰蓝
    static let borderWhisper = Color(hex: "737daa").opacity(0.16)
    static let borderDefault = Color(hex: "737daa").opacity(0.24)
    static let borderStrong  = Color(hex: "737daa").opacity(0.34)
    static let glassBorder   = Color.white.opacity(0.78)

    // radii
    static let rXS: CGFloat = 5
    static let rSM: CGFloat = 7
    static let rMD: CGFloat = 10
    static let rLG: CGFloat = 16
    static let rXL: CGFloat = 20
    static let r2XL: CGFloat = 26

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

    /// 深墨玻璃（侧栏状态卡 / 追问横幅）
    static var inkGlass: LinearGradient {
        LinearGradient(colors: [Color(hex: "1e2238").opacity(0.94), Color(hex: "2c3256").opacity(0.90)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    /// 闭环绿渐变（主按钮）
    static var greenGrad: LinearGradient {
        LinearGradient(colors: [Color(hex: "12b573"), Color(hex: "0a8a58")],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    /// 深墨渐变（次主按钮）
    static var inkGrad: LinearGradient {
        LinearGradient(colors: [Color(hex: "2a2d40"), Color(hex: "1b1d2a")],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - 系统原生玻璃（Tahoe）：侧栏 / 标题栏直接用 NSVisualEffectView，不叠自定义颜色

struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blending
    }
}

// MARK: - Shadow & border helpers

extension View {
    /// Barely-there elevation used on cards.
    func whisperShadow() -> some View {
        self.shadow(color: Color(hex: "5862a8").opacity(0.08), radius: 11, x: 0, y: 6)
            .shadow(color: Color(hex: "5862a8").opacity(0.05), radius: 2, x: 0, y: 1)
    }
    /// Medium card elevation.
    func cardShadow() -> some View {
        self.shadow(color: Color(hex: "5862a8").opacity(0.10), radius: 16, x: 0, y: 12)
            .shadow(color: Color(hex: "5862a8").opacity(0.06), radius: 5, x: 0, y: 4)
    }
    /// Strong popover / floating bar elevation.
    func popShadow() -> some View {
        self.shadow(color: Color(hex: "5862a8").opacity(0.16), radius: 26, x: 0, y: 18)
            .shadow(color: Color(hex: "5862a8").opacity(0.08), radius: 10, x: 0, y: 6)
    }
    /// 彩色发光（主按钮 / 录制点）
    func glow(_ color: Color, radius: CGFloat = 14, opacity: Double = 0.35) -> some View {
        self.shadow(color: color.opacity(opacity), radius: radius, x: 0, y: 5)
    }
    /// Hairline stroke on a rounded rect.
    func hairline(_ color: Color = Theme.borderWhisper, radius: CGFloat, width: CGFloat = 1) -> some View {
        self.overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(color, lineWidth: width))
    }
}
