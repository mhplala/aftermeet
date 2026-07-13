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

    /// 明暗自适应色：随系统外观在 light / dark 之间切换。
    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let darkMatch = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(darkMatch ? dark : light)
        })
    }
}

// MARK: - Design tokens（玻璃拟态版：冷墨 + 闭环绿；框架玻璃、工作区自适应明暗）

enum Theme {
    /// hex 明暗对：`dyn("ffffff","1b1b1e")` = 浅色白 / 深色近黑
    static func dyn(_ l: String, _ d: String) -> Color { Color(light: Color(hex: l), dark: Color(hex: d)) }

    // surfaces — 浅色 Cal.com 纯白工作区；深色近黑分层
    static let white       = dyn("ffffff", "2a2a2e")   // 卡片 / 胶囊实底
    static let warmWhite   = dyn("f7f7f7", "303034")
    static let warmWhite2  = dyn("f0f0f0", "3a3a40")
    static let paper300    = dyn("e4e4e4", "45454b")
    static let pageBg      = dyn("f3f3f3", "1c1c1f")
    static let canvas      = dyn("ffffff", "1b1b1e")   // 工作区背景
    static let sidebarBg   = Color(light: Color.white.opacity(0.34), dark: Color.white.opacity(0.04))
    static let searchBg    = dyn("f7f7f7", "303034")

    // ink / text — 明暗反向
    static let inkPrimary   = dyn("111111", "f3f3f5")
    static let inkSecondary = dyn("4b4b4b", "bcbcc2")
    static let inkTertiary  = dyn("898989", "909097")
    static let inkMuted     = dyn("b5b5b5", "64646a")
    static let ink1000      = dyn("111111", "f3f3f5")
    static let ink900       = dyn("1c1c1c", "e6e6ea")
    static let ink800       = dyn("2a2a2a", "d0d0d6")
    static let ink700       = dyn("444444", "a8a8ae")
    static let onDark       = Color(hex: "ffffff")           // 深色面板上的文字，恒白
    static let onDarkDim    = Color.white.opacity(0.65)

    // blue — 唯一交互色（深色下略提亮）
    static let blue50  = dyn("eff4ff", "17273f")
    static let blue100 = dyn("dbe7ff", "1f3557")
    static let blue500 = dyn("3b82f6", "4f92ff")
    static let blue600 = dyn("2563eb", "3b82f6")
    static let blue700 = dyn("1d4ed8", "76a9ff")            // 用作 blue50 上的文字，深色需变亮

    // brand (warm accent, 深度要点等暖橘点缀)
    static let brand50  = dyn("fbf1e8", "34251b")
    static let brand300 = dyn("efb08a", "c88a5f")
    static let brand500 = dyn("e0905a", "e8a066")
    static let brand700 = dyn("9c5526", "e0a877")          // 文字用，深色变亮

    // green — 只做「完成/成功」语义色
    static let green50  = dyn("eaf7ef", "16311f")
    static let green500 = dyn("16a34a", "2ec46b")
    static let green700 = dyn("15803d", "56d98a")          // 文字用，深色变亮

    // accent — 主操作 = Cal 式黑；深色下随交互色走
    static let accent        = dyn("111111", "f3f3f5")
    static let accentBright  = dyn("2a2a2a", "d0d0d6")
    static let accentInk     = dyn("111111", "f3f3f5")     // Pill 文字
    static let accentSurface = dyn("f0f0f0", "3a3a40")     // Pill 底
    static let accentGlow    = Color(hex: "22c55e")        // 在线小绿点，恒定

    // warn / danger（50 底色深色转暗、文字色深色转亮）
    static let warn50    = dyn("fdf4e0", "332a12")
    static let warn500   = dyn("a16207", "d9a441")
    static let danger50  = dyn("fdecec", "3a1d1d")
    static let danger500 = dyn("dc2626", "ff5b5b")

    // hairlines — 浅色用黑描边，深色用白描边
    static let borderWhisper = Color(light: Color.black.opacity(0.08), dark: Color.white.opacity(0.10))
    static let borderDefault = Color(light: Color.black.opacity(0.13), dark: Color.white.opacity(0.14))
    static let borderStrong  = Color(light: Color.black.opacity(0.20), dark: Color.white.opacity(0.24))
    static let glassBorder   = Color(light: Color.white.opacity(0.78), dark: Color.white.opacity(0.12))

    // 浮动条/胶囊叠在系统材质上的补光层（浅色补白、深色补黑）
    static let glassFill       = Color(light: Color.white.opacity(0.72), dark: Color.black.opacity(0.34))
    static let glassFillStrong = Color(light: Color.white.opacity(0.92), dark: Color.white.opacity(0.10))
    // 悬停高亮：比 active 态更淡（浅色补白、深色补微光）
    static let hoverFill        = Color(light: Color.white.opacity(0.5), dark: Color.white.opacity(0.06))
    // 引用/代码块等次级实底
    static let subtleFill  = dyn("fafafa", "343439")
    // 蒙层（onboarding dim 等）
    static let dimOverlay  = Color(light: Color.black.opacity(0.45), dark: Color.black.opacity(0.58))

    // radii
    static let rXS: CGFloat = 5
    static let rSM: CGFloat = 7
    static let rMD: CGFloat = 10
    static let rLG: CGFloat = 16
    static let rXL: CGFloat = 20
    static let r2XL: CGFloat = 26

    // type — Inter Tight falls back to SF Pro; JetBrains Mono to SF Mono.
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
    static func display(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight)
    }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// 深色浮起面板（侧栏状态卡 / 追问横幅）：浅色近黑，深色抬亮成可见的浮层
    static var inkGlass: LinearGradient {
        LinearGradient(colors: [dyn("111111", "2f2f35"), dyn("1c1c1c", "27272c")],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    /// 成功绿（仅语义场景）
    static var greenGrad: LinearGradient {
        LinearGradient(colors: [dyn("16a34a", "22b562"), dyn("15803d", "1a9c4d")],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    /// 主按钮：浅色 Cal 式黑，深色转蓝（白字通用，保证对比）
    static var inkGrad: LinearGradient {
        LinearGradient(colors: [dyn("1c1c1c", "4f92ff"), dyn("111111", "3b82f6")],
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
