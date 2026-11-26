import SwiftUI
import AppKit

struct MeetingTimelineView: View {
    @ObservedObject var timelines: MeetingTimelineStore = .shared
    let sessionID: String
    var compact = false
    @State private var browsing = MeetingTimelineBrowsingState()
    @State private var initialized = false

    private var document: MeetingTimelineDocument? { timelines.documents[sessionID] }
    private var ids: [String] { document?.chunks.map(\.id) ?? [] }

    var body: some View {
        Group {
            if let doc = document {
                ScrollViewReader { proxy in
                    VStack(spacing: 0) {
                        header(doc)
                        HStack(spacing: 12) {
                            Text("会议脉络 · \(doc.chunks.count) 段")
                                .font(Theme.ui(12, .semibold)).foregroundColor(Theme.inkSecondary)
                            Spacer(minLength: 4)
                            if browsing.showsAll {
                                Button("跳到开场") {
                                    if let first = ids.first { proxy.scrollTo(first, anchor: .top) }
                                }
                                Button(browsing.expandedIDs.count == ids.count && !ids.isEmpty ? "收起历史" : "全部展开") {
                                    browsing.visibleIDs = ids
                                    browsing.expandedIDs = browsing.expandedIDs.count == ids.count
                                        ? Set(ids.suffix(3)) : Set(ids)
                                }
                            }
                        }
                        .font(Theme.ui(11)).buttonStyle(.plain).foregroundColor(Theme.blue700)
                        .padding(.horizontal, 20).padding(.vertical, 12)
                        Divider()
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                if doc.chunks.isEmpty && doc.pendingSegments.isEmpty {
                                    emptyState(doc)
                                }
                                ForEach(doc.chunks.filter { browsing.visibleIDs.contains($0.id) }) { chunk in
                                    MeetingTimelineCard(chunk: chunk, source: doc.source(for: chunk),
                                                        expanded: browsing.expandedIDs.contains(chunk.id),
                                                        toggle: { browsing.toggle(chunk.id) },
                                                        retry: { timelines.retry(sessionID: sessionID, chunkID: chunk.id) })
                                        .id(chunk.id)
                                }
                                if !browsing.showsAll && doc.chunks.count > 3 {
                                    Button {
                                        browsing.showAll(ids)
                                    } label: {
                                        Label("查看全部 \(doc.chunks.count) 段", systemImage: "clock.arrow.circlepath")
                                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                                    }
                                    .buttonStyle(.plain).font(Theme.ui(12, .semibold)).foregroundColor(Theme.blue700)
                                }
                                if !doc.pendingSegments.isEmpty && browsing.unseenCount(ids) == 0 {
                                    pendingCard(doc)
                                }
                                Color.clear.frame(height: 1).id("timeline-latest")
                            }
                            .padding(20)
                        }
                        .onAppear {
                            if !initialized {
                                browsing.open(ids, all: !compact)
                                initialized = true
                                // After layout, position once. Incoming chunks never trigger scrolling.
                                DispatchQueue.main.async { proxy.scrollTo("timeline-latest", anchor: .bottom) }
                            }
                        }
                        .onChange(of: ids) { _, new in
                            if browsing.visibleIDs.isEmpty {
                                browsing.open(new, all: browsing.showsAll)
                            }
                        }
                        if browsing.unseenCount(ids) > 0 {
                            Button {
                                browsing.showLatest(ids)
                                DispatchQueue.main.async { proxy.scrollTo("timeline-latest", anchor: .bottom) }
                            } label: {
                                HStack {
                                    Text("新增 \(browsing.unseenCount(ids)) 段")
                                    Spacer()
                                    Label("回到最新", systemImage: "arrow.down")
                                }
                                .font(Theme.ui(12, .semibold))
                                .padding(.horizontal, 20).padding(.vertical, 12)
                                .background(Theme.blue50).foregroundColor(Theme.blue700)
                            }.buttonStyle(.plain)
                        } else if browsing.showsAll && !ids.isEmpty {
                            HStack {
                                Spacer()
                                Button("回到最新 ↓") {
                                    browsing.showLatest(ids)
                                    DispatchQueue.main.async { proxy.scrollTo("timeline-latest", anchor: .bottom) }
                                }.buttonStyle(.plain).font(Theme.ui(11)).foregroundColor(Theme.blue700)
                            }.padding(.horizontal, 20).padding(.vertical, 8)
                        }
                        if let error = timelines.storageError {
                            Text(error).font(Theme.ui(11)).foregroundColor(Theme.danger500).padding(12)
                        }
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "clock").font(.system(size: 28))
                    Text("这场会议还没有会中回顾")
                    Text("新录制会自动保留分段摘要和对应原文。")
                        .font(Theme.ui(12)).foregroundColor(Theme.inkMuted)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.canvas)
    }

    private func header(_ doc: MeetingTimelineDocument) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(doc.displayTitle).font(Theme.display(compact ? 21 : 26, .semibold)).lineLimit(2)
                    Text(doc.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(Theme.ui(11)).foregroundColor(Theme.inkMuted)
                }
                Spacer(minLength: 12)
                Text(doc.state == .recording ? "进行中" : (doc.state == .finished ? "已结束" : "录制已中断"))
                    .font(Theme.ui(10.5, .medium))
                    .foregroundColor(doc.state == .recording ? Theme.danger500 : Theme.inkSecondary)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(doc.state == .recording ? Theme.danger50 : Theme.warmWhite2).clipShape(Capsule())
            }
            if let summary = doc.latestSummary,
               let latest = doc.chunks.last(where: { $0.state == .ready }) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("当前进展").font(Theme.ui(11, .semibold))
                        Spacer()
                        Text("整理至 \(MeetingTimelineStore.time(latest.endMS))")
                            .font(Theme.mono(10)).foregroundColor(Theme.inkMuted)
                    }
                    Text(summary.currentProgress).font(Theme.ui(12.5)).foregroundColor(Theme.inkSecondary)
                        .lineSpacing(3).lineLimit(3).frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)
                }
                .padding(12).background(Theme.warmWhite2)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }.padding(20)
    }

    private func emptyState(_ doc: MeetingTimelineDocument) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(doc.state == .recording ? "正在聆听" : "暂无可总结的文字", systemImage: "waveform")
                .font(Theme.ui(14, .semibold))
            Text("每积累约 3–5 分钟的有效内容，会自动整理一段摘要；字幕和录音照常进行。")
                .font(Theme.ui(12)).foregroundColor(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
        }.padding(.vertical, 30).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pendingCard(_ doc: MeetingTimelineDocument) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(doc.state == .recording ? "正在积累下一段" : "还有一段原文待整理", systemImage: "waveform")
                    .font(Theme.ui(12, .medium))
                Spacer()
                Button("总结当前段") { timelines.sealPending(sessionID: sessionID) }
                    .font(Theme.ui(11)).buttonStyle(.plain).foregroundColor(Theme.blue700)
            }
            Text("\(MeetingTimelineStore.time(doc.pendingSegments.first?.startMS ?? 0)) — \(MeetingTimelineStore.time(doc.elapsedSec * 1000)) · 原文已保存")
                .font(Theme.mono(10.5)).foregroundColor(Theme.inkMuted)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.warmWhite2).clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct MeetingTimelineCard: View {
    let chunk: MeetingTimelineChunk
    let source: [CapturedSegment]
    let expanded: Bool
    let toggle: () -> Void
    let retry: () -> Void
    @State private var sourceExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(chunk.state == .ready ? Theme.blue500 : Theme.inkMuted)
                        .frame(width: 7, height: 7).padding(.top, 5)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(chunk.approximateTime ? "约 " : "")\(MeetingTimelineStore.time(chunk.startMS))–\(MeetingTimelineStore.time(chunk.endMS))")
                            .font(Theme.mono(10.5)).foregroundColor(Theme.inkMuted)
                        Text(chunk.summary?.title ?? (chunk.state == .failed ? "摘要暂未生成" : "正在整理这一段…"))
                            .font(Theme.ui(14, .semibold)).foregroundColor(Theme.inkPrimary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold)).foregroundColor(Theme.inkMuted)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    if let summary = chunk.summary {
                        ForEach(Array(summary.points.enumerated()), id: \.offset) { _, point in
                            HStack(alignment: .top, spacing: 7) {
                                Text("·").foregroundColor(Theme.inkMuted)
                                Text(point).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                            }.font(Theme.ui(12.5)).foregroundColor(Theme.inkSecondary)
                        }
                    } else if chunk.state == .failed {
                        Text(chunk.error ?? "整理失败，原文已保留")
                            .font(Theme.ui(11.5)).foregroundColor(Theme.warn500)
                        Button("重新总结", action: retry).buttonStyle(.plain)
                            .font(Theme.ui(11.5, .medium)).foregroundColor(Theme.blue700)
                    } else {
                        HStack(spacing: 7) {
                            ProgressView().controlSize(.mini)
                            Text(chunk.state == .queued ? "等待整理，原文可随时查看" : "正在生成摘要…")
                                .font(Theme.ui(11.5)).foregroundColor(Theme.inkMuted)
                        }
                    }
                    Button {
                        sourceExpanded.toggle()
                    } label: {
                        Label(sourceExpanded ? "收起原文" : "查看这段原文", systemImage: "text.alignleft")
                    }.buttonStyle(.plain).font(Theme.ui(11)).foregroundColor(Theme.blue700)
                    if sourceExpanded {
                        VStack(alignment: .leading, spacing: 9) {
                            ForEach(source) { segment in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(MeetingTimelineStore.time(segment.startMS ?? chunk.startMS))
                                        .font(Theme.mono(10)).foregroundColor(Theme.inkMuted)
                                    Text(segment.text).font(Theme.ui(12)).textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.warmWhite2).clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }.padding(.leading, 17).padding(.top, 12)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.white).clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.borderWhisper, lineWidth: 1))
    }
}

struct MeetingTimelineScreen: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject private var timelines = MeetingTimelineStore.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { store.goBack() } label: { Label("返回", systemImage: "chevron.left") }
                .buttonStyle(.plain).font(Theme.ui(12)).foregroundColor(Theme.inkSecondary)
                .padding(.horizontal, 24).padding(.top, 16)
            if let id = store.timelineSessionID,
               timelines.documents[id]?.state == .recording {
                MeetingTimelineView(sessionID: id).id(id)
            }
        }
        .onChange(of: timelines.activeSessionID) { _, activeID in
            if activeID != store.timelineSessionID { store.goBack() }
        }
    }
}

final class MeetingTimelineWindowController {
    static let shared = MeetingTimelineWindowController()
    private var panel: NSPanel?
    private var sessionID: String?

    func show(sessionID: String) {
        if let panel, self.sessionID == sessionID {
            panel.orderFrontRegardless()
            return
        }
        let panel = panel ?? NSPanel(contentRect: NSRect(x: 0, y: 0, width: 540, height: 640),
                                     styleMask: [.titled, .closable, .resizable, .utilityWindow],
                                     backing: .buffered, defer: false)
        panel.title = "会中回顾"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.appearance = NSAppearance(named: .aqua)
        panel.contentView = NSHostingView(rootView: MeetingTimelineView(sessionID: sessionID, compact: true)
            .frame(minWidth: 420, minHeight: 360).preferredColorScheme(.light))
        panel.contentMinSize = NSSize(width: 420, height: 360)
        if self.panel == nil { panel.center() }
        self.panel = panel
        self.sessionID = sessionID
        panel.orderFrontRegardless()
    }
}
