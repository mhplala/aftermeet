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
            Overline("跨会议 · 任务闭环", tracking: 1.2).padding(.bottom, 8)
            Text("待办中心")
                .font(Theme.display(38, .medium)).tracking(-0.9).foregroundColor(Theme.inkPrimary)
            Text("所有会议的待办集中在这里，完成情况实时计入闭环率。")
                .font(Theme.display(15, .regular))
                .foregroundColor(Theme.inkSecondary).padding(.top, 8)
        }
    }

    private var filterRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                pill("全部 \(store.ctodos.count)", .all)
                pill("未完成 \(openN)", .open)
                pill("逾期 \(overN)", .overdue)
                pill("已完成 \(doneN)", .done)
            }
            .padding(3)
            .background(Color(hex: "ecebe8"))
            .clipShape(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous))
            Spacer()
            Text("闭环率 \(closeRate)%").font(Theme.mono(11.5)).foregroundColor(Theme.inkTertiary)
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
        LazyVStack(spacing: 0) {
            ForEach(Array(visible.enumerated()), id: \.element.id) { idx, t in
                CrossTodoRow(todo: t, last: idx == visible.count - 1)
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
        case .all:     return store.ctodos
        case .open:    return store.ctodos.filter { $0.status != .done }
        case .overdue: return store.ctodos.filter { $0.status == .overdue }
        case .done:    return store.ctodos.filter { $0.status == .done }
        }
    }
    private var openN: Int { store.ctodos.filter { $0.status != .done }.count }
    private var overN: Int { store.ctodos.filter { $0.status == .overdue }.count }
    private var doneN: Int { store.ctodos.filter { $0.status == .done }.count }
    private var closeRate: Int { store.ctodos.isEmpty ? 0 : Int((Double(doneN) / Double(store.ctodos.count) * 100).rounded()) }
}

// MARK: - Cross-meeting todo row

struct CrossTodoRow: View {
    @EnvironmentObject var store: AppStore
    let todo: CrossTodo
    let last: Bool
    @State private var hover = false

    private var done: Bool { todo.status == .done }
    /// 搜索跳转的落点：闪一下这一行
    private var flashing: Bool { store.flashTodoText == todo.text }

    var body: some View {
        Button { store.toggleCtodo(todo.id) } label: {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    checkbox
                    VStack(alignment: .leading, spacing: 3) {
                        Text(todo.text)
                            .font(Theme.ui(14))
                            .foregroundColor(done ? Theme.inkTertiary : Theme.inkPrimary.opacity(0.88))
                            .strikethrough(done, color: Theme.inkTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(todo.meeting).font(Theme.mono(11)).foregroundColor(Theme.inkTertiary)
                    }
                    Spacer(minLength: 8)
                    HStack(spacing: 7) {
                        Avatar(initial: todo.initial, color: todo.color, size: 24)
                        Text(todo.owner).font(Theme.ui(12.5)).foregroundColor(Theme.inkSecondary)
                    }
                    .frame(width: 120, alignment: .leading)
                    Text(dueLabel)
                        .font(Theme.ui(11, .semibold)).foregroundColor(dueFg)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .frame(width: 78)
                        .background(dueBg)
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 22).padding(.vertical, 15)
                .background(flashing ? Theme.blue50
                            : hover ? Color(hex: "f6f7fc") : Theme.white)
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
                .fill(done ? Theme.accent : Color.clear)
                .frame(width: 20, height: 20)
                .overlay {
                    if !done {
                        RoundedRectangle(cornerRadius: Theme.rXS, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.18), lineWidth: 2)
                    }
                }
            if done {
                Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundColor(.white)
            }
        }
    }

    private var dueLabel: String {
        switch todo.status {
        case .overdue: return "逾期·\(todo.due)"
        case .done:    return "已完成"
        case .doing:   return todo.due
        }
    }
    private var dueBg: Color {
        switch todo.status {
        case .overdue: return Theme.danger50
        case .done:    return Theme.green50
        case .doing:   return Theme.warmWhite2
        }
    }
    private var dueFg: Color {
        switch todo.status {
        case .overdue: return Theme.danger500
        case .done:    return Theme.green700
        case .doing:   return Theme.inkSecondary
        }
    }
}
