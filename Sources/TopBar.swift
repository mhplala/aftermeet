import SwiftUI

struct TopBar: View {
    @EnvironmentObject var store: AppStore
    @State private var query = ""
    @State private var bellHover = false
    @State private var showBell = false
    @FocusState private var searchFocused: Bool

    private var todayLabel: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "M月d日 EEE"
        return f.string(from: Date())
    }

    var body: some View {
        HStack(spacing: 14) {
            RecStrip()
            search
                .frame(maxWidth: 330)
            Spacer()
            Text(todayLabel)
                .font(Theme.mono(11.5))
                .foregroundColor(Theme.inkTertiary)
            bell
            avatar
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
            if query.isEmpty {
                Text("⌘K")
                    .font(Theme.mono(10))
                    .foregroundColor(Theme.inkTertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Theme.white)
                    .hairline(Theme.borderDefault, radius: 3)
            } else {
                Button { query = ""; searchFocused = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12)).foregroundColor(Theme.inkMuted)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.55))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Theme.glassBorder, lineWidth: 1))
        .overlay(alignment: .topLeading) { results.offset(y: 40) }
    }

    @ViewBuilder
    private var results: some View {
        let hits = store.search(query)
        if searchFocused && !query.isEmpty {
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
            .background(Color.white.opacity(0.75))
            .clipShape(RoundedRectangle(cornerRadius: Theme.rLG, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.rLG, style: .continuous)
                .strokeBorder(Color.white.opacity(0.9), lineWidth: 1))
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

    // MARK: bell — 需要处理的事，不再是摆设

    private var bell: some View {
        Button { showBell.toggle() } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(Theme.inkPrimary.opacity(0.8))
                    .frame(width: 33, height: 33)
                    .background(bellHover ? Color.white.opacity(0.85) : Color.white.opacity(0.58))
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Theme.glassBorder, lineWidth: 1))
                if !store.notifications.isEmpty {
                    Circle().fill(Theme.danger500).frame(width: 7, height: 7)
                        .glow(Theme.danger500, radius: 5, opacity: 0.7)
                        .offset(x: -6, y: 7)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { bellHover = $0 }
        .popover(isPresented: $showBell, arrowEdge: .bottom) { bellPanel }
    }

    private var bellPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("待处理")
                .font(Theme.mono(10, .semibold)).tracking(1.0).textCase(.uppercase)
                .foregroundColor(Theme.inkTertiary)
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)
            if store.notifications.isEmpty {
                Text("暂无待处理事项。")
                    .font(Theme.ui(12.5)).foregroundColor(Theme.inkSecondary)
                    .padding(.horizontal, 14).padding(.bottom, 14).padding(.top, 4)
            } else {
                ForEach(store.notifications) { n in
                    Button {
                        showBell = false
                        store.go(n.screen)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: n.icon)
                                .font(.system(size: 13)).foregroundColor(Theme.accent)
                                .frame(width: 18).padding(.top, 1)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(n.text).font(Theme.ui(12.5, .medium)).foregroundColor(Theme.inkPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(n.meta).font(Theme.mono(10.5)).foregroundColor(Theme.inkTertiary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Color.clear.frame(height: 8)
            }
        }
        .frame(width: 290, alignment: .leading)
    }

    private var avatar: some View {
        Text(store.userName.isEmpty ? "…" : store.userInitial)
            .font(Theme.display(14.5, .medium))
            .foregroundColor(.white)
            .frame(width: 33, height: 33)
            .background(Theme.greenGrad)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color.white.opacity(0.8), lineWidth: 1.5))
            .glow(Theme.accent, radius: 8, opacity: 0.3)
            .help(store.userName)
    }
}
