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
    // surfaces — Cal.com 风：纯白工作区 + 中性灰
    static let white       = Color(hex: "ffffff")
    static let warmWhite   = Color(hex: "f7f7f7")
    static let warmWhite2  = Color(hex: "f0f0f0")
    static let paper300    = Color(hex: "e4e4e4")
    static let pageBg      = Color(hex: "f3f3f3")
    static let canvas      = Color(hex: "ffffff")
    static let sidebarBg   = Color.white.opacity(0.34)
    static let searchBg    = Color(hex: "f7f7f7")

    // ink / text — 中性黑灰
    static let inkPrimary   = Color(hex: "111111")
    static let inkSecondary = Color(hex: "4b4b4b")
    static let inkTertiary  = Color(hex: "898989")
    static let inkMuted     = Color(hex: "b5b5b5")
    static let ink1000      = Color(hex: "111111")
    static let ink900       = Color(hex: "1c1c1c")
    static let ink800       = Color(hex: "2a2a2a")
    static let ink700       = Color(hex: "444444")
    static let onDark       = Color(hex: "ffffff")
    static let onDarkDim    = Color.white.opacity(0.65)

    // blue — 唯一交互色
    static let blue50  = Color(hex: "eff4ff")
    static let blue100 = Color(hex: "dbe7ff")
    static let blue500 = Color(hex: "3b82f6")
    static let blue600 = Color(hex: "2563eb")
    static let blue700 = Color(hex: "1d4ed8")

    // brand (warm accent, 深度要点等暖橘点缀)
    static let brand50  = Color(hex: "fbf1e8")
    static let brand300 = Color(hex: "efb08a")
    static let brand500 = Color(hex: "e0905a")
    static let brand700 = Color(hex: "9c5526")

    // green — 只做「完成/成功」语义色，不再是品牌主色
    static let green50  = Color(hex: "eaf7ef")
    static let green500 = Color(hex: "16a34a")
    static let green700 = Color(hex: "15803d")
    static let accent        = Color(hex: "111111")   // 主操作 = Cal 式黑
    static let accentBright  = Color(hex: "2a2a2a")
    static let accentInk     = Color(hex: "111111")
    static let accentSurface = Color(hex: "f0f0f0")
    static let accentGlow    = Color(hex: "22c55e")   // 在线小绿点

    // warn / danger
    static let warn50    = Color(hex: "fdf4e0")
    static let warn500   = Color(hex: "a16207")
    static let danger50  = Color(hex: "fdecec")
    static let danger500 = Color(hex: "dc2626")

    // hairlines — 中性
    static let borderWhisper = Color.black.opacity(0.08)
    static let borderDefault = Color.black.opacity(0.13)
    static let borderStrong  = Color.black.opacity(0.20)
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

    /// 近黑面板（侧栏状态卡 / 追问横幅）
    static var inkGlass: LinearGradient {
        LinearGradient(colors: [Color(hex: "111111").opacity(0.94), Color(hex: "1c1c1c").opacity(0.92)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    /// 成功绿（仅语义场景）
    static var greenGrad: LinearGradient {
        LinearGradient(colors: [Color(hex: "16a34a"), Color(hex: "15803d")],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    /// 主按钮黑（Cal 式）
    static var inkGrad: LinearGradient {
        LinearGradient(colors: [Color(hex: "1c1c1c"), Color(hex: "111111")],
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
        self.shadow(color: Color.black.opacity(0.08), radius: 11, x: 0, y: 6)
            .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    /// Medium card elevation.
    func cardShadow() -> some View {
        self.shadow(color: Color.black.opacity(0.10), radius: 16, x: 0, y: 12)
            .shadow(color: Color.black.opacity(0.06), radius: 5, x: 0, y: 4)
    }
    /// Strong popover / floating bar elevation.
    func popShadow() -> some View {
        self.shadow(color: Color.black.opacity(0.16), radius: 26, x: 0, y: 18)
            .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 6)
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
