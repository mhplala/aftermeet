import SwiftUI

struct DetailScreen: View {
    @EnvironmentObject var store: AppStore
    @State private var question = ""

    private var m: MeetingVM { store.current }
    private var decisions: [Decision] { m.decisions }
    private var disputes: [Dispute] { m.disputes }
    private var transcript: [TranscriptLine] { m.transcript }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                // 普通 VStack：页内大量 fixedSize 多行文本，放进 Lazy 容器会触发测量循环卡死主线程
                VStack(alignment: .leading, spacing: 14) {
                    breadcrumb
                    titleRow
                    metaRow
                    if let suggestion = store.calendarSuggestions[m.id] { renameChip(suggestion) }
                    if let failure = m.displayBlocks.first(where: { $0.type == "refineFailed" }) {
                        regenBanner(failure.text ?? "")
                    }
                    NoteBlocksView(blocks: m.displayBlocks).padding(.top, 4)
                    todosSection
                    transcriptSection
                    qaSection
                    Color.clear.frame(height: 8)
                }
                .frame(maxWidth: 920, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(32)
            }
            actionBar
        }
        .task(id: m.id) { store.checkCalendarName(for: m) }
    }

    /// 时间戳 × 日历命中了别的名字 → 给一条可采用的改名建议
    private func renameChip(_ suggestion: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar").font(.system(size: 11)).foregroundColor(Theme.blue700)
            Text("日历中该时段是「\(suggestion)」")
                .font(Theme.ui(12)).foregroundColor(Theme.blue700).lineLimit(1)
            Button { store.adoptCalendarName(id: m.id) } label: {
                Text("改用此名").font(Theme.ui(11.5, .semibold)).foregroundColor(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Theme.blue500).clipShape(Capsule())
                    .contentShape(Capsule())
            }.buttonStyle(.plain)
            Button { store.calendarSuggestions[m.id] = nil } label: {
                Text("忽略").font(Theme.ui(11.5)).foregroundColor(Theme.inkTertiary)
                    .padding(.horizontal, 6).padding(.vertical, 4)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Theme.blue50)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous))
    }

    /// 提炼失败入库的会：给出原因和重试入口（转写完好，随时可再生成）
    private func regenBanner(_ reason: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 11)).foregroundColor(Theme.warn500)
            Text("纪要生成失败\(reason.isEmpty ? "" : "：\(reason)")，转写已完整保存")
                .font(Theme.ui(12)).foregroundColor(Theme.inkSecondary).lineLimit(2)
            if store.regenPending.contains(m.id) {
                ProgressView().controlSize(.small).padding(.leading, 2)
            } else {
                Button { store.regenerateNote(id: m.id) } label: {
                    Text("重新生成").font(Theme.ui(11.5, .semibold)).foregroundColor(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Theme.inkGrad).clipShape(Capsule())
                        .contentShape(Capsule())
                }.buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Theme.warmWhite)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous))
    }

    // MARK: header

    private var breadcrumb: some View {
        HStack(spacing: 10) {
            if store.canGoBack {
                Button { store.goBack() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
                        Text("返回").font(Theme.ui(11.5, .semibold))
                    }
                    .foregroundColor(Theme.inkSecondary)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.white)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Theme.borderDefault, lineWidth: 1))
                    .contentShape(Capsule())
                }.buttonStyle(.plain)
            }
            Button { store.go(.library) } label: {
                Text("会议库").font(Theme.mono(11)).tracking(1.0).foregroundColor(Theme.inkTertiary)
            }.buttonStyle(.plain)
            Text("· 会议纪要").font(Theme.mono(11)).tracking(1.0).foregroundColor(Theme.inkTertiary)
            Spacer()
            switcher
        }
        .textCase(.uppercase)
    }

    /// ‹ 上一场 / 下一场 ›（时间序，到头禁用）
    private var switcher: some View {
        HStack(spacing: 5) {
            stepButton("chevron.left", enabled: store.canPrevMeeting) { store.stepMeeting(-1) }
            Text(store.meetingPos).font(Theme.mono(10.5)).foregroundColor(Theme.inkTertiary)
                .padding(.horizontal, 3)
            stepButton("chevron.right", enabled: store.canNextMeeting) { store.stepMeeting(1) }
        }
        .textCase(nil)
    }

    private func stepButton(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(Theme.inkSecondary)
                .frame(width: 28, height: 28)
                .background(Color.white)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Theme.borderDefault, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
    }

    private var titleRow: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(m.title)
                .font(Theme.display(36, .medium))
                .tracking(-0.7)
                .foregroundColor(Theme.inkPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Pill(text: m.badge, bg: Theme.accentSurface, fg: Theme.accentInk)
                .padding(.top, 8)
        }
    }

    private var metaRow: some View {
        HStack(spacing: 8) {
            ForEach(Array(m.metaParts.enumerated()), id: \.offset) { _, p in
                metaText(p)
                metaText("·")
            }
            Text(m.metaAccent).font(Theme.mono(12)).foregroundColor(Theme.accent)
        }
    }

    private func metaText(_ s: String) -> some View {
        Text(s).font(Theme.mono(12)).foregroundColor(Theme.inkTertiary)
    }

    // MARK: sections

    private var insightsSection: some View {
        SectionCard(dot: Theme.brand500, title: "深度要点", count: m.keyPoints.count,
                    expanded: store.secInsights) { store.secInsights.toggle() } content: {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(m.keyPoints.enumerated()), id: \.offset) { _, p in
                    HStack(alignment: .top, spacing: 12) {
                        Circle().fill(Theme.brand500).frame(width: 5, height: 5).padding(.top, 8)
                        Text(p).font(Theme.ui(14)).foregroundColor(Theme.inkPrimary.opacity(0.85))
                            .lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 11)
                    .overlay(alignment: .top) { Hairline() }
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 8)
        }
    }

    private var decisionsSection: some View {
        SectionCard(dot: Theme.accent, title: "结论与决策", count: decisions.count,
                    expanded: store.secDecisions) { store.secDecisions.toggle() } content: {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(decisions) { d in
                    HStack(alignment: .top, spacing: 12) {
                        Text(d.no).font(Theme.mono(12, .semibold)).foregroundColor(Theme.accent).padding(.top, 2)
                        Text(d.text).font(Theme.ui(14)).foregroundColor(Theme.inkPrimary.opacity(0.85))
                            .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 11)
                    .overlay(alignment: .top) { Hairline() }
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 8)
        }
    }

    private var todosSection: some View {
        SectionCard(dot: Theme.blue500, title: "待办", count: store.dtodos.count,
                    expanded: store.secTodos, toggle: { store.secTodos.toggle() },
                    trailing: {
                        Pill(text: "\(store.unclaimedCount) 待认领", bg: Theme.warn50, fg: Theme.warn500, size: 11)
                    }, content: {
            VStack(spacing: 0) {
                ForEach(store.dtodos) { t in
                    DetailTodoRow(todo: t).overlay(alignment: .top) { Hairline() }
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 4)
        })
    }

    private var disputesSection: some View {
        SectionCard(dot: Theme.warn500, title: "分歧与未决项", count: disputes.count,
                    expanded: store.secDisputes) { store.secDisputes.toggle() } content: {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(disputes) { d in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(d.title).font(Theme.ui(14, .medium)).foregroundColor(Theme.inkPrimary.opacity(0.88))
                        Text(d.body).font(Theme.ui(13)).foregroundColor(Theme.inkSecondary)
                            .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 13)
                    .overlay(alignment: .top) { Hairline() }
                }
                if !m.nextAgenda.isEmpty { nextAgenda.padding(.top, 6) }
            }
            .padding(.horizontal, 20).padding(.bottom, 8)
        }
    }

    private var nextAgenda: some View {
        VStack(alignment: .leading, spacing: 8) {
            Overline("下次会议建议议题", color: Theme.blue600, size: 10.5, tracking: 0.8)
            Text(m.nextAgenda.map { "· \($0)" }.joined(separator: "\n"))
                .font(Theme.ui(13)).foregroundColor(Theme.blue700).lineSpacing(7)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.blue50)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous))
    }

    private var transcriptSection: some View {
        SectionCard(dot: Theme.inkMuted, title: "原始逐字稿",
                    expanded: store.secTranscript, toggle: { store.secTranscript.toggle() },
                    trailing: {
                        Text(m.transcriptNote).font(Theme.mono(11)).foregroundColor(Theme.inkTertiary)
                    }, content: {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(transcript) { tr in
                    HStack(alignment: .top, spacing: 12) {
                        Text(tr.time).font(Theme.mono(11)).foregroundColor(Theme.inkMuted)
                            .frame(width: 46, alignment: .leading).padding(.top, 2)
                        Text(tr.who).font(Theme.ui(12.5, .semibold)).foregroundColor(Theme.inkPrimary.opacity(0.8))
                            .frame(width: 40, alignment: .leading).padding(.top, 1)
                        Text(tr.text).font(Theme.ui(13)).foregroundColor(Theme.inkSecondary)
                            .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 9)
                    .overlay(alignment: .top) { Hairline() }
                }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(m.rawTranscript, forType: .string)
                    store.showToast("完整逐字稿已复制（\(m.rawTranscript.count) 字）")
                } label: {
                    Text("复制完整逐字稿 →")
                        .font(Theme.mono(11.5)).foregroundColor(Theme.blue500)
                        .padding(.vertical, 6).padding(.trailing, 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
            .padding(.horizontal, 20).padding(.bottom, 18).padding(.top, 4)
        })
    }

    // MARK: 问答

    private var qaSection: some View {
        let thread = store.qaThreads[m.id] ?? []
        let pending = store.qaPending.contains(m.id)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Dot(color: Theme.blue500)
                Text("问这场会").font(Theme.display(18, .medium)).foregroundColor(Theme.inkPrimary)
                Spacer()
                Text("基于逐字稿回答").font(Theme.mono(11)).foregroundColor(Theme.inkTertiary)
            }
            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)

            if thread.isEmpty && !pending {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(["这场会定了什么？", "有哪些待办、谁负责？", "有什么分歧没拍板？"], id: \.self) { q in
                        Button { ask(q) } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "sparkle").font(.system(size: 10)).foregroundColor(Theme.blue500)
                                Text(q).font(Theme.ui(13)).foregroundColor(Theme.blue700)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Theme.blue50)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.rSM, style: .continuous))
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 8)
            }

            if !thread.isEmpty || pending {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(thread) { qaTurn($0) }
                    if pending {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("正在检索逐字稿…").font(Theme.ui(13)).foregroundColor(Theme.inkTertiary)
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 14)
            }

            HStack(spacing: 10) {
                TextField("就这场会提问…", text: $question)
                    .textFieldStyle(.plain).font(Theme.ui(13.5))
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Theme.warmWhite)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous))
                    .hairline(Theme.borderDefault, radius: Theme.rMD)
                    .onSubmit { ask(question) }
                Button { ask(question) } label: {
                    Image(systemName: "arrow.up").font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(canSend ? Theme.accent : Theme.inkMuted)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous))
                }.buttonStyle(.plain).disabled(!canSend)
            }
            .padding(.horizontal, 20).padding(.bottom, 18).padding(.top, 4)
        }
        .background(Theme.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rLG, style: .continuous))
        .hairline(Theme.borderWhisper, radius: Theme.rLG)
        .whisperShadow()
    }

    private var canSend: Bool {
        !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !store.qaPending.contains(m.id)
    }

    private func qaTurn(_ t: QATurn) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 8) {
                Text("问").font(Theme.mono(11, .semibold)).foregroundColor(Theme.blue700)
                    .padding(.horizontal, 6).padding(.vertical, 2).background(Theme.blue50).clipShape(Capsule())
                Text(t.question).font(Theme.ui(14, .medium)).foregroundColor(Theme.inkPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let a = t.answer {
                Text(a).font(Theme.ui(14)).foregroundColor(Theme.inkPrimary.opacity(0.85)).lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true).padding(.leading, 28)
                    .textSelection(.enabled)
            }
        }
    }

    private func ask(_ q: String) {
        let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.askCurrentMeeting(trimmed)
        question = ""
    }

    // MARK: pinned action bar

    @State private var showForward = false

    private var actionBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.confirmHint).font(Theme.ui(13, .semibold)).foregroundColor(Theme.inkPrimary)
                Text(store.usingRealData ? "确认后自动创建飞书任务并通知负责人"
                                         : "示例数据 · 不会创建真实任务")
                    .font(Theme.mono(11)).foregroundColor(Theme.inkTertiary)
            }
            Spacer()
            Button { showForward = true } label: {
                Text("转发到群").font(Theme.ui(13, .semibold)).foregroundColor(Theme.inkPrimary.opacity(0.85))
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(Color.white.opacity(0.75))
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Theme.borderDefault, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showForward, arrowEdge: .top) {
                ForwardPicker(meetingTitle: m.title) { chat in
                    showForward = false
                    store.forward(to: chat)
                }
            }
            Button { store.confirmAll() } label: {
                Text("全部确认并建任务").font(Theme.ui(13, .semibold)).foregroundColor(.white)
                    .padding(.horizontal, 18).padding(.vertical, 9)
                    .background(Theme.inkGrad)
                    .clipShape(Capsule())
                    .glow(Color.black, radius: 9, opacity: 0.28)
            }.buttonStyle(.plain)
        }
        .padding(.leading, 21).padding(.trailing, 13).padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .background(Color.white.opacity(0.72))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.85), lineWidth: 1))
        .popShadow()
        .frame(maxWidth: 920, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 32)
        .padding(.bottom, 20)
        .padding(.top, 6)
        .background(Theme.canvas)
    }
}

// MARK: - 转发到群：搜群 → 选一个 → 真发（markdown 纪要）

struct ForwardPicker: View {
    @EnvironmentObject var store: AppStore
    let meetingTitle: String
    var copyMarkdown: String? = nil       // 「复制」按钮的内容；nil = 当前会议纪要
    let onPick: (Lark.Chat) -> Void

    @State private var query = ""
    @State private var chats: [Lark.Chat] = []
    @State private var searching = false
    @State private var searched = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("发到哪个群")
                .font(Theme.mono(10, .semibold)).tracking(1.0).textCase(.uppercase)
                .foregroundColor(Theme.inkTertiary)
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundColor(Theme.inkTertiary)
                TextField("搜群名…", text: $query)
                    .textFieldStyle(.plain).font(Theme.ui(12.5))
                    .onSubmit { search() }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Theme.searchBg)
            .clipShape(RoundedRectangle(cornerRadius: Theme.rSM, style: .continuous))
            .padding(.horizontal, 12).padding(.bottom, 8)

            if searching {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("搜索中…").font(Theme.ui(12)).foregroundColor(Theme.inkTertiary)
                }.padding(.horizontal, 14).padding(.vertical, 10)
            } else if chats.isEmpty && searched {
                Text("没搜到相关的群，换个词试试")
                    .font(Theme.ui(12)).foregroundColor(Theme.inkTertiary)
                    .padding(.horizontal, 14).padding(.vertical, 10)
            } else {
                ForEach(chats) { c in
                    Button { onPick(c) } label: {
                        HStack(spacing: 9) {
                            Image(systemName: "person.2").font(.system(size: 11)).foregroundColor(Theme.inkTertiary)
                            Text(c.name).font(Theme.ui(12.5)).foregroundColor(Theme.inkPrimary).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }

            Divider().padding(.vertical, 4)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(copyMarkdown ?? AppStore.noteMarkdown(store.current),
                                               forType: .string)
                store.showToast("已复制，可手动粘贴到任何群")
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "doc.on.doc").font(.system(size: 11))
                    Text("复制纪要（手动转发）").font(Theme.ui(12.5))
                    Spacer(minLength: 0)
                }
                .foregroundColor(Theme.inkSecondary)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
            Color.clear.frame(height: 8)
        }
        .frame(width: 280, alignment: .leading)
        .onAppear {
            query = meetingTitle
            search()
        }
    }

    private func search() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        searching = true
        Task {
            chats = await Lark.searchChats(query: q)
            searching = false
            searched = true
        }
    }
}

// MARK: - Detail todo row

struct DetailTodoRow: View {
    @EnvironmentObject var store: AppStore
    let todo: DetailTodo

    var body: some View {
        HStack(spacing: 13) {
            Avatar(initial: todo.initial, color: todo.color, size: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(todo.text).font(Theme.ui(14)).foregroundColor(Theme.inkPrimary.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
                Text(sub).font(Theme.mono(11)).foregroundColor(Theme.inkTertiary)
            }
            Spacer(minLength: 8)
            Pill(text: statusLabel, bg: statusBg, fg: statusFg, size: 11)
            actionButton
        }
        .padding(.vertical, 13)
    }

    private var sub: String {
        if todo.status == .unclaimed { return todo.note ?? "待认领" }
        return "\(todo.owner ?? "未指派") · 截止 \(todo.due)"
    }

    private var statusLabel: String {
        switch todo.status {
        case .pending:   return "待确认"
        case .unclaimed: return "待认领"
        case .confirmed: return "已建任务"
        }
    }
    private var statusBg: Color {
        switch todo.status {
        case .pending:   return Theme.warmWhite2
        case .unclaimed: return Theme.warn50
        case .confirmed: return Theme.green50
        }
    }
    private var statusFg: Color {
        switch todo.status {
        case .pending:   return Theme.inkSecondary
        case .unclaimed: return Theme.warn500
        case .confirmed: return Theme.green700
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch todo.status {
        case .unclaimed:
            button("认领", bg: Theme.warn500, fg: .white, border: nil) { store.claimDTodo(todo.id) }
        case .confirmed:
            button("已建任务 ✓", bg: Theme.white, fg: Theme.green700, border: Theme.green500) { store.confirmDTodo(todo.id) }
        case .pending:
            button("确认", bg: Theme.ink1000, fg: .white, border: nil) { store.confirmDTodo(todo.id) }
        }
    }

    private func button(_ label: String, bg: Color, fg: Color, border: Color?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(Theme.ui(12, .semibold)).foregroundColor(fg)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(bg)
                .clipShape(RoundedRectangle(cornerRadius: Theme.rSM, style: .continuous))
                .overlay {
                    if let border {
                        RoundedRectangle(cornerRadius: Theme.rSM, style: .continuous).strokeBorder(border, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}

// MARK: - Collapsible section card

struct SectionCard<Trailing: View, Content: View>: View {
    let dot: Color
    let title: String
    var count: Int? = nil
    let expanded: Bool
    let toggle: () -> Void
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    init(dot: Color, title: String, count: Int? = nil, expanded: Bool,
         toggle: @escaping () -> Void,
         @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() },
         @ViewBuilder content: @escaping () -> Content) {
        self.dot = dot
        self.title = title
        self.count = count
        self.expanded = expanded
        self.toggle = toggle
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: { withAnimation(.easeOut(duration: 0.2)) { toggle() } }) {
                HStack(spacing: 10) {
                    Dot(color: dot)
                    Text(title).font(Theme.display(18, .medium)).foregroundColor(Theme.inkPrimary)
                    if let count {
                        Text("\(count)").font(Theme.mono(12)).foregroundColor(Theme.inkTertiary)
                    }
                    Spacer()
                    trailing()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.inkTertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded { content() }
        }
        .background(Theme.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rLG, style: .continuous))
        .hairline(Theme.borderWhisper, radius: Theme.rLG)
        .whisperShadow()
    }
}
