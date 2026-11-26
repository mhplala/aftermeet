import SwiftUI

struct HomeScreen: View {
    @EnvironmentObject var store: AppStore

    private let recent: [RecentMeeting] = [
        .init(title: "周三产品评审会", meta: "6/10", day: "6/10",
              iconBg: Theme.accentSurface, iconFg: Theme.accentInk,
              tag: "待确认", tagBg: Theme.warn50, tagFg: Theme.warn500),
        .init(title: "技术对齐会", meta: "6/9", day: "6/9",
              iconBg: Theme.blue50, iconFg: Theme.blue700,
              tag: "已确认", tagBg: Theme.green50, tagFg: Theme.green700),
        .init(title: "产品周例会", meta: "6/3", day: "6/3",
              iconBg: Theme.warmWhite2, iconFg: Theme.inkSecondary,
              tag: "已闭环 4/6", tagBg: Theme.warmWhite2, tagFg: Theme.inkSecondary),
    ]

    private let todos: [HomeTodo] = [
        .init(text: "完成纪要卡片折叠态前端联调", meta: "周岚 · 逾期 1 天", dot: Theme.danger500),
        .init(text: "给出待办确认率基线埋点方案", meta: "王凯 · 今天截止", dot: Theme.warn500),
        .init(text: "拟定 3 个团队的灰度沟通话术", meta: "待认领 · 需指派", dot: Theme.warn500),
        .init(text: "待办 → 飞书任务字段 open_id 兜底", meta: "高翔 · 6/16", dot: Theme.blue500),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header.padding(.bottom, 24)
                dailyDigestCard.padding(.bottom, 16)
                HStack(alignment: .top, spacing: 16) {
                    recentCard
                    todoCard.frame(width: 360)
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: header

    private var todayOverline: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "M月d日 · EEEE"
        return f.string(from: Date())
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12:  return "早上好，"
        case 12..<14: return "中午好，"
        case 14..<18: return "下午好，"
        default:      return "晚上好，"
        }
    }

    private var subtitle: String {
        if store.usingRealData {
            let n = store.candidateCount
            let latest = store.meetings.first?.title ?? ""
            if n > 0 { return "有新的行动项待确认。最新纪要：「\(latest)」。" }
            if !latest.isEmpty { return "最新纪要：「\(latest)」。" }
            return "暂无会议记录。开始录制，或等待飞书自动同步。"
        }
        return "有新的行动项待确认，周三的评审会纪要已经备好。"
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                Overline(todayOverline, tracking: 1.2).padding(.bottom, 8)
                (Text(store.userName.isEmpty ? String(greeting.dropLast()) : greeting)
                    .foregroundColor(Theme.inkPrimary)
                    + Text(store.userName).foregroundColor(Theme.accent)
                    + Text("。").foregroundColor(Theme.inkPrimary))
                    .font(Theme.display(42, .medium))
                    .tracking(-1)
                Text(subtitle)
                    .font(Theme.display(16, .regular))
                    .foregroundColor(Theme.inkSecondary)
                    .padding(.top, 10)
            }
            Spacer()
            Button {
                if store.usingRealData { store.selectMeeting(0) } else { store.syncNow() }
            } label: {
                Text(store.usingRealData ? "查看最新纪要" : "立即同步飞书")
                    .font(Theme.ui(13, .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 17).padding(.vertical, 9)
                    .background(Theme.inkGrad)
                    .clipShape(Capsule())
                    .glow(Theme.ink1000, radius: 10, opacity: 0.25)
            }
            .buttonStyle(.plain)
        }
    }

    private var realHomeTodos: [HomeTodo] {
        let ordered = store.ctodos.filter { $0.status == .candidate }
            + store.officialTodos.filter { $0.status != .done }
        return ordered.prefix(4).map { t in
            let meta = t.status == .candidate
                ? "待确认"
                : [t.owner == "待认领" ? nil : t.owner, t.due == "—" ? nil : t.due]
                    .compactMap { $0 }.joined(separator: " · ")
            return HomeTodo(text: t.text,
                            meta: meta.isEmpty ? "进行中" : meta,
                            dot: t.status == .candidate ? Theme.warn500 : Theme.blue500)
        }
    }

    // MARK: daily digest

    private var latestDigestDay: (day: String, items: [MeetingVM])? {
        store.meetingsByDay.first
    }

    private var dailyDigestPreview: String {
        guard let latest = latestDigestDay else {
            return "有会议后，这里会把当天的进展、结论和待关注事项汇总到一起。"
        }
        if store.dailyGenerating.contains(latest.day) {
            return "正在汇总当天的 (latest.items.count) 场会议…"
        }
        if let blocks = store.dailyBlocks[latest.day] {
            if let text = blocks.first(where: { $0.type == "summary" })?.text,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
            if let item = blocks.compactMap({ $0.items?.first }).first {
                return item.components(separatedBy: "|").last ?? item
            }
        }
        return "汇总当天所有会议里的整体进展、关键结论和待关注事项。"
    }

    private var dailyDigestCard: some View {
        Button { store.go(.daily) } label: {
            HStack(spacing: 16) {
                Image(systemName: "sun.max")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(Theme.accentInk)
                    .frame(width: 42, height: 42)
                    .background(Theme.accentSurface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("每日总结")
                            .font(Theme.display(17, .medium))
                            .foregroundColor(Theme.inkPrimary)
                        if let latest = latestDigestDay {
                            Text("\(latest.day) · \(latest.items.count) 场会议")
                                .font(Theme.mono(10.5))
                                .foregroundColor(Theme.inkTertiary)
                        }
                    }
                    Text(dailyDigestPreview)
                        .font(Theme.ui(12.5))
                        .foregroundColor(Theme.inkSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 16)
                Text(store.dailyBlocks[latestDigestDay?.day ?? ""] == nil ? "生成总结 →" : "查看总结 →")
                    .font(Theme.ui(12.5, .medium))
                    .foregroundColor(Theme.blue500)
            }
            .padding(.horizontal, 18).padding(.vertical, 15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.white)
            .clipShape(RoundedRectangle(cornerRadius: Theme.rLG, style: .continuous))
            .hairline(Theme.borderWhisper, radius: Theme.rLG)
            .whisperShadow()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: recent meetings

    private var recentCard: some View {
        Card(padding: 22) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("近期会议纪要").font(Theme.display(19, .medium)).foregroundColor(Theme.inkPrimary)
                    if !store.usingRealData {
                        Pill(text: "示例数据", bg: Theme.warmWhite2, fg: Theme.inkTertiary, size: 10.5)
                    }
                    Spacer()
                    Button { store.go(.library) } label: {
                        Text("查看全部 →")
                            .font(Theme.ui(12.5)).foregroundColor(Theme.blue500)
                            .padding(.vertical, 6).padding(.leading, 14)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                .padding(.bottom, 16)

                if store.usingRealData {
                    let shown = Array(store.meetings.prefix(5))
                    ForEach(Array(shown.enumerated()), id: \.element.id) { idx, mv in
                        Button { store.selectMeeting(idx) } label: {
                            realRow(mv, last: idx == shown.count - 1)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { idx, m in
                        Button { store.selectMeeting(0) } label: {
                            recentRow(m, last: idx == recent.count - 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func realRow(_ mv: MeetingVM, last: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(mv.title)
                        .font(Theme.display(15, .medium)).foregroundColor(Theme.inkPrimary).lineLimit(1)
                    Text(mv.recentMeta).font(Theme.mono(11)).foregroundColor(Theme.inkTertiary)
                }
                Spacer()
            }
            .padding(.vertical, 13).padding(.horizontal, 10)
            .contentShape(Rectangle())
            if !last { Hairline() }
        }
    }

    private func recentRow(_ m: RecentMeeting, last: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(m.title)
                        .font(Theme.display(15, .medium))
                        .foregroundColor(Theme.inkPrimary)
                    Text(m.meta)
                        .font(Theme.mono(11))
                        .foregroundColor(Theme.inkTertiary)
                }
                Spacer()
                Pill(text: m.tag, bg: m.tagBg, fg: m.tagFg)
            }
            .padding(.vertical, 13)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
            if !last { Hairline() }
        }
    }

    // MARK: today's todos

    private var todoCard: some View {
        Card(padding: 22) {
            VStack(alignment: .leading, spacing: 0) {
                cardHeader(title: "需要处理", link: "行动项 →") { store.go(.todos) }
                    .padding(.bottom, 16)
                let list = store.usingRealData ? realHomeTodos : todos
                ForEach(Array(list.enumerated()), id: \.element.id) { idx, t in
                    VStack(spacing: 0) {
                        HStack(alignment: .top, spacing: 10) {
                            Circle().fill(t.dot).frame(width: 7, height: 7).padding(.top, 6)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(t.text)
                                    .font(Theme.ui(13))
                                    .foregroundColor(Theme.inkPrimary.opacity(0.92))
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(t.meta)
                                    .font(Theme.mono(10.5))
                                    .foregroundColor(Theme.inkTertiary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 11)
                        if idx != list.count - 1 { Hairline() }
                    }
                }
            }
        }
    }

    // MARK: shared card header

    private func cardHeader(title: String, link: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Theme.display(19, .medium))
                .foregroundColor(Theme.inkPrimary)
            Spacer()
            Button(action: action) {
                Text(link).font(Theme.ui(12.5)).foregroundColor(Theme.blue500)
                    .padding(.vertical, 6).padding(.leading, 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
