import SwiftUI

struct HomeScreen: View {
    @EnvironmentObject var store: AppStore

    private let recent: [RecentMeeting] = [
        .init(title: "周三产品评审会", meta: "6/10 · 7人 · 6 条待办", day: "6/10",
              iconBg: Theme.accentSurface, iconFg: Theme.accentInk,
              tag: "待确认", tagBg: Theme.warn50, tagFg: Theme.warn500),
        .init(title: "技术对齐会", meta: "6/9 · 4人 · 4 条待办", day: "6/9",
              iconBg: Theme.blue50, iconFg: Theme.blue700,
              tag: "已确认", tagBg: Theme.green50, tagFg: Theme.green700),
        .init(title: "产品周例会", meta: "6/3 · 9人 · 6 条待办", day: "6/3",
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
                header.padding(.bottom, 26)
                statRow.padding(.bottom, 24)
                HStack(alignment: .top, spacing: 16) {
                    recentCard
                    todoCard.frame(width: 360)
                }
                if store.recurringCard != nil || !store.usingRealData {
                    followupBanner.padding(.top, 16)
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
            let n = store.pendingCount + store.unclaimedCount
            let latest = store.meetings.first?.title ?? ""
            if n > 0 { return "\(n) 条待办待确认。最新纪要：「\(latest)」。" }
            if !latest.isEmpty { return "待办已全部处理。最新纪要：「\(latest)」。" }
            return "暂无会议记录。开始录制，或等待飞书自动同步。"
        }
        return "有 5 条待办在等你确认，周三的评审会纪要已经备好。"
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

    // MARK: stats

    @ViewBuilder
    private var statRow: some View {
        if store.usingRealData {
            HStack(spacing: 14) {
                StatCard(label: "待确认待办", value: "\(store.openCount)",
                         sub: "\(store.unclaimedCount) 条待认领", subColor: Theme.warn500)
                StatCard(label: "闭环率", value: "\(store.closeRatePct)", unit: "%",
                         sub: "\(store.crossDone)/\(store.ctodos.count) 已完成", subColor: Theme.green500)
                StatCard(label: "已同步会议", value: "\(store.meetings.count)", sub: "已生成纪要")
                StatCard(label: "长期未动", value: "\(store.staleTodos.count)",
                         sub: store.maxOverdueDays > 0 ? "最久逾期 \(store.maxOverdueDays) 天" : "暂无逾期",
                         subColor: store.staleTodos.isEmpty ? Theme.inkTertiary : Theme.danger500)
            }
        } else {
            HStack(spacing: 14) {
                StatCard(label: "待确认待办", value: "5", sub: "2 条待认领", subColor: Theme.warn500)
                StatCard(label: "本周闭环率", value: "43", unit: "%", sub: "▲ +7% 环比", subColor: Theme.green500)
                StatCard(label: "今日会议", value: "2", sub: "1 场已生成纪要")
                StatCard(label: "长期未动", value: "5", sub: "最久 12 天未更新", subColor: Theme.danger500)
            }
        }
    }

    private var realHomeTodos: [HomeTodo] {
        store.ctodos.filter { $0.status != .done }.prefix(4).map { t in
            HomeTodo(text: t.text,
                     meta: "\(t.owner) · \(t.due == "—" ? "待认领" : t.due)",
                     dot: t.owner == "待认领" ? Theme.warn500 : Theme.blue500)
        }
    }

    // MARK: recent meetings

    private var recentCard: some View {
        Card(padding: 22) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("近期会议纪要").font(Theme.display(19, .medium)).foregroundColor(Theme.inkPrimary)
                    if store.usingRealData {
                        Pill(text: "真实数据", bg: Theme.green50, fg: Theme.green700, size: 10.5)
                    }
                    Spacer()
                    Button { store.go(.library) } label: {
                        Text("全部 \(store.meetings.count) 场 →")
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
                Text(mv.dayChip)
                    .font(Theme.mono(12, .semibold))
                    .foregroundColor(Theme.accentInk)
                    .frame(width: 38, height: 38)
                    .background(Theme.accentSurface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(mv.title)
                        .font(Theme.display(15, .medium)).foregroundColor(Theme.inkPrimary).lineLimit(1)
                    Text(mv.recentMeta).font(Theme.mono(11)).foregroundColor(Theme.inkTertiary)
                }
                Spacer()
                Pill(text: mv.badge, bg: Theme.green50, fg: Theme.green700)
            }
            .padding(.vertical, 13).padding(.horizontal, 10)
            .contentShape(Rectangle())
            if !last { Hairline() }
        }
    }

    private func recentRow(_ m: RecentMeeting, last: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Text(m.day)
                    .font(Theme.mono(12, .semibold))
                    .foregroundColor(m.iconFg)
                    .frame(width: 38, height: 38)
                    .background(m.iconBg)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous))
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
                cardHeader(title: "今日跟进", link: "待办中心 →") { store.go(.todos) }
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

    // MARK: followup banner

    private var followupBanner: some View {
        let card = store.recurringCard
        let title = card.map { "「\($0.title)」即将再次召开" }
            ?? "下周二的站会前，有一张进度追问卡待确认"
        let sub: String = {
            guard let c = card else { return "上次 6 条待办：4 完成、2 未动 —— 要不要公开点名？" }
            let done = c.items.filter { $0.done }.count
            return "上次 \(c.items.count) 条待办：\(done) 项已完成、\(c.items.count - done) 项未完成，进度汇总已就绪。"
        }()
        return Button { store.go(.followup) } label: {
            HStack(spacing: 16) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundColor(Theme.green500)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.display(15.5, .medium))
                        .foregroundColor(Theme.inkPrimary)
                        .lineLimit(1)
                    Text(sub)
                        .font(Theme.ui(12.5))
                        .foregroundColor(Theme.inkSecondary)
                }
                Spacer()
                Text("查看 →")
                    .font(Theme.ui(12.5, .semibold))
                    .foregroundColor(Theme.inkPrimary)
            }
            .padding(.horizontal, 22).padding(.vertical, 17)
            .background(Theme.warmWhite2)
            .clipShape(RoundedRectangle(cornerRadius: Theme.rLG, style: .continuous))
            .hairline(Theme.borderWhisper, radius: Theme.rLG)
        }
        .buttonStyle(.plain)
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
