import SwiftUI

struct TranscriptFile: Identifiable {
    let id = UUID()
    let url: URL          // first fragment (for "reveal in Finder")
    let title: String
    let chars: Int
    let preview: String
    let body: String
    let paragraphs: [String]   // 预切好的段落，几万字全文用 LazyVStack 按段懒渲染
}

/// 会议库 —— 所有会议的家：纪要（按天分组）+ 原始转写（本地存档全文）。
/// 详情页不再是一级目录，从这里（或概览/搜索）点进去。
struct LibraryScreen: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                tabs.padding(.top, 18).padding(.bottom, 6)
                if store.libraryRawTab {
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
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    Overline("全部会议", tracking: 1.2).padding(.bottom, 8)
                    Text("会议库")
                        .font(Theme.display(36, .semibold)).tracking(-0.8)
                        .foregroundColor(Theme.inkPrimary)
                }
                Spacer()
                Text(store.libraryRawTab
                     ? "本地存档 · 仅保存在本机"
                     : "\(store.meetings.count) 场 · \(store.ctodos.count) 条待办")
                    .font(Theme.mono(11)).foregroundColor(Theme.inkTertiary)
            }
        }
    }

    private var tabs: some View {
        HStack(spacing: 2) {
            tab("纪要", raw: false)
            tab("原始转写", raw: true)
        }
        .padding(3)
        .background(Theme.paper300.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: Theme.rMD + 2, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.rMD + 2, style: .continuous)
            .strokeBorder(Color.white.opacity(0.55), lineWidth: 1))
        .fixedSize()
    }

    private func tab(_ label: String, raw: Bool) -> some View {
        let on = store.libraryRawTab == raw
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { store.libraryRawTab = raw }
        } label: {
            Text(label)
                .font(Theme.ui(12.5, .semibold))
                .foregroundColor(on ? Theme.inkPrimary : Theme.inkSecondary)
                .padding(.horizontal, 18).padding(.vertical, 8)
                .background(on ? Color.white.opacity(0.92) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: Theme.rMD - 1, style: .continuous))
                .shadow(color: on ? Color(hex: "5862a8").opacity(0.14) : .clear, radius: 4, x: 0, y: 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                dayHeader(group.day, count: group.items.count)
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
                dayHeader("未标日期", count: undated.count)
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

    private func dayHeader(_ day: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(day).font(Theme.mono(11, .semibold)).foregroundColor(Theme.inkPrimary)
            Text("· \(count) 场").font(Theme.mono(10.5)).foregroundColor(Theme.inkTertiary)
        }
        .padding(.top, 18).padding(.bottom, 8)
    }

    private func row(_ m: MeetingVM, last: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 13) {
                Text(m.dayChip)
                    .font(Theme.mono(11.5, .semibold))
                    .foregroundColor(Theme.accentInk)
                    .frame(width: 36, height: 36)
                    .background(
                        LinearGradient(colors: [Theme.accentSurface, Theme.blue50],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.7), lineWidth: 1))
                VStack(alignment: .leading, spacing: 3) {
                    Text(m.title)
                        .font(Theme.ui(13.5, .medium)).foregroundColor(Theme.inkPrimary).lineLimit(1)
                    Text(m.recentMeta).font(Theme.mono(10.5)).foregroundColor(Theme.inkTertiary)
                }
                Spacer()
                Pill(text: statusLabel(m).0, bg: statusLabel(m).1, fg: statusLabel(m).2, size: 10.5)
                Text(m.id.hasPrefix("live-") ? "本地" : "飞书同步")
                    .font(Theme.mono(9.5)).foregroundColor(Theme.inkMuted)
                    .frame(width: 52, alignment: .trailing)
            }
            .padding(.vertical, 12).padding(.horizontal, 8)
            .contentShape(Rectangle())
            if !last { Hairline() }
        }
    }

    /// 状态标：待确认 > 待认领 > 已确认/闭环进度
    private func statusLabel(_ m: MeetingVM) -> (String, Color, Color) {
        let todos = m.dtodos
        let pending = todos.filter { $0.status == .pending }.count
        let unclaimed = todos.filter { $0.status == .unclaimed }.count
        let done = todos.filter { $0.status == .confirmed }.count
        if pending > 0 { return ("待确认 \(pending)", Theme.warn50, Theme.warn500) }
        if unclaimed > 0 { return ("待认领 \(unclaimed)", Theme.warn50, Theme.warn500) }
        if todos.isEmpty { return ("无待办", Theme.warmWhite2, Theme.inkSecondary) }
        return ("已确认 \(done)/\(todos.count)", Theme.green50, Theme.green700)
    }

    private func openMeeting(_ m: MeetingVM) {
        if let idx = store.meetings.firstIndex(where: { $0.id == m.id }) {
            store.selectMeeting(idx)
        }
    }
}

// MARK: - 原始转写 tab（原「转写历史」整体併入，含合并逻辑 + 全文查看）

struct TranscriptArchiveView: View {
    @EnvironmentObject var store: AppStore
    @State private var files: [TranscriptFile] = []
    @State private var selected: TranscriptFile?
    @State private var loading = true

    static var dir: URL {
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
                        ForEach(Array(files.enumerated()), id: \.element.id) { idx, f in
                            Button { selected = f } label: { row(f, last: idx == files.count - 1) }
                                .buttonStyle(.plain)
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
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.inkMuted).padding(.top, 4)
            }
            .padding(.vertical, 13).padding(.horizontal, 8)
            .contentShape(Rectangle())
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
                .background(Color.white.opacity(0.8))
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
                        .background(Color.white)
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

    static func loadFiles() -> [TranscriptFile] {
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
            let paras = body.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            return TranscriptFile(url: g.first!.url, title: title, chars: body.count,
                                  preview: String(body.replacingOccurrences(of: "\n", with: " ").prefix(90)),
                                  body: body, paragraphs: paras)
        }.reversed()
    }

    private static func startFromFilename(_ url: URL) -> Date? {
        let s = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "会中转写-", with: "")
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd-HHmmss"; df.timeZone = .current
        return df.date(from: s)
    }
}
