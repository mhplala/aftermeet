import SwiftUI

/// 日历视图 —— 前后各 7 天的飞书日程流，和会议库交叉标注：
/// 过去的会「已有纪要」（点击进详情）/「未记录」；未来的会一键跳飞书日历。
/// 各天区块在滚动坐标系里的 minY —— 右侧刻度用它判断「现在看到哪天」
private struct DayOffsetKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

struct CalendarScreen: View {
    @EnvironmentObject var store: AppStore
    private var events: [Lark.CalEvent] { store.calEvents }
    private var loading: Bool { store.calLoading && store.calEvents.isEmpty }
    @State private var visibleDay: String = "today"
    @State private var suppressTrackingUntil = Date.distantPast   // 点击刻度的动画滚动期间别回写选中

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "M月d日 EEEE"; return f
    }()
    private static let dFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "d"; return f
    }()
    private static let wFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "EEEEE"; return f
    }()

    var body: some View {
        ScrollViewReader { proxy in
        HStack(alignment: .top, spacing: 0) {
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
                    daysList(grouped())
                }
            }
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(32)
        }
        .coordinateSpace(name: "calScroll")
        .onPreferenceChange(DayOffsetKey.self) { offsets in
            guard Date() >= suppressTrackingUntil else { return }   // 程序化滚动中，别覆盖点击的选中
            // 顶部基准线之上、离得最近的那天 = 当前在看的天
            let top: CGFloat = 140
            if let cur = offsets.filter({ $0.value <= top }).max(by: { $0.value < $1.value })?.key
                ?? offsets.min(by: { $0.value < $1.value })?.key {
                if cur != visibleDay { visibleDay = cur }
            }
        }
        dateRail(proxy, grouped())
        }
        .onAppear {
            store.loadCalendar()             // TTL 15 分钟内直接用缓存
            // 时间严格升序，打开时直接停在「今天」——往上翻过去，往下翻未来
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                proxy.scrollTo("today", anchor: .top)
            }
        }
        }
    }

    // MARK: - 右侧日期快速跳转

    private func dateRail(_ proxy: ScrollViewProxy, _ groups: [DayGroup]) -> some View {
        let df = Self.dFmt
        let wf = Self.wFmt  // 一字周几
        return VStack(spacing: 2) {
            ForEach(groups) { day in
                let date = day.events.first?.start ?? Date()
                let selected = visibleDay == day.id
                Button {
                    visibleDay = day.id
                    suppressTrackingUntil = Date().addingTimeInterval(0.45)
                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(day.id, anchor: .top) }
                } label: {
                    HStack(spacing: 6) {
                        // 刻度线：今天蓝、其余灰，选中加长加深
                        RoundedRectangle(cornerRadius: 1)
                            .fill(day.isToday ? Theme.blue500 : (selected ? Theme.inkSecondary : Theme.borderDefault))
                            .frame(width: selected ? 14 : 8, height: 2)
                        Text(day.isToday ? "今" : df.string(from: date))
                            .font(Theme.mono(10.5, selected ? .bold : .regular))
                            .foregroundColor(selected ? Theme.inkPrimary
                                             : (day.isToday ? Theme.blue700 : Theme.inkMuted))
                            .frame(width: 20, alignment: .leading)
                        Text(day.isToday ? "" : wf.string(from: date))
                            .font(Theme.mono(8.5))
                            .foregroundColor(selected ? Theme.inkTertiary : Theme.inkMuted.opacity(0.7))
                            .frame(width: 10, alignment: .leading)
                        if !day.events.isEmpty {
                            Circle().fill(Theme.blue500.opacity(selected ? 1 : 0.45))
                                .frame(width: 3.5, height: 3.5)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(height: 26)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .animation(.easeOut(duration: 0.15), value: selected)
            }
        }
        .frame(width: 74)
        .frame(maxHeight: .infinity, alignment: .center)
        .padding(.trailing, 14)
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
            Button { store.loadCalendar(force: true) } label: {
                HStack(spacing: 5) {
                    if store.calLoading { ProgressView().controlSize(.mini) }
                    else { Image(systemName: "arrow.clockwise").font(.system(size: 11)) }
                    Text("刷新").font(Theme.ui(12, .semibold))
                }
                .foregroundColor(Theme.inkSecondary)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color.white)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Theme.borderDefault, lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(store.calLoading)
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

    /// 严格时间升序：过去 → 今天 → 未来；今天没日程也插一行占位（滚动锚点）。
    private func grouped() -> [DayGroup] {
        let cal = Calendar.current
        let df = Self.dayFmt
        var map: [Date: [Lark.CalEvent]] = [:]
        for ev in events.sorted(by: { $0.start < $1.start }) {
            map[cal.startOfDay(for: ev.start), default: []].append(ev)
        }
        let todayKey = cal.startOfDay(for: Date())
        var keys = Set(map.keys); keys.insert(todayKey)
        return keys.sorted().map { day in
            let today = cal.isDateInToday(day)
            let prefix = today ? "今天 · " : (cal.isDateInYesterday(day) ? "昨天 · " : (cal.isDateInTomorrow(day) ? "明天 · " : ""))
            return DayGroup(id: today ? "today" : "\(day.timeIntervalSince1970)",
                            label: prefix + df.string(from: day),
                            isToday: today, events: map[day] ?? [])
        }
    }

    @ViewBuilder
    private func daysList(_ groups: [DayGroup]) -> some View {
        ForEach(groups) { day in
            VStack(alignment: .leading, spacing: 0) {
                dayHeader(day)
                if day.events.isEmpty {
                    Card(padding: 0) {
                        Text("今天没有日程").font(Theme.ui(13)).foregroundColor(Theme.inkTertiary)
                            .frame(maxWidth: .infinity).padding(.vertical, 24)
                    }
                    .overlay(RoundedRectangle(cornerRadius: Theme.rLG, style: .continuous)
                        .strokeBorder(Theme.blue500.opacity(0.35), lineWidth: 1.5))
                } else {
                    dayCard(day, highlight: day.isToday)
                        .opacity(day.isToday || day.events.first!.start > Date() ? 1 : 0.8)
                }
            }
            .id(day.id)
            .background(GeometryReader { geo in
                Color.clear.preference(key: DayOffsetKey.self,
                                       value: [day.id: geo.frame(in: .named("calScroll")).minY])
            })
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
                let dur = Double(store.liveDuration(id: m.id) ?? 600)
                let recStart = ts - dur, recEnd = ts
                let overlap = min(ev.end.timeIntervalSince1970, recEnd)
                    - max(ev.start.timeIntervalSince1970, recStart)
                if overlap > 300 { return .note(idx) }
            }
        }
        return ev.start > Date() ? .upcoming : .none
    }

    private func eventRow(_ ev: Lark.CalEvent, last: Bool) -> some View {
        let tf = Self.timeFmt
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

}
