import AppKit
import SwiftUI

/// A second, attached surface keeps the subtitle line completely still during a hover.
final class CaptionReviewHoverController {
    private weak var anchor: NSPanel?
    private var panel: NSPanel?
    private var openWork: DispatchWorkItem?
    private var closeWork: DispatchWorkItem?
    private var captionHovered = false
    private var reviewHovered = false
    private var generation = 0
    private let timelines: MeetingTimelineStore

    init(timelines: MeetingTimelineStore = .shared) { self.timelines = timelines }

    func setCaptionHovered(_ inside: Bool, anchor: NSPanel) {
        self.anchor = anchor
        captionHovered = inside
        if inside {
            closeWork?.cancel()
            if let panel, panel.isVisible {
                generation += 1 // Re-entering during fade-out revives the same surface.
                panel.animator().alphaValue = 1
                return
            }
            openWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.captionHovered, anchor.isVisible else { return }
                self.show(attachedTo: anchor)
            }
            openWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32, execute: work)
        } else {
            openWork?.cancel()
            scheduleClose()
        }
    }

    func setReviewHovered(_ inside: Bool) {
        reviewHovered = inside
        if inside {
            closeWork?.cancel()
            if let panel, panel.isVisible {
                generation += 1
                panel.animator().alphaValue = 1
            }
        } else { scheduleClose() }
    }

    private func scheduleClose() {
        closeWork?.cancel()
        // Allows crossing the gap without flicker; entering either surface cancels this.
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.captionHovered, !self.reviewHovered else { return }
            self.dismiss()
        }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func show(attachedTo anchor: NSPanel) {
        generation += 1
        let p = panel ?? NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.appearance = NSAppearance(named: .darkAqua)
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let hosting = NSHostingView(rootView: CaptionReviewPreview(timelines: timelines,
            onHover: { [weak self] in self?.setReviewHovered($0) }).preferredColorScheme(.dark))
        hosting.sizingOptions = []
        p.contentView = hosting
        panel = p
        reposition()
        p.alphaValue = 0
        anchor.addChildWindow(p, ordered: .above)
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.18
            p.animator().alphaValue = 1
        }
    }

    func reposition() {
        guard let anchor, let panel, let screen = anchor.screen else { return }
        let count = timelines.activeSessionID.flatMap { timelines.documents[$0]?.chunks.count } ?? 0
        let height: CGFloat = count == 0 ? 180 : (count == 1 ? 280 : 420)
        panel.setFrame(Self.frame(anchor: anchor.frame, screen: screen.visibleFrame, preferredHeight: height), display: true)
    }

    static func frame(anchor: NSRect, screen: NSRect, preferredHeight: CGFloat = 420) -> NSRect {
        let gap: CGFloat = 8
        let margin: CGFloat = 12
        let width = min(max(anchor.width, 380), 500, screen.width - margin * 2)
        let above = screen.maxY - anchor.maxY - gap - margin
        let below = anchor.minY - screen.minY - gap - margin
        let useAbove = above >= preferredHeight || above >= below
        let available = useAbove ? above : below
        let height = min(preferredHeight, max(180, available), screen.height - margin * 2)
        let x = min(max(anchor.minX, screen.minX + margin), screen.maxX - margin - width)
        let preferredY = useAbove ? anchor.maxY + gap : anchor.minY - gap - height
        let y = min(max(preferredY, screen.minY + margin), screen.maxY - margin - height)
        return NSRect(x: x, y: y, width: width, height: height)
    }

    func dismiss(immediately: Bool = false) {
        openWork?.cancel(); closeWork?.cancel()
        captionHovered = false; reviewHovered = false
        generation += 1
        let current = generation
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = immediately || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.16
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self, self.generation == current else { return }
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
    }
}

struct CaptionReviewPreview: View {
    @ObservedObject var timelines: MeetingTimelineStore
    let onHover: (Bool) -> Void
    @State private var sessionID: String?
    private var document: MeetingTimelineDocument? { sessionID.flatMap { timelines.documents[$0] } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath").foregroundStyle(.white.opacity(0.55))
                Text("会议回顾").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("共 \(document?.chunks.count ?? 0) 段").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
            }.padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 14)
            if let doc = document {
                ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let summary = doc.latestSummary {
                            Text(summary.currentProgress)
                                .font(.system(size: 13, weight: .medium)).lineSpacing(4)
                                .foregroundStyle(.white.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(doc.chunks) { chunk in
                            HStack(alignment: .top, spacing: 12) {
                                Circle().fill(.white.opacity(0.3)).frame(width: 5, height: 5).padding(.top, 5)
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(chunk.summary?.title ?? (chunk.state == .failed ? "摘要暂未生成" : "正在整理…"))
                                            .font(.system(size: 12, weight: .semibold))
                                        Spacer(minLength: 8)
                                        Text("\(chunk.approximateTime ? "约 " : "")\(MeetingTimelineStore.time(chunk.startMS))–\(MeetingTimelineStore.time(chunk.endMS))")
                                            .font(.system(size: 9, design: .monospaced)).foregroundStyle(.white.opacity(0.4))
                                    }
                                    if let summary = chunk.summary {
                                        Text(summary.points.joined(separator: "\n"))
                                            .font(.system(size: 11.5)).lineSpacing(4)
                                            .foregroundStyle(.white.opacity(0.65)).fixedSize(horizontal: false, vertical: true)
                                    } else {
                                        Text("原文已保存，可在完整时间线查看")
                                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                                    }
                                }
                            }.id(chunk.id)
                        }
                        if doc.chunks.isEmpty {
                            Text(doc.state == .recording ? "正在积累这场会议的内容。第一段摘要会自动出现在这里。" : "这场会议还没有分段摘要，可打开时间线查看原文。")
                                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).lineSpacing(4)
                        }
                        Color.clear.frame(height: 1).id("hover-latest")
                    }.padding(.horizontal, 20).padding(.bottom, 16)
                }
                .onAppear {
                    DispatchQueue.main.async {
                        proxy.scrollTo("hover-latest", anchor: .bottom)
                    }
                }
                .onChange(of: doc.chunks.count) { old, _ in
                    // Only the first result follows automatically. Reading history stays put.
                    if old == 0 { proxy.scrollTo("hover-latest", anchor: .bottom) }
                }
                }
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.arrow.down")
                    Text("上下滚动回看全部内容")
                    Spacer()
                    Text("移开收起").foregroundStyle(.white.opacity(0.35))
                }.font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.55))
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.08)).frame(height: 1) }
            } else {
                Text("开始一场新录制后，分段回顾会自动出现在这里。")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).lineSpacing(5)
                    .padding(.horizontal, 20)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.12)))
        .background(CaptionHoverRegion(onHover: onHover))
        .onAppear {
            sessionID = timelines.activeSessionID
        }
    }
}

/// Nonactivating panels must track the pointer even while a different app owns keyboard focus.
struct CaptionHoverRegion: NSViewRepresentable {
    let onHover: (Bool) -> Void
    func makeNSView(context: Context) -> TrackingView { TrackingView(onHover: onHover) }
    func updateNSView(_ view: TrackingView, context: Context) { view.onHover = onHover }

    final class TrackingView: NSView {
        var onHover: (Bool) -> Void
        private var area: NSTrackingArea?
        private var inside = false
        init(onHover: @escaping (Bool) -> Void) { self.onHover = onHover; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let area { removeTrackingArea(area) }
            let next = NSTrackingArea(rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
            addTrackingArea(next)
            area = next
            if let window {
                let point = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
                setInside(visibleRect.contains(point))
            }
        }
        private func setInside(_ value: Bool) {
            guard value != inside else { return }
            inside = value
            DispatchQueue.main.async { [weak self] in
                guard let self, self.inside == value else { return }
                self.onHover(value)
            }
        }
        override func mouseEntered(with event: NSEvent) { setInside(true) }
        override func mouseExited(with event: NSEvent) { setInside(false) }
    }
}
