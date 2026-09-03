import SwiftUI

struct TranscriptFile: Identifiable, Sendable {
    let id = UUID()
    let url: URL          // first fragment (for "reveal in Finder")
    let title: String
    let chars: Int
    let preview: String
    let body: String
    let paragraphs: [String]   // 预切好的段落，几万字全文用 LazyVStack 按段懒渲染
    let start: Date            // 首段开始（文件名解析）
    let end: Date              // 末段最后写入 —— 补生成纪要时用作停录时刻
}

/// 会议库 —— 所有会议的家：纪要（按天分组）+ 原始转写（本地存档全文）。
/// 详情页不再是一级目录，从这里（或概览/搜索）点进去。
struct LibraryScreen: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        ScrollView {
            // 注意：这里必须是普通 VStack —— 内层（转写全文）是 LazyVStack，
            // Lazy 嵌套 Lazy 会退化成全量 measureEstimates，几千段落直接卡死主线程。
            VStack(alignment: .leading, spacing: 0) {
                header
                if store.libraryRawTab {
                    Button { store.libraryRawTab = false } label: {
                        Label("返回会议", systemImage: "chevron.left")
                            .font(Theme.ui(12.5, .semibold)).foregroundColor(Theme.inkSecondary)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    TranscriptArchiveView()
                } else {
                    notesList
                }
            }
            .frame(maxWidth: 880, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(32)
        }
    }

    private var header: some View {
        Text(store.libraryRawTab ? "转写档案" : "会议")
            .font(Theme.display(36, .semibold)).tracking(-0.8)
            .foregroundColor(Theme.inkPrimary)
            .padding(.bottom, 12)
    }

    // MARK: - 纪要 tab

    @ViewBuilder
    private var notesList: some View {
        if store.meetings.isEmpty {
            Card(padding: 0) {
                EmptyState(icon: "books.vertical", title: "暂无会议记录",
                           message: "使用顶部「录制」开始第一场会议，或等待飞书自动同步。")
            }
            .padding(.top, 14)
        } else {
            ForEach(store.meetingsByDay, id: \.day) { group in
                dayHeader(group.day)
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(group.items.enumerated()), id: \.element.id) { idx, m in
                            Button { openMeeting(m) } label: {
                                row(m, last: idx == group.items.count - 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 3)
                }
            }
            // dayChip 解析不出的（样例等）兜底一组
            let undated = store.meetings.filter { $0.dayChip == "·" }
            if !undated.isEmpty {
                dayHeader("未标日期")
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(undated.enumerated()), id: \.element.id) { idx, m in
                            Button { openMeeting(m) } label: {
                                row(m, last: idx == undated.count - 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 3)
                }
            }
        }
    }

    private func dayHeader(_ day: String) -> some View {
        Text(day).font(Theme.mono(11, .semibold)).foregroundColor(Theme.inkPrimary)
        .padding(.top, 18).padding(.bottom, 8)
    }

    private func row(_ m: MeetingVM, last: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 13) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(m.title)
                        .font(Theme.ui(13.5, .medium)).foregroundColor(Theme.inkPrimary).lineLimit(1)
                    Text(m.recentMeta).font(Theme.mono(10.5)).foregroundColor(Theme.inkTertiary)
                }
                Spacer()
                Pill(text: statusLabel(m).0, bg: statusLabel(m).1, fg: statusLabel(m).2, size: 10.5)
            }
            .padding(.vertical, 12).padding(.horizontal, 8)
            .contentShape(Rectangle())
            if !last { Hairline() }
        }
    }

    /// 状态标：待确认 > 待认领 > 已确认/闭环进度
    private func statusLabel(_ m: MeetingVM) -> (String, Color, Color) {
        if m.displayBlocks.contains(where: { $0.type == "refinePending" }) {
            return ("生成中", Theme.blue50, Theme.blue700)
        }
        if m.displayBlocks.contains(where: { $0.type == "refineFailed" }) {
            return ("生成失败", Theme.danger50, Theme.danger500)
        }
        let todos = store.ctodos.filter { $0.key.hasPrefix("\(m.id)|") }
        let pending = todos.filter { $0.status == .candidate }.count
        let open = todos.filter { $0.status == .doing || $0.status == .overdue }.count
        let done = todos.filter { $0.status == .done }.count
        if pending > 0 { return ("待确认 \(pending)", Theme.warn50, Theme.warn500) }
        if open > 0 { return ("进行中 \(open)", Theme.blue50, Theme.blue700) }
        if todos.isEmpty { return ("无待办", Theme.warmWhite2, Theme.inkSecondary) }
        return ("已完成 \(done)", Theme.green50, Theme.green700)
    }

    private func openMeeting(_ m: MeetingVM) {
        if let idx = store.meetings.firstIndex(where: { $0.id == m.id }) {
            store.selectMeeting(idx)
        } else {
        }
    }
}

// MARK: - 原始转写 tab（原「转写历史」整体併入，含合并逻辑 + 全文查看）

struct TranscriptArchiveView: View {
    @EnvironmentObject var store: AppStore
    @State private var files: [TranscriptFile] = []
    @State private var selected: TranscriptFile?
    @State private var loading = true

    nonisolated static var dir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AfterMeet/transcripts")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let sel = selected { detail(sel) } else { list }
        }
        .padding(.top, 14)
        .task {
            // 文件 IO + 解析放后台，几十个 .txt 不卡主线程
            let loaded = await Task.detached(priority: .userInitiated) { Self.loadFiles() }.value
            files = loaded
            loading = false
            // 搜索命中的档案 → 直接打开那条
            if let target = store.archiveTargetTitle {
                selected = loaded.first { $0.title == target }
                store.archiveTargetTitle = nil
            }
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("相邻的转写片段自动合并为一条记录，点击查看全文。内容实时保存。")
                .font(Theme.ui(12.5)).foregroundColor(Theme.inkTertiary)
                .padding(.bottom, 14)

            if loading {
                Card(padding: 0) {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("正在读取本地存档…").font(Theme.ui(13)).foregroundColor(Theme.inkTertiary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 36)
                }
            } else if files.isEmpty {
                Card(padding: 0) {
                    EmptyState(icon: "doc.text", title: "暂无转写记录",
                               message: "使用顶部「录制」开始记录，文字会实时保存到这里。")
                }
            } else {
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        // 行内有「生成纪要」按钮，外层不能再包 Button（嵌套按钮会吞点击）
                        ForEach(Array(files.enumerated()), id: \.element.id) { idx, f in
                            row(f, last: idx == files.count - 1)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 3)
                }
            }
        }
    }

    private func row(_ f: TranscriptFile, last: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 13) {
                // 导航用 Button（onTapGesture 会被窗口激活时的 first-responder 抢焦点吞掉首击 → 要点两次）；
                // 「生成纪要」是并列的另一个 Button，不嵌套，各自独立命中
                Button { selected = f } label: {
                    HStack(alignment: .top, spacing: 13) {
                        ZStack {
                            RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous)
                                .fill(Theme.warmWhite2).frame(width: 36, height: 36)
                            Image(systemName: "waveform").font(.system(size: 15)).foregroundColor(Theme.inkSecondary)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(f.title).font(Theme.ui(13.5, .medium)).foregroundColor(Theme.inkPrimary).lineLimit(1)
                                Text("\(f.chars) 字").font(Theme.mono(10.5)).foregroundColor(Theme.inkTertiary)
                            }
                            Text(f.preview).font(Theme.ui(12)).foregroundColor(Theme.inkSecondary)
                                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                    }
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)

                // 孤儿录音（这个时间段没有对应的会）→ 一键补生成纪要
                if store.archivePending.contains(f.title) {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("生成中").font(Theme.ui(11.5)).foregroundColor(Theme.inkTertiary)
                    }.padding(.top, 8)
                } else if !store.hasLiveMeeting(overlapping: f.start, f.end) {
                    Button { store.generateFromArchive(f) } label: {
                        Text("生成纪要").font(Theme.ui(11.5, .semibold)).foregroundColor(.white)
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(Theme.inkGrad).clipShape(Capsule())
                            .contentShape(Capsule())
                    }.buttonStyle(.plain).padding(.top, 6)
                }
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.inkMuted).padding(.top, 4)
            }
            .padding(.vertical, 13).padding(.horizontal, 8)
            if !last { Hairline() }
        }
    }

    private func detail(_ f: TranscriptFile) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { selected = nil } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                    Text("原始转写").font(Theme.ui(12.5, .semibold))
                }
                .foregroundColor(Theme.inkSecondary)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Theme.glassFill)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Theme.borderDefault, lineWidth: 1))
            }.buttonStyle(.plain).padding(.bottom, 14)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(f.title).font(Theme.display(24, .semibold)).tracking(-0.4).foregroundColor(Theme.inkPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button { NSWorkspace.shared.activateFileViewerSelecting([f.url]) } label: {
                    Text("在访达中显示").font(Theme.ui(12, .semibold)).foregroundColor(Theme.inkPrimary.opacity(0.85))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Theme.white)
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(Theme.borderDefault, lineWidth: 1))
                }.buttonStyle(.plain)
            }
            .padding(.bottom, 6)
            Text("\(f.chars) 字").font(Theme.mono(11.5)).foregroundColor(Theme.inkTertiary).padding(.bottom, 16)

            Card(padding: 22) {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(f.paragraphs.enumerated()), id: \.offset) { _, para in
                        Text(para)
                            .font(Theme.ui(14)).foregroundColor(Theme.inkPrimary.opacity(0.88))
                            .lineSpacing(6).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: load + merge contiguous fragments

    private struct Frag { let url: URL; let start: Date; let end: Date; let name: String; let dateStr: String; let body: String }

    nonisolated static func loadFiles() -> [TranscriptFile] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: Self.dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let dd = DateFormatter(); dd.locale = Locale(identifier: "zh_CN"); dd.dateFormat = "M月d日 HH:mm"

        let frags: [Frag] = urls.filter { $0.pathExtension == "txt" }.compactMap { url in
            let raw = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let lines = raw.components(separatedBy: "\n")
            let header = (lines.first ?? "").replacingOccurrences(of: "# ", with: "")
            let name = header.components(separatedBy: " · ").first?.trimmingCharacters(in: .whitespaces) ?? ""
            let body = lines.dropFirst().filter { !$0.isEmpty }.joined(separator: "\n")
            let start = startFromFilename(url) ?? .distantPast
            let end = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? start
            return Frag(url: url, start: start, end: end, name: name, dateStr: dd.string(from: start), body: body)
        }.sorted { $0.start < $1.start }

        // group by contiguity: gap between a fragment's start and the running group's last end < 12 min
        var groups: [[Frag]] = []
        for f in frags {
            if let last = groups.last?.last, f.start.timeIntervalSince(last.end) < 12 * 60 {
                groups[groups.count - 1].append(f)
            } else { groups.append([f]) }
        }

        let tf = DateFormatter(); tf.dateFormat = "HH:mm"
        let generic: (String) -> Bool = { $0.isEmpty || $0 == "未命名会议" || $0 == "会中实时转写" }
        return groups.map { g -> TranscriptFile in
            // name from the largest non-generic fragment — most representative, usually the 豆包 content name
            let name = g.filter { !generic($0.name) }.max(by: { $0.body.count < $1.body.count })?.name ?? "未命名会议"
            let body = g.map { $0.body }.joined(separator: "\n")
            let dayPart = g.first!.dateStr.components(separatedBy: " ").first ?? ""
            let span = "\(tf.string(from: g.first!.start))–\(tf.string(from: g.last!.end))"
            let title = g.count > 1
                ? "\(name) · \(dayPart) \(span)（\(g.count) 段合并）"
                : "\(name) · \(g.first!.dateStr)"
            // 段落合并成 ~300 字块：既保留懒加载粒度，又把子视图数压低一个量级
            var paras: [String] = []
            var cur = ""
            for line in body.components(separatedBy: "\n") {
                let t = line.trimmingCharacters(in: .whitespaces)
                guard !t.isEmpty else { continue }
                if cur.isEmpty { cur = t }
                else if cur.count + t.count < 300 { cur += "\n" + t }
                else { paras.append(cur); cur = t }
            }
            if !cur.isEmpty { paras.append(cur) }
            return TranscriptFile(url: g.first!.url, title: title, chars: body.count,
                                  preview: String(body.replacingOccurrences(of: "\n", with: " ").prefix(90)),
                                  body: body, paragraphs: paras,
                                  start: g.first!.start, end: g.last!.end)
        }.reversed()
    }

    nonisolated private static func startFromFilename(_ url: URL) -> Date? {
        let s = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "会中转写-", with: "")
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd-HHmmss"; df.timeZone = .current
        return df.date(from: s)
    }
}
