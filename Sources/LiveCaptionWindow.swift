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
    private var expandedHeight: CGFloat = 200
    private static let collapsedHeight: CGFloat = 56

    func toggleCollapsed() {
        guard let panel else { return }
        var f = panel.frame
        if isCollapsed {
            f.origin.y -= (expandedHeight - Self.collapsedHeight)   // 顶边不动，往下长
            f.size.height = expandedHeight
            isCollapsed = false
        } else {
            expandedHeight = f.size.height
            f.origin.y += (f.size.height - Self.collapsedHeight)
            f.size.height = Self.collapsedHeight
            isCollapsed = true
        }
        panel.setFrame(f, display: true, animate: true)
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
        p.setFrameAutosaveName("AftermeetLiveCaption")
        if p.frame.origin == .zero { p.center() }
        p.orderFrontRegardless()

        panel = p
        isOpen = true
    }

    func close() {
        panel?.orderOut(nil)
        isOpen = false
    }

    func windowWillClose(_ notification: Notification) { isOpen = false }
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
        ZStack(alignment: .topTrailing) {
            if controller.isCollapsed { collapsedLine } else { transcript }
            controls
                .padding(10)
                .opacity(hovering ? 1 : 0)   // 平时隐形，鼠标移入才浮现
                .animation(.easeOut(duration: 0.15), value: hovering)
        }
        .frame(minWidth: 320, minHeight: 120)
        .background(GlassBackground())
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .onHover { hovering = $0 }
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
            iconButton(controller.isCollapsed ? "chevron.down" : "chevron.up") {
                controller.toggleCollapsed()
            }
            iconButton("xmark") { onClose() }
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(Color.black.opacity(0.28))
        .clipShape(Capsule())
    }

    private func iconButton(_ name: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var elapsed: String {
        String(format: "%02d:%02d", capture.elapsed / 60, capture.elapsed % 60)
    }

    // MARK: 收起态——只显示最新一句，够跟上进度又不挡屏幕

    private var collapsedLine: some View {
        let latest = !capture.pendingLine.isEmpty ? capture.pendingLine
                   : (capture.liveLines.last ?? (capture.isCapturing ? "正在聆听…" : "未在录制"))
        return HStack(spacing: 8) {
            if capture.isCapturing {
                Circle().fill(capture.isPaused ? Color.orange : Color.red).frame(width: 6, height: 6)
            }
            Text(latest)
                .font(.system(size: min(fontSize, 15)))
                .foregroundColor(.white.opacity(capture.pendingLine.isEmpty ? 0.9 : 0.6))
                .lineLimit(1).truncationMode(.head)     // 保留句尾——最新说的才是要看的
            Spacer(minLength: 60)                        // 给右上角悬浮控件让位
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
            .onChange(of: lines.count) { _, _ in
                withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: pending.count) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }
}
