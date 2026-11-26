import SwiftUI

struct TodosScreen: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header.padding(.bottom, 24)
                filterRow.padding(.bottom, 16)
                list
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("行动项")
                .font(Theme.display(38, .medium)).tracking(-0.9).foregroundColor(Theme.inkPrimary)
            Text("自动提取的内容先确认，再成为正式任务。")
                .font(Theme.display(15, .regular))
                .foregroundColor(Theme.inkSecondary).padding(.top, 8)
        }
    }

    private var filterRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                pill("待确认 \(candidateN)", .candidates)
                pill("进行中 \(openN)", .open)
                pill("已完成 \(doneN)", .done)
            }
            .padding(3)
            .background(Theme.warmWhite2)
            .clipShape(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous))
        }
    }

    private func pill(_ label: String, _ f: TodoFilter) -> some View {
        let on = store.filter == f
        return Button { withAnimation(.easeOut(duration: 0.15)) { store.filter = f } } label: {
            Text(label)
                .font(Theme.ui(12.5, .semibold))
                .foregroundColor(on ? Theme.inkPrimary : Theme.inkSecondary)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(on ? Theme.white : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: Theme.rSM, style: .continuous))
                .shadow(color: on ? .black.opacity(0.06) : .clear, radius: 1, x: 0, y: 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var list: some View {
        Group {
            if visible.isEmpty {
                EmptyState(icon: emptyIcon, title: emptyTitle, message: emptyMessage)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { idx, t in
                        CrossTodoRow(todo: t, last: idx == visible.count - 1)
                    }
                }
            }
        }
        .background(Theme.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rLG, style: .continuous))
        .hairline(Theme.borderWhisper, radius: Theme.rLG)
        .whisperShadow()
    }

    // derived
    private var visible: [CrossTodo] {
        switch store.filter {
        case .candidates: return store.ctodos.filter { $0.status == .candidate }
        case .open:    return store.officialTodos.filter { $0.status != .done }
        case .done:    return store.ctodos.filter { $0.status == .done }
        }
    }
    private var candidateN: Int { store.candidateCount }
    private var openN: Int { store.openCount }
    private var doneN: Int { store.ctodos.filter { $0.status == .done }.count }
    private var emptyIcon: String { store.filter == .candidates ? "checkmark.seal" : "checkmark.circle" }
    private var emptyTitle: String { store.filter == .candidates ? "没有待确认内容" : "这里暂时为空" }
    private var emptyMessage: String {
        store.filter == .candidates ? "新会议提取出的行动项会先出现在这里。" : "确认后的任务会按进度显示。"
    }
}

// MARK: - Cross-meeting todo row

struct CrossTodoRow: View {
    @EnvironmentObject var store: AppStore
    let todo: CrossTodo
    let last: Bool
    @State private var hover = false

    private var done: Bool { todo.status == .done }
    private var candidate: Bool { todo.status == .candidate }
    /// 搜索跳转的落点：闪一下这一行
    private var flashing: Bool { store.flashTodoText == todo.text }

    var body: some View {
        Button {
            candidate ? store.openCandidate(todo) : store.toggleCtodo(todo.id)
        } label: {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    if candidate {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 15)).foregroundColor(Theme.warn500)
                            .frame(width: 20)
                    } else {
                        checkbox
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(todo.text)
                            .font(Theme.ui(14))
                            .foregroundColor(done ? Theme.inkTertiary : Theme.inkPrimary.opacity(0.88))
                            .strikethrough(done, color: Theme.inkTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(todo.meeting).font(Theme.mono(11)).foregroundColor(Theme.inkTertiary)
                    }
                    Spacer(minLength: 8)
                    if candidate {
                        Text("去确认")
                            .font(Theme.ui(11.5, .semibold)).foregroundColor(Theme.warn500)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold)).foregroundColor(Theme.inkMuted)
                    } else {
                        if todo.owner != "待认领" {
                            Text(todo.owner).font(Theme.ui(12.5)).foregroundColor(Theme.inkSecondary)
                                .frame(width: 80, alignment: .leading)
                        }
                        if todo.status == .done || todo.due != "—" {
                            Text(dueLabel)
                                .font(Theme.ui(11, .semibold)).foregroundColor(dueFg)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .frame(width: 78)
                                .background(dueBg)
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal, 22).padding(.vertical, 15)
                .background(flashing ? Theme.blue50
                            : hover ? Theme.warmWhite : Theme.white)
                .animation(.easeOut(duration: 0.4), value: flashing)
                .contentShape(Rectangle())
                if !last { Hairline() }
            }
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }

    private var checkbox: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.rXS, style: .continuous)
                // 完成态用「深浅都深」的底 + 白勾：accent 深色会翻成近白，白底白勾会刺眼且看不见勾
                .fill(done ? Theme.dyn("111111", "3a3a40") : Color.clear)
                .frame(width: 20, height: 20)
                .overlay {
                    if !done {
                        RoundedRectangle(cornerRadius: Theme.rXS, style: .continuous)
                            .strokeBorder(Theme.borderStrong, lineWidth: 2)
                    }
                }
            if done {
                Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundColor(.white)
            }
        }
    }

    private var dueLabel: String {
        switch todo.status {
        case .candidate: return "待确认"
        case .overdue: return "逾期·\(todo.due)"
        case .done:    return "已完成"
        case .doing:   return todo.due
        }
    }
    private var dueBg: Color {
        switch todo.status {
        case .candidate: return Theme.warn50
        case .overdue: return Theme.danger50
        case .done:    return Theme.green50
        case .doing:   return Theme.warmWhite2
        }
    }
    private var dueFg: Color {
        switch todo.status {
        case .candidate: return Theme.warn500
        case .overdue: return Theme.danger500
        case .done:    return Theme.green700
        case .doing:   return Theme.inkSecondary
        }
    }
}
