import SwiftUI
import AppKit

/// 悬浮字幕窗：像字幕一样跟着会议实时滚动。无边框玻璃面板，常驻最前（含全屏会议之上）、
/// 不抢焦点。刻意不留标题栏和状态栏——那两行在小窗里占掉的高度比正文还多；
/// 状态与控件改为悬停时才浮现的角标浮层，正文始终铺满整块玻璃。
final class LiveCaptionWindowController: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = LiveCaptionWindowController()

    @Published private(set) var isOpen = false
    /// 收起态：只留一行"最新一句"的窄条，开会时挂在角落不挡视线；展开恢复原高度。
    @Published private(set) var isCollapsed = false
    private var panel: NSPanel?
    private let hoverReview = CaptionReviewHoverController()
    private var expandedHeight: CGFloat = 200
    private static let collapsedHeight: CGFloat = 56
    private static let minimumWidth: CGFloat = 320
    private static let minimumExpandedHeight: CGFloat = 120

    func toggleCollapsed() {
        guard let panel else { return }
        let oldFrame = panel.frame
        if !isCollapsed {
            expandedHeight = max(Self.minimumExpandedHeight, oldFrame.height)
        }
        isCollapsed.toggle()
        updateSizeLimits(panel)

        let height = isCollapsed ? Self.collapsedHeight : expandedHeight
        var f = NSRect(x: oldFrame.minX, y: oldFrame.maxY - height,
                       width: oldFrame.width, height: height)
        if let visible = panel.screen?.visibleFrame {
            f.size.width = min(f.width, visible.width)
            f.size.height = min(f.height, visible.height)
            f.origin.x = min(max(f.minX, visible.minX), visible.maxX - f.width)
            f.origin.y = min(max(f.minY, visible.minY), visible.maxY - f.height)
        }
        panel.setFrame(f, display: true, animate: true)
    }

    private func updateSizeLimits(_ panel: NSPanel) {
        panel.contentMinSize = NSSize(width: Self.minimumWidth,
                                      height: isCollapsed ? Self.collapsedHeight : Self.minimumExpandedHeight)
        panel.contentMaxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                      height: isCollapsed ? Self.collapsedHeight : CGFloat.greatestFiniteMagnitude)
    }

    func toggle(capture: CaptureService) {
        if isOpen { close() } else { show(capture: capture) }
    }

    func show(capture: CaptureService) {
        if let panel {
            panel.orderFrontRegardless()
            isOpen = true
            return
        }
        let hosting = NSHostingView(rootView: LiveCaptionView(
            capture: capture,
            controller: self,
            onClose: { [weak self] in self?.close() }))
        hosting.wantsLayer = true
        // 窗口尺寸由两种模式明确管理，避免 SwiftUI 的最小内容高度反过来撑大窄条。
        hosting.sizingOptions = []

        // .borderless：没有标题栏，整块都是内容；.resizable 让边缘仍可拖拽改大小
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 620, height: 200),
                        styleMask: [.nonactivatingPanel, .borderless, .resizable],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear                 // 圆角外的部分要透出去，不能留白底
        // 固定深色：.hudWindow 材质会跟随系统外观，浅色模式下会渲染成浅底面板，
        // 而字幕文字是白色 —— 那样直接糊成一片看不见。字幕要压在任意内容之上，
        // 固定深色底 + 白字是最稳的组合，也不受用户深浅色设置影响。
        p.appearance = NSAppearance(named: .darkAqua)
        p.hasShadow = true
        p.isMovableByWindowBackground = true       // 没有标题栏了，整窗都能拖
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.contentView = hosting
        p.delegate = self
        updateSizeLimits(p)
        p.setFrameAutosaveName("AftermeetLiveCaption")
        // 上次退出可能保存的是窄条尺寸；首次打开始终与展开态一致。
        if p.frame.height < Self.minimumExpandedHeight {
            var frame = p.frame
            frame.origin.y = frame.maxY - expandedHeight
            frame.size.height = expandedHeight
            p.setFrame(frame, display: false)
        }
        if p.frame.origin == .zero { p.center() }
        p.orderFrontRegardless()

        panel = p
        isOpen = true
    }

    func close() {
        hoverReview.dismiss(immediately: true)
        panel?.orderOut(nil)
        isOpen = false
    }

    func setHovered(_ inside: Bool) {
        guard let panel else { return }
        hoverReview.setCaptionHovered(inside, anchor: panel)
    }

    func windowDidMove(_ notification: Notification) { hoverReview.reposition() }
    func windowDidResize(_ notification: Notification) { hoverReview.reposition() }
    func windowWillClose(_ notification: Notification) {
        hoverReview.dismiss(immediately: true)
        isOpen = false
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        // NSHostingView 可能在布局后重算窗口的 min/maxSize；原生拖拽也须遵守模式尺寸。
        NSSize(width: max(Self.minimumWidth, frameSize.width),
               height: isCollapsed ? Self.collapsedHeight : max(Self.minimumExpandedHeight, frameSize.height))
    }
}

/// 毛玻璃底：用系统材质，自动适配深浅色与桌面背景
private struct GlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

private struct LiveCaptionView: View {
    @ObservedObject var capture: CaptureService
    @ObservedObject var controller: LiveCaptionWindowController
    let onClose: () -> Void
    @AppStorage("liveCaptionFontSize") private var fontSize: Double = 18
    @State private var hovering = false

    private let corner: CGFloat = 14

    var body: some View {
        Group {
            if controller.isCollapsed {
                collapsedLine
                    .frame(height: 56)
            } else {
                ZStack(alignment: .topTrailing) {
                    transcript
                    controls
                        .padding(10)
                        .opacity(hovering ? 1 : 0)
                        .allowsHitTesting(hovering)
                        .animation(.easeOut(duration: 0.15), value: hovering)
                }
                .frame(minHeight: 120)
            }
        }
        .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
        .background(GlassBackground())
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .background(CaptionHoverRegion {
            hovering = $0
            controller.setHovered($0)
        })
    }

    // MARK: 悬浮控件（状态 + 字号 + 关闭）

    private var controls: some View {
        HStack(spacing: 8) {
            if capture.isCapturing {
                Circle().fill(capture.isPaused ? Color.orange : Color.red).frame(width: 6, height: 6)
                Text(elapsed)
                    .font(.system(size: 11, weight: .medium, design: .rounded)).monospacedDigit()
                    .foregroundColor(.white.opacity(0.85))
                Text(capture.isPaused ? "已暂停"
                     : (capture.cloudReconnecting ? "重连中" : (capture.usingCloud ? "云端" : "本地")))
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.75))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.white.opacity(0.14))
                    .clipShape(Capsule())
            }
            if !controller.isCollapsed {
                iconButton("textformat.size.smaller") { fontSize = max(12, fontSize - 2) }
                iconButton("textformat.size.larger") { fontSize = min(36, fontSize + 2) }
            }
            iconButton("chevron.up", label: "收起字幕窗") {
                controller.toggleCollapsed()
            }
            iconButton("xmark", label: "关闭字幕窗") { onClose() }
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(Color.black.opacity(0.28))
        .clipShape(Capsule())
    }

    private func iconButton(_ name: String, label: String? = nil,
                            _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label ?? (name == "textformat.size.smaller" ? "缩小字幕字号" : "放大字幕字号"))
        .help(label ?? (name == "textformat.size.smaller" ? "缩小字幕字号" : "放大字幕字号"))
    }

    private var elapsed: String {
        String(format: "%02d:%02d", capture.elapsed / 60, capture.elapsed % 60)
    }

    // MARK: 收起态——只显示最新一句，够跟上进度又不挡屏幕

    private var collapsedLine: some View {
        let latest = !capture.pendingLine.isEmpty ? capture.pendingLine
                   : (capture.liveLines.last ?? (capture.isPaused ? "录制已暂停"
                        : (capture.isCapturing ? "正在聆听…" : "未在录制")))
        return HStack(spacing: 12) {
            if capture.isCapturing {
                Circle().fill(capture.isPaused ? Color.orange : Color.red).frame(width: 6, height: 6)
            }
            Text(latest)
                .font(.system(size: min(fontSize, 15)))
                .foregroundColor(.white.opacity(capture.pendingLine.isEmpty ? 0.95 : 0.8))
                .lineLimit(1).truncationMode(.head)     // 保留句尾——最新说的才是要看的
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            HStack(spacing: 4) {
                compactButton("chevron.down", label: "展开字幕窗") { controller.toggleCollapsed() }
                compactButton("xmark", label: "关闭字幕窗") { onClose() }
            }
            .opacity(hovering ? 1 : 0.65)
            .animation(.easeOut(duration: 0.15), value: hovering)
        }
        .padding(.leading, 16).padding(.trailing, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func compactButton(_ name: String, label: String,
                               _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(hovering ? 0.1 : 0.04))
                .clipShape(Circle())
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    // MARK: 正文

    private var transcript: some View {
        let lines = capture.liveLines
        let pending = capture.pendingLine
        let isEmpty = lines.isEmpty && pending.isEmpty
        return ScrollViewReader { proxy in
            ScrollView {
                if isEmpty {
                    HStack(spacing: 7) {
                        if capture.isCapturing { PulsingDot(color: .white.opacity(0.5)) }
                        Text(capture.isCapturing ? "正在聆听…" : "开始录制后，这里实时显示字幕")
                            .font(.system(size: fontSize - 4))
                            .foregroundColor(.white.opacity(0.55))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18).padding(.top, 16)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: fontSize))
                                .foregroundColor(.white.opacity(0.95))
                                .lineSpacing(5)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !pending.isEmpty {
                            Text(pending)                       // 还会被改写，压暗区分
                                .font(.system(size: fontSize))
                                .foregroundColor(.white.opacity(0.5))
                                .lineSpacing(5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    // 顶部留白比右侧控件略小：控件是浮层，不该逼正文让出一整行
                    .padding(.horizontal, 18)
                    .padding(.top, 14).padding(.bottom, 16)
                }
                Color.clear.frame(height: 1).id("bottom")
            }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: lines) { _, _ in
                withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: pending) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }
}
