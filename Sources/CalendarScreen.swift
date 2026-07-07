import SwiftUI

/// 日历视图 —— 前后各 7 天的飞书日程流，和会议库交叉标注：
/// 过去的会「已有纪要」（点击进详情）/「未记录」；未来的会一键跳飞书日历。
struct CalendarScreen: View {
    @EnvironmentObject var store: AppStore
    @State private var events: [Lark.CalEvent] = []
    @State private var loading = true

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header
                if loading {
                    Card(padding: 0) {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("正在读取飞书日历…").font(Theme.ui(13)).foregroundColor(Theme.inkTertiary)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 36)
                    }
                    .padding(.top, 18)
                } else if events.isEmpty {
                    Card(padding: 0) {
                        EmptyState(icon: "calendar", title: "没有读到日程",
                                   message: "确认 lark-cli 已登录，且日历权限已授权。")
                    }
                    .padding(.top, 18)
                } else {
                    daysList
                }
            }
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(32)
        }
        .task { await load() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 0) {
                Overline("前后 7 天 · 飞书日程 × 会议纪要", tracking: 1.2).padding(.bottom, 8)
                Text("日历")
                    .font(Theme.display(36, .semibold)).tracking(-0.8)
                    .foregroundColor(Theme.inkPrimary)
            }
            Spacer()
            Button { Lark.openCalendar(at: Date()) } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.forward.app").font(.system(size: 11))
                    Text("打开飞书日历").font(Theme.ui(12, .semibold))
                }
                .foregroundColor(Theme.inkPrimary.opacity(0.85))
                .padding(.horizontal, 13).padding(.vertical, 7)
                .background(Color.white)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Theme.borderDefault, lineWidth: 1))
                .contentShape(Capsule())
            }.buttonStyle(.plain)
        }
    }

    // MARK: - 按天分组

    private struct DayGroup: Identifiable {
        let id: String
        let label: String
        let isToday: Bool
        let events: [Lark.CalEvent]
    }

    /// 今天在最前，然后是未来（升序）；过去 7 天弱化收尾（降序，最近的在前）。
    private func grouped() -> (today: DayGroup?, future: [DayGroup], past: [DayGroup]) {
        let cal = Calendar.current
        let df = DateFormatter(); df.locale = Locale(identifier: "zh_CN"); df.dateFormat = "M月d日 EEEE"
        var map: [Date: [Lark.CalEvent]] = [:]
        for ev in events.sorted(by: { $0.start < $1.start }) {
            map[cal.startOfDay(for: ev.start), default: []].append(ev)
        }
        let todayKey = cal.startOfDay(for: Date())
        func group(_ day: Date) -> DayGroup {
            let today = cal.isDateInToday(day)
            let prefix = today ? "今天 · " : (cal.isDateInYesterday(day) ? "昨天 · " : (cal.isDateInTomorrow(day) ? "明天 · " : ""))
            return DayGroup(id: "\(day.timeIntervalSince1970)", label: prefix + df.string(from: day),
                            isToday: today, events: map[day] ?? [])
        }
        let today = map[todayKey] != nil ? group(todayKey) : nil
        let future = map.keys.filter { $0 > todayKey }.sorted().map(group)
        let past = map.keys.filter { $0 < todayKey }.sorted(by: >).map(group)
        return (today, future, past)
    }

    @ViewBuilder
    private var daysList: some View {
        let g = grouped()

        if let today = g.today {
            dayHeader(today)
            dayCard(today, highlight: true)
        } else {
            dayHeader(DayGroup(id: "today-empty", label: "今天", isToday: true, events: []))
            Card(padding: 0) {
                Text("今天没有日程").font(Theme.ui(13)).foregroundColor(Theme.inkTertiary)
                    .frame(maxWidth: .infinity).padding(.vertical, 26)
            }
        }

        ForEach(g.future) { day in
            dayHeader(day)
            dayCard(day, highlight: false)
        }

        if !g.past.isEmpty {
            Text("过去 7 天")
                .font(Theme.mono(10, .semibold)).tracking(1.0).textCase(.uppercase)
                .foregroundColor(Theme.inkMuted)
                .padding(.top, 26).padding(.bottom, 2)
            ForEach(g.past) { day in
                dayHeader(day)
                dayCard(day, highlight: false).opacity(0.75)
            }
        }
    }

    private func dayHeader(_ day: DayGroup) -> some View {
        HStack(spacing: 7) {
            Text(day.label)
                .font(Theme.mono(11, .semibold))
                .foregroundColor(day.isToday ? Theme.blue700 : Theme.inkPrimary)
            if day.isToday { Circle().fill(Theme.blue500).frame(width: 5, height: 5) }
            if !day.events.isEmpty {
                Text("\(day.events.count) 场").font(Theme.mono(10.5)).foregroundColor(Theme.inkTertiary)
            }
        }
        .padding(.top, 18).padding(.bottom, 8)
    }

    private func dayCard(_ day: DayGroup, highlight: Bool) -> some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(day.events.enumerated()), id: \.offset) { idx, ev in
                    eventRow(ev, last: idx == day.events.count - 1)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 3)
        }
        .overlay {
            if highlight {
                RoundedRectangle(cornerRadius: Theme.rLG, style: .continuous)
                    .strokeBorder(Theme.blue500.opacity(0.35), lineWidth: 1.5)
            }
        }
    }

    // MARK: - 事件行 + 纪要交叉标注

    fileprivate enum Link {
        case note(Int); case upcoming; case none
        var isNote: Bool { if case .note = self { return true }; return false }
    }

    /// 日程 ↔ 会议库：标题同系列，或本地录音区间与日程重叠。
    private func link(for ev: Lark.CalEvent) -> Link {
        let evNorm = AppStore.normalizedTitle(ev.summary)
        for (idx, m) in store.meetings.enumerated() {
            if AppStore.sameSeries(evNorm, AppStore.normalizedTitle(m.title)) { return .note(idx) }
            if m.id.hasPrefix("live-"), let ts = Double(m.id.dropFirst(5)) {
                let dur = Double(600)
                let recStart = ts - dur, recEnd = ts
                let overlap = min(ev.end.timeIntervalSince1970, recEnd)
                    - max(ev.start.timeIntervalSince1970, recStart)
                if overlap > 300 { return .note(idx) }
            }
        }
        return ev.start > Date() ? .upcoming : .none
    }

    private func eventRow(_ ev: Lark.CalEvent, last: Bool) -> some View {
        let tf = DateFormatter(); tf.dateFormat = "HH:mm"
        let kind = link(for: ev)
        return VStack(spacing: 0) {
            Button {
                switch kind {
                case .note(let idx): store.selectMeeting(idx)
                case .upcoming, .none: Lark.openCalendar(at: ev.start)
                }
            } label: {
                HStack(spacing: 13) {
                    Text("\(tf.string(from: ev.start))–\(tf.string(from: ev.end))")
                        .font(Theme.mono(11)).foregroundColor(Theme.inkTertiary)
                        .frame(width: 88, alignment: .leading)
                    Text(ev.summary)
                        .font(Theme.ui(13.5, .medium)).foregroundColor(Theme.inkPrimary)
                        .lineLimit(1)
                    Spacer()
                    if ev.start <= Date() && Date() < ev.end {
                        Pill(text: "进行中", bg: Theme.danger50, fg: Theme.danger500, size: 10.5)
                    }
                    switch kind {
                    case .note:
                        Pill(text: "已有纪要", bg: Theme.green50, fg: Theme.green700, size: 10.5)
                    case .upcoming:
                        Pill(text: "未开始", bg: Theme.blue50, fg: Theme.blue700, size: 10.5)
                    case .none:
                        Pill(text: "未记录", bg: Theme.warmWhite2, fg: Theme.inkTertiary, size: 10.5)
                    }
                    Image(systemName: kind.isNote ? "chevron.right" : "arrow.up.forward")
                        .font(.system(size: 10, weight: .semibold)).foregroundColor(Theme.inkMuted)
                }
                .padding(.vertical, 11).padding(.horizontal, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if !last { Hairline() }
        }
    }

    private func load() async {
        events = await Lark.events(from: Date().addingTimeInterval(-7 * 86400),
                                   to: Date().addingTimeInterval(7 * 86400))
        loading = false
    }
}
