import SwiftUI

struct TopBar: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject private var timelines = MeetingTimelineStore.shared
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: 14) {
            RecStrip()
            RecControls()
            if let id = timelines.activeSessionID,
               let doc = timelines.documents[id], doc.state == .recording {
                Button { store.openTimeline(sessionID: doc.id) } label: {
                    Label("进展 · \(doc.chunks.count) 段", systemImage: "clock.arrow.circlepath")
                        .font(Theme.ui(11.5, .medium)).foregroundColor(Theme.blue700)
                }.buttonStyle(.plain).help("查看进行中会议的进展")
            }
            search
                .frame(maxWidth: 330)
            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(height: 60)
        .background(VisualEffect(material: .headerView))   // 系统玻璃标题栏
        .overlay(alignment: .bottom) { Hairline() }
        .background {   // ⌘K 聚焦搜索
            Button("") { searchFocused = true }
                .keyboardShortcut("k", modifiers: .command)
                .opacity(0)
        }
        .onAppear {
            // AppKit 默认把窗口首个文本框设为第一响应者 → 搜索框一直亮着光标；启动后清掉
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if !searchFocused { NSApp.keyWindow?.makeFirstResponder(nil) }
            }
        }
        // 窗口每次重新成为 key，AppKit 都会把焦点还给唯一的文本框；焦点在文本框上时，
        // 用户的第一次点击会被用来收回焦点（事件被吞）→ "会议要点两次才打开"。
        // 只要不是用户主动聚焦（⌘K/点击搜索框），激活后就立刻清掉第一响应者。
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            guard let w = note.object as? NSWindow, w.frame.width > 500 else { return }   // 忽略弹窗小窗
            DispatchQueue.main.async {
                if !searchFocused, w.firstResponder is NSTextView {
                    w.makeFirstResponder(nil)
                }
            }
        }
    }

    // MARK: search — 会议标题/摘要/逐字稿 + 待办/负责人 全文匹配

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.inkTertiary)
            TextField("搜索会议、待办、负责人…", text: $query)
                .textFieldStyle(.plain)
                .font(Theme.ui(13))
                .focused($searchFocused)
                .onSubmit {
                    if let first = store.search(query).first { open(first) }
                }
            if !query.isEmpty {
                Button { query = ""; searchFocused = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12)).foregroundColor(Theme.inkMuted)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
        .background(Theme.glassFill)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Theme.borderDefault, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.10), radius: 5, x: 0, y: 2)
        .overlay(alignment: .topLeading) { results.offset(y: 40) }
    }

    @ViewBuilder
    private var results: some View {
        if searchFocused && !query.isEmpty {
            let hits = store.search(query)
            VStack(alignment: .leading, spacing: 0) {
                if hits.isEmpty {
                    Text("未找到与「\(query)」相关的内容")
                        .font(Theme.ui(12.5)).foregroundColor(Theme.inkTertiary)
                        .padding(.horizontal, 14).padding(.vertical, 12)
                } else {
                    let groups: [AppStore.SearchKind] = [.meeting, .todo, .archive]
                    ForEach(groups, id: \.rawValue) { kind in
                        let inGroup = hits.filter { $0.kind == kind }
                        if !inGroup.isEmpty {
                            Text(kind.rawValue)
                                .font(Theme.mono(9.5, .semibold)).tracking(1.0)
                                .foregroundColor(Theme.inkMuted)
                                .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 3)
                            ForEach(inGroup) { h in resultRow(h) }
                        }
                    }
                    Color.clear.frame(height: 8)
                }
            }
            .frame(width: 380, alignment: .leading)
            .background(.ultraThinMaterial)
            .background(Theme.glassFill)
            .clipShape(RoundedRectangle(cornerRadius: Theme.rLG, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.rLG, style: .continuous)
                .strokeBorder(Theme.glassBorder, lineWidth: 1))
            .popShadow()
        }
    }

    private func resultRow(_ h: AppStore.SearchHit) -> some View {
        Button { open(h) } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: h.icon)
                    .font(.system(size: 12)).foregroundColor(Theme.inkTertiary)
                    .frame(width: 16).padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(h.title).font(Theme.ui(13, .medium)).foregroundColor(Theme.inkPrimary).lineLimit(1)
                    Text(h.meta).font(Theme.mono(10)).foregroundColor(Theme.inkTertiary).lineLimit(1)
                    if let sn = h.snippet {
                        Text(sn)
                            .font(Theme.ui(11.5)).foregroundColor(Theme.inkSecondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func open(_ h: AppStore.SearchHit) {
        store.open(h)
        query = ""
        searchFocused = false
    }

}
