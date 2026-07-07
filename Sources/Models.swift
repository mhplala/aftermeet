import SwiftUI
import Combine

// MARK: - Enums

enum Screen { case home, library, calendar, detail, todos, followup, weekly, daily, settings }
enum TodoFilter { case all, open, overdue, done }
enum DetailStatus { case pending, unclaimed, confirmed }
enum CrossStatus { case overdue, doing, done }

// MARK: - Data types

struct DetailTodo: Identifiable {
    let id: Int
    var owner: String?
    var initial: String
    var color: Color
    let text: String
    let due: String
    var status: DetailStatus
    let orig: DetailStatus
    var note: String? = nil

    static let sample: [DetailTodo] = [
        .init(id: 1, owner: "周岚", initial: "周", color: Color(hex: "0075de"),
              text: "完成纪要卡片折叠态前端联调", due: "6/13", status: .pending, orig: .pending),
        .init(id: 2, owner: "高翔", initial: "高", color: Color(hex: "1f7a4c"),
              text: "待办 → 飞书任务字段映射，补充 open_id 兜底", due: "6/16", status: .pending, orig: .pending),
        .init(id: 3, owner: nil, initial: "?", color: Color(hex: "a86a1a"),
              text: "拟定 3 个团队的灰度沟通话术", due: "—", status: .unclaimed, orig: .unclaimed,
              note: "置信度低 · 未识别明确负责人"),
        .init(id: 4, owner: "王凯", initial: "王", color: Color(hex: "d06a3a"),
              text: "给出待办确认率基线埋点方案", due: "6/14", status: .pending, orig: .pending),
        .init(id: 5, owner: "陈默", initial: "陈", color: Color(hex: "6c5c7a"),
              text: "进度追问卡公开转发预览态视觉", due: "6/15", status: .confirmed, orig: .confirmed),
        .init(id: 6, owner: nil, initial: "?", color: Color(hex: "a86a1a"),
              text: "待认领场景的回归测试用例", due: "—", status: .unclaimed, orig: .unclaimed,
              note: "置信度低 · 未识别明确负责人"),
    ]
}

struct CrossTodo: Identifiable {
    let id: Int
    let text: String
    let meeting: String
    let owner: String
    let initial: String
    let color: Color
    let due: String
    var status: CrossStatus
    var wasBeforeDone: CrossStatus? = nil
    var key: String = ""            // meetingID|todoID —— 完成态的持久键（样例数据为空）

    static let sample: [CrossTodo] = [
        .init(id: 1, text: "完成纪要卡片折叠态前端联调", meeting: "周三产品评审会 · 6/10",
              owner: "周岚", initial: "周", color: Color(hex: "0075de"), due: "6/13", status: .overdue),
        .init(id: 2, text: "待办 → 飞书任务字段映射补充 open_id 兜底", meeting: "周三产品评审会 · 6/10",
              owner: "高翔", initial: "高", color: Color(hex: "1f7a4c"), due: "6/16", status: .doing),
        .init(id: 3, text: "给出待办确认率基线埋点方案", meeting: "周三产品评审会 · 6/10",
              owner: "王凯", initial: "王", color: Color(hex: "d06a3a"), due: "6/14", status: .doing),
        .init(id: 4, text: "灰度首周用户访谈提纲", meeting: "产品周例会 · 6/3",
              owner: "苏萌", initial: "苏", color: Color(hex: "1f7a4c"), due: "6/9", status: .overdue),
        .init(id: 5, text: "siku-proxy 提炼 schema 联调", meeting: "技术对齐会 · 6/9",
              owner: "高翔", initial: "高", color: Color(hex: "1f7a4c"), due: "6/12", status: .done),
        .init(id: 6, text: "机器人欢迎卡文案终稿", meeting: "内容评审 · 6/5",
              owner: "我", initial: "林", color: Color(hex: "1f7a4c"), due: "6/11", status: .done),
        .init(id: 7, text: "周报形态二选一，产出对比方案", meeting: "产品周例会 · 6/3",
              owner: "王凯", initial: "王", color: Color(hex: "d06a3a"), due: "6/13", status: .doing),
        .init(id: 8, text: "会议台账多维表格字段设计", meeting: "技术对齐会 · 6/9",
              owner: "周岚", initial: "周", color: Color(hex: "0075de"), due: "6/17", status: .doing),
    ]
}

struct FollowItem: Identifiable {
    let id: Int
    let text: String
    let owner: String
    var done: Bool

    static let sample: [FollowItem] = [
        .init(id: 1, text: "灰度首周用户访谈提纲", owner: "苏萌", done: false),
        .init(id: 2, text: "机器人欢迎卡文案终稿", owner: "林涛", done: true),
        .init(id: 3, text: "siku-proxy 提炼链路打通", owner: "高翔", done: true),
        .init(id: 4, text: "周报形态二选一对比方案", owner: "王凯", done: false),
        .init(id: 5, text: "多维表格台账字段设计", owner: "周岚", done: true),
        .init(id: 6, text: "Onboarding 授权流程评审", owner: "陈默", done: true),
    ]
}

// Static display-only sample content.

struct RecentMeeting: Identifiable {
    let id = UUID()
    let title: String
    let meta: String
    let day: String
    let iconBg: Color
    let iconFg: Color
    let tag: String
    let tagBg: Color
    let tagFg: Color
}

struct HomeTodo: Identifiable {
    let id = UUID()
    let text: String
    let meta: String
    let dot: Color
}

struct Decision: Identifiable {
    let id = UUID()
    let no: String
    let text: String
}

struct Dispute: Identifiable {
    let id = UUID()
    let title: String
    let body: String
}

struct TranscriptLine: Identifiable {
    let id = UUID()
    let time: String
    let who: String
    let text: String
}

struct Procrastinator: Identifiable {
    let id = UUID()
    let rank: String
    let text: String
    let owner: String
    let days: String
}

// MARK: - App store

@MainActor
final class AppStore: ObservableObject {
    @Published var screen: Screen = .home
    @Published var showOnboarding = false
    @Published var obStep = 0

    @Published var secDecisions = true
    @Published var secInsights = true
    @Published var secTodos = true
    @Published var secDisputes = true
    @Published var secTranscript = false

    @Published var dtodos: [DetailTodo] = DetailTodo.sample
    @Published var ctodos: [CrossTodo] = CrossTodo.sample
    @Published var fitems: [FollowItem] = FollowItem.sample
    @Published var filter: TodoFilter = .all
    @Published var toast: String? = nil

    /// Real meetings — synced from Feishu (sync.sh) or captured live — else the sample fallback.
    @Published var meetings: [MeetingVM]
    @Published var usingRealData: Bool
    @Published var selectedMeeting = 0
    @Published var refining = false

    // 每日综述 — cached per-day digest of all that day's meetings.
    @Published var dailyBlocks: [String: [NoteBlock]] = DailyStore.load()
    @Published var dailyGenerating: Set<String> = []
    @Published var dailyDay = ""                 // 放 store 里：跳走再返回不丢选中的天

    // 会议库 tab（纪要 / 原始转写），同样跨跳转保留
    @Published var libraryRawTab = false

    // start/stop 幂等门：多入口（面板/菜单栏/自动检测）并发触发时只放行一次
    private var startInFlight = false
    private var stopInFlight = false

    // 录制条（顶栏常驻）：面板开合 + 刚生成完的纪要（完成态，点击才跳）
    @Published var showRecPanel = false
    @Published var freshLiveID: String? = nil

    // 搜索跳到待办中心时闪一下目标行
    @Published var flashTodoText: String? = nil

    // 本地录制会议的时长（秒），启动加载时缓存 —— 日历比对不再读盘
    private var liveDurations: [String: Int] = [:]

    // 派生缓存：重活（正则/日期解析/分组）只在数据变化时算一次，不在 body 里跑
    @Published private(set) var recurringCardsCache: [RecurringCard] = []
    @Published private(set) var meetingsByDayCache: [(day: String, items: [MeetingVM])] = []
    @Published private(set) var staleTodosCache: [CrossTodo] = []
    @Published private(set) var maxOverdueDaysCache = 0

    // 时间戳 × 日历猜出来的改名建议：meetingID → 日历日程名
    @Published var calendarSuggestions: [String: String] = [:]
    private var calendarChecked = Set<String>()

    // 纪要问答 — per-meeting Q&A grounded in its transcript.
    @Published var qaThreads: [String: [QATurn]] = QAStore.load()
    @Published var qaPending: Set<String> = []

    // Live capture engine (app-wide, so auto-detect can start it from any screen).
    let capture = CaptureService()
    let watcher = MeetingWatcher()
    @Published var meetingActive = false
    @Published var autoStart = UserDefaults.standard.bool(forKey: "autoStart")
    private var watching = false

    // 会后自动同步（轮询飞书，替代手动 sync.sh）。
    let sync = FeishuSync()

    // 当前用户（问候语 / 认领任务用），启动时从 lark-cli 拉一次。
    @Published var userName = ""
    var userInitial: String { String(userName.prefix(1)) }

    // 已在飞书真实建卡的待办：meetingID|todoID → task guid（防重复建；同时是"已确认"的持久真源）。
    @Published var taskLinks: [String: String] = TaskLinkStore.load()

    // 待办中心手动勾掉的完成态（meetingID|todoID），持久化 —— 重新派生列表时不清零。
    @Published var doneTodoKeys: Set<String> = {
        guard let s = DB.shared.kvGet("done_todos"),
              let arr = try? JSONDecoder().decode([String].self, from: Data(s.utf8)) else { return [] }
        return Set(arr)
    }()
    private func saveDoneKeys() {
        if let d = try? JSONEncoder().encode(Array(doneTodoKeys)), let s = String(data: d, encoding: .utf8) {
            DB.shared.kvSet("done_todos", s)
        }
    }

    /// 详情页待办叠加持久确认态（selectMeeting 拷贝出来的 dtodos 不再"切走即失忆"）。
    private func applyConfirmations(_ todos: [DetailTodo], meetingID: String) -> [DetailTodo] {
        todos.map { t in
            var t = t
            if taskLinks["\(meetingID)|\(t.id)"] != nil { t.status = .confirmed }
            return t
        }
    }

    /// meetings/持久态变化后重建两份派生列表。
    func rederiveTodos() {
        ctodos = deriveCrossTodosApplied()
        dtodos = applyConfirmations(current.dtodos, meetingID: current.id)
    }

    private func deriveCrossTodosApplied() -> [CrossTodo] {
        var out: [CrossTodo] = []
        var id = 1
        for mv in meetings {
            for t in applyConfirmations(mv.dtodos, meetingID: mv.id) {
                let key = "\(mv.id)|\(t.id)"
                let label = mv.dayChip == "·" ? mv.title : "\(mv.title) · \(mv.dayChip)"
                let done = t.status == .confirmed || doneTodoKeys.contains(key)
                let status: CrossStatus = done ? .done
                    : (Self.overdueDays(due: t.due) ?? 0) > 0 ? .overdue : .doing
                out.append(CrossTodo(id: id, text: t.text, meeting: label,
                                     owner: t.owner ?? "待认领", initial: t.initial, color: t.color,
                                     due: t.due, status: status, key: key))
                id += 1
            }
        }
        return out
    }

    var current: MeetingVM { meetings.isEmpty ? .sample : meetings[min(max(0, selectedMeeting), meetings.count - 1)] }

    private var toastWork: DispatchWorkItem?
    private var flashWork: DispatchWorkItem?
    private var syncForward: AnyCancellable?

    init() {
        let reals = RealData.load().map { MeetingVM(real: $0) }
        let stored = LiveStore.load()
        liveDurations = Dictionary(uniqueKeysWithValues: stored.map { ($0.id, $0.durationSec) })
        let live = stored
            .sorted { $0.timestamp > $1.timestamp }                       // newest first
            .map { MeetingVM(live: $0.note, transcript: $0.transcript, durationSec: $0.durationSec,
                             now: Date(timeIntervalSince1970: $0.timestamp), title: $0.title) }
        let all = live + reals                                            // local captures on top, sync’d below
        usingRealData = !all.isEmpty
        meetings = all.isEmpty ? [MeetingVM.sample] : all
        dtodos = meetings[0].dtodos
        if !all.isEmpty { rederiveTodos() }

        // Dev affordance: `open AfterMeet.app --args -screen detail [-onboarding YES]`
        switch UserDefaults.standard.string(forKey: "screen") {
        case "library":  screen = .library
        case "calendar": screen = .calendar
        case "settings": screen = .settings
        case "detail":   screen = .detail
        case "todos":    screen = .todos
        case "followup": screen = .followup
        case "weekly":   screen = .weekly
        case "daily":    screen = .daily
        default:         break
        }
        if UserDefaults.standard.bool(forKey: "onboarding") { showOnboarding = true }

        Task { if let me = await Lark.me() { self.userName = me.name } }
        sync.onNewMeetings = { [weak self] fresh in self?.mergeSynced(fresh) }
        // FeishuSync 是嵌套 ObservableObject，把它的变化转发出去，侧栏状态卡才会刷新
        syncForward = sync.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        sync.start()
        buildArchiveIndex()      // 转写档案全文进搜索
        calEvents = CalCache.load()   // 上次的日历先顶上（秒开），随后后台刷新
        loadCalendar()
        refreshDerived()
    }

    /// 自动同步拉到新会 → 并进列表并提示（本地捕获的仍排最上面）。
    private func mergeSynced(_ fresh: [RealMeeting]) {
        let vms = fresh.map { MeetingVM(real: $0) }
        if !usingRealData { meetings = [] }
        usingRealData = true
        let liveCount = meetings.prefix(while: { $0.id.hasPrefix("live-") }).count
        meetings.insert(contentsOf: vms, at: liveCount)
        if selectedMeeting >= liveCount { selectedMeeting += vms.count }   // 正在看的那场别被顶换
        rederiveTodos()
        refreshDerived()
        showToast("已同步 \(vms.count) 场新会议")
    }

    func selectMeeting(_ i: Int) {
        selectedMeeting = i
        dtodos = applyConfirmations(current.dtodos, meetingID: current.id)
        go(.detail)
    }

    /// A live-captured transcript came back — refine it, then drop the result in as a real meeting.
    func ingestLive(transcript: String, durationSec: Int) {
        refining = true
        let stopped = Date()                       // 停录时刻（提炼要几十秒，别把时间戳推迟）
        Task {
            do {
                let note = try await Refine.note(from: transcript)
                let userName = capture.meetingName.trimmingCharacters(in: .whitespaces)
                if userName.isEmpty { capture.setMeetingName(note.title) }   // 豆包 names the file by content
                let now = stopped
                let title = userName.isEmpty ? note.title : userName
                let storedID = "live-\(Int(now.timeIntervalSince1970))"
                let persisted = LiveStore.append(StoredLiveMeeting(          // persist → survives a restart
                    id: storedID, title: title,
                    timestamp: now.timeIntervalSince1970, durationSec: durationSec,
                    transcript: transcript, note: note))
                if !persisted { showToast("纪要写入数据库失败，已导出救援文件到数据目录") }
                liveDurations[storedID] = durationSec
                let vm = MeetingVM(live: note, transcript: transcript, durationSec: durationSec,
                                   now: now, title: title)
                addLiveMeeting(vm)
                refining = false
                freshLiveID = vm.id            // 录制条转完成态，用户点了才跳，不抢页面
                showToast("纪要已生成:\(vm.title)")
            } catch {
                refining = false
                showToast("提炼失败：\(error.localizedDescription)")
            }
        }
    }

    func addLiveMeeting(_ vm: MeetingVM) {
        if !usingRealData { meetings = [] }          // drop the sample fallback once real content exists
        usingRealData = true
        let wasEmpty = meetings.isEmpty
        meetings.insert(vm, at: 0)
        if wasEmpty { selectedMeeting = 0 } else { selectedMeeting += 1 }   // 保持用户正看的那场不被顶掉
        rederiveTodos()
        refreshDerived()
    }

    // MARK: - Auto meeting detection

    func startWatching() {
        guard !watching else { return }
        watching = true
        capture.requestAuth()
        watcher.onChange = { [weak self] active in self?.handleMeeting(active) }
        watcher.start()
    }

    func setAutoStart(_ on: Bool) {
        autoStart = on
        UserDefaults.standard.set(on, forKey: "autoStart")
        if on && meetingActive { beginCapture(openPanel: false) }   // already mid-meeting → start now
    }

    private func handleMeeting(_ active: Bool) {
        meetingActive = active
        if active {
            if autoStart { beginCapture(openPanel: false) }
        } else {
            endCapture()
        }
    }

    /// Start (→ panel) or stop (→ refine & ingest) — shared by the rec strip, panel, and menu bar.
    func toggleCapture() {
        if capture.isCapturing { endCapture() } else { beginCapture(openPanel: true) }
    }

    /// 幂等 start：面板按钮 / 菜单栏 / 自动检测同拍触发也只起一条流。
    private func beginCapture(openPanel: Bool) {
        guard !capture.isCapturing, !startInFlight, !stopInFlight else { return }
        startInFlight = true
        freshLiveID = nil            // 上一场的"纪要已生成"完成态让位给新录制
        if openPanel { showRecPanel = true }
        Task {
            await capture.start()
            startInFlight = false
        }
    }

    /// 幂等 stop：stop() 从按下到收尾有数秒窗口，第二次触发直接吞掉（防双份提炼/重复纪要）。
    private func endCapture() {
        guard capture.isCapturing, !stopInFlight else { return }
        stopInFlight = true
        Task {
            let text = await capture.stop()
            stopInFlight = false
            if text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 4 {
                ingestLive(transcript: text, durationSec: capture.elapsed)
            }
        }
    }

    // MARK: - 每日综述

    var meetingsByDay: [(day: String, items: [MeetingVM])] { meetingsByDayCache }

    /// 数据变化后重算全部派生缓存（分组 / 追问卡 / 逾期统计）。
    func refreshDerived() {
        var order: [String] = []
        var map: [String: [MeetingVM]] = [:]
        for m in meetings where m.dayChip != "·" {
            if map[m.dayChip] == nil { order.append(m.dayChip) }
            map[m.dayChip, default: []].append(m)
        }
        meetingsByDayCache = order.map { (day: $0, items: map[$0] ?? []) }

        staleTodosCache = ctodos.filter { $0.status != .done && (Self.overdueDays(due: $0.due) ?? 0) > 3 }
        maxOverdueDaysCache = ctodos.filter { $0.status != .done }
            .compactMap { Self.overdueDays(due: $0.due) }.filter { $0 > 0 }.max() ?? 0

        recurringCardsCache = computeRecurringCards()
    }

    /// Generate (or reuse cached) the day's digest by synthesizing all its meetings via 豆包.
    func generateDigest(day: String, force: Bool = false) {
        if dailyGenerating.contains(day) { return }
        if !force, dailyBlocks[day] != nil { return }
        let items = meetingsByDay.first { $0.day == day }?.items ?? []
        guard !items.isEmpty else { return }
        dailyGenerating.insert(day)
        let input = "「\(day)」这一天共 \(items.count) 场会，各会要点如下：\n\n"
            + items.map { AppStore.condensed($0) }.joined(separator: "\n\n———\n\n")
        Task {
            do {
                let note = try await Refine.digest(from: input)
                dailyBlocks[day] = note.blocks ?? []
                DailyStore.save(dailyBlocks)
            } catch {
                showToast("当日综述生成失败：\(error.localizedDescription)")
            }
            dailyGenerating.remove(day)
        }
    }

    /// Condense one meeting to its high-signal lines for the daily-rollup input.
    static func condensed(_ m: MeetingVM) -> String {
        var parts = ["《\(m.title)》"]
        for b in m.displayBlocks {
            switch b.type {
            case "summary":   if let t = b.text, !t.isEmpty { parts.append("摘要：" + t) }
            case "decisions": if let it = b.items, !it.isEmpty { parts.append("决策：" + it.joined(separator: "；")) }
            case "keyPoints": if let it = b.items, !it.isEmpty { parts.append("要点：" + it.joined(separator: "；")) }
            case "disputes":  if let it = b.items, !it.isEmpty { parts.append("分歧：" + it.joined(separator: "；")) }
            default: break
            }
        }
        return parts.joined(separator: "\n")
    }

    /// Ask a question about the currently-open meeting; 豆包 answers from its transcript.
    func askCurrentMeeting(_ raw: String) {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = current.id
        guard !q.isEmpty, !qaPending.contains(id) else { return }
        let transcript = current.rawTranscript
        qaThreads[id, default: []].append(QATurn(question: q, answer: nil))
        qaPending.insert(id)
        QAStore.save(qaThreads)
        Task {
            let answer: String
            do { answer = try await Refine.ask(transcript: transcript, question: q) }
            catch { answer = "回答失败：\(error.localizedDescription)" }
            if var t = qaThreads[id], let i = t.lastIndex(where: { $0.answer == nil }) {
                t[i].answer = answer
                qaThreads[id] = t
                QAStore.save(qaThreads)
            }
            qaPending.remove(id)
        }
    }

    // MARK: - navigation（带历史栈：返回永远回「你来的地方」）

    private var backStack: [Screen] = []
    var canGoBack: Bool { !backStack.isEmpty }

    func go(_ s: Screen) {
        guard s != screen else { return }
        backStack.append(screen)
        if backStack.count > 30 { backStack.removeFirst() }
        withAnimation(.easeOut(duration: 0.18)) { screen = s }
    }

    func goBack() {
        guard let prev = backStack.popLast() else { return }
        withAnimation(.easeOut(duration: 0.18)) { screen = prev }
    }

    // 详情页 ‹ › ：时间序上一场/下一场，到头禁用（不循环）
    var canPrevMeeting: Bool { selectedMeeting > 0 }
    var canNextMeeting: Bool { selectedMeeting < meetings.count - 1 }
    var meetingPos: String { "\(selectedMeeting + 1) / \(meetings.count)" }

    func stepMeeting(_ delta: Int) {
        let i = selectedMeeting + delta
        guard meetings.indices.contains(i) else { return }
        selectedMeeting = i
        dtodos = applyConfirmations(current.dtodos, meetingID: current.id)
    }

    // MARK: - 时间戳 × 日历：猜这段录音属于哪场会，给改名建议

    /// 泛泛标题（模型没起好名）→ 日历命中时直接自动改名，否则只挂建议。
    static func isGenericTitle(_ t: String) -> Bool {
        t.isEmpty || t == "未命名会议" || t == "会中纪要"
            || t.hasPrefix("简体中文") || t.hasPrefix("会议") || t.count <= 4
    }

    func checkCalendarName(for m: MeetingVM) {
        guard m.id.hasPrefix("live-"), !calendarChecked.contains(m.id), Lark.available else { return }
        calendarChecked.insert(m.id)
        guard let ts = Double(m.id.dropFirst("live-".count)) else { return }
        Task {
            let dur = liveDurations[m.id] ?? 600
            // 存的时间戳是停录时刻 → 录音区间是 [ts - 时长, ts]
            let recStart = Date(timeIntervalSince1970: ts - Double(dur))
            let candidates = await Lark.eventsOverlapping(start: recStart, durationSec: dur)
            guard let ev = candidates.first else { return }
            let evNorm = AppStore.normalizedTitle(ev.summary)
            let curNorm = AppStore.normalizedTitle(m.title)
            guard !AppStore.sameSeries(evNorm, curNorm) else { return }   // 名字已经对上，不打扰
            if candidates.count == 1 || AppStore.isGenericTitle(m.title) {
                // 该时段日历里只有这一场（或现名本来就是占位）→ 直接改，不打扰用户
                renameMeeting(id: m.id, to: ev.summary)
                showToast("已按日历改名：\(ev.summary)")
            } else {
                calendarSuggestions[m.id] = ev.summary   // 同时段多场会 → 给建议，用户拍板
            }
        }
    }

    func adoptCalendarName(id: String) {
        guard let name = calendarSuggestions[id] else { return }
        renameMeeting(id: id, to: name)
        calendarSuggestions[id] = nil
        showToast("已改名：\(name)")
    }

    func renameMeeting(id: String, to title: String) {
        guard let i = meetings.firstIndex(where: { $0.id == id }) else { return }
        meetings[i].title = title
        LiveStore.rename(id: id, title: title)
        rederiveTodos()                                      // 待办里的会议标签同步
        refreshDerived()
    }

    func liveDuration(id: String) -> Int? { liveDurations[id] }

    /// 录制条完成态被点击 → 打开刚生成的纪要
    func openFreshLive() {
        guard let id = freshLiveID else { return }
        freshLiveID = nil
        if let idx = meetings.firstIndex(where: { $0.id == id }) { selectMeeting(idx) }
    }

    func showToast(_ message: String) {
        toast = message
        toastWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.easeOut(duration: 0.2)) { self?.toast = nil }
        }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6, execute: work)
    }

    // detail todos —— 确认/认领即真实回写飞书任务（样例数据只演示，不建真卡）。

    private func linkKey(_ todoID: Int) -> String { "\(current.id)|\(todoID)" }

    func confirmDTodo(_ id: Int) {
        guard let i = dtodos.firstIndex(where: { $0.id == id }) else { return }
        if dtodos[i].status == .confirmed {          // 撤回只改本地状态；已建的飞书任务保留
            dtodos[i].status = dtodos[i].orig
            return
        }
        dtodos[i].status = .confirmed
        createLarkTask(for: dtodos[i], assignToSelf: false)
    }

    func claimDTodo(_ id: Int) {
        guard let i = dtodos.firstIndex(where: { $0.id == id }) else { return }
        dtodos[i].status = .confirmed
        dtodos[i].owner = userName.isEmpty ? "我" : userName
        dtodos[i].initial = userName.isEmpty ? "我" : userInitial
        dtodos[i].color = Theme.green500
        createLarkTask(for: dtodos[i], assignToSelf: true)
    }

    func confirmAll() {
        let pending = dtodos.filter { $0.status == .pending }
        guard !pending.isEmpty else { return }
        for i in dtodos.indices where dtodos[i].status == .pending {
            dtodos[i].status = .confirmed
        }
        for t in pending { createLarkTask(for: t, assignToSelf: false, quiet: true) }
        if usingRealData && Lark.available {
            showToast("正在创建 \(pending.count) 个飞书任务…")
        } else {
            showToast("已确认 \(pending.count) 条（示例数据，未创建真实任务）")
        }
    }

    /// 真·建飞书任务。负责人姓名只认精确唯一匹配（宁可不指派不可派错）；
    /// 已建过的（task-links 台账里有）不重复建。
    private func createLarkTask(for todo: DetailTodo, assignToSelf: Bool, quiet: Bool = false) {
        guard usingRealData else {
            if !quiet { showToast("已确认（示例数据，未创建真实任务）") }
            return
        }
        guard Lark.available else {
            if !quiet { showToast("未检测到 lark-cli，任务仅保存在本地") }
            return
        }
        let key = linkKey(todo.id)
        guard taskLinks[key] == nil else {
            if !quiet { showToast("该待办已创建过飞书任务") }
            return
        }
        let meetingTitle = current.title
        let owner = todo.owner
        Task {
            var assignee: String? = nil
            var note = ""
            if assignToSelf {
                assignee = (await Lark.me())?.openID
            } else if let owner, !owner.isEmpty {
                assignee = await Lark.resolveOpenID(name: owner)
                if assignee == nil { note = "（未匹配到「\(owner)」的唯一飞书账号，任务未指派）" }
            }
            do {
                let created = try await Lark.createTask(
                    summary: todo.text,
                    description: "来自会议「\(meetingTitle)」 · Aftermeet"
                        + (owner.map { " · 负责人：\($0)" } ?? ""),
                    due: todo.due == "—" ? nil : todo.due,
                    assigneeOpenID: assignee)
                taskLinks[key] = created.guid
                TaskLinkStore.save(taskLinks)
                rederiveTodos()
                refreshDerived()
                if !quiet {
                    showToast(assignToSelf ? "已认领，飞书任务已创建"
                                           : "飞书任务已创建：\(todo.text.prefix(14))…\(note)")
                } else if !note.isEmpty {
                    showToast(note)
                }
            } catch {
                showToast("创建飞书任务失败：\(error.localizedDescription)")
            }
        }
    }

    // cross-meeting todos
    func toggleCtodo(_ id: Int) {
        guard let i = ctodos.firstIndex(where: { $0.id == id }) else { return }
        let key = ctodos[i].key
        if ctodos[i].status == .done {
            ctodos[i].status = (Self.overdueDays(due: ctodos[i].due) ?? 0) > 0 ? .overdue : .doing
            if !key.isEmpty { doneTodoKeys.remove(key) }
        } else {
            ctodos[i].status = .done
            if !key.isEmpty { doneTodoKeys.insert(key) }
        }
        saveDoneKeys()
        refreshDerived()
    }

    func toggleFitem(_ id: Int) {
        guard let i = fitems.firstIndex(where: { $0.id == id }) else { return }
        fitems[i].done.toggle()
    }

    // onboarding
    func obNext() {
        if obStep >= 3 {
            showOnboarding = false
            obStep = 0
            showToast("设置完成，自动记录已开启")
        } else {
            withAnimation(.easeOut(duration: 0.2)) { obStep += 1 }
        }
    }

    func obSkip() {
        showOnboarding = false
        obStep = 0
    }

    /// "6/13" 距今逾期几天；解析不了（"—"、"Q3"）返回 nil。
    static func overdueDays(due: String) -> Int? {
        let nums = due.components(separatedBy: CharacterSet(charactersIn: "/-月日 "))
            .compactMap { Int($0) }
        guard nums.count >= 2, (1...12).contains(nums[0]), (1...31).contains(nums[1]) else { return nil }
        let cal = Calendar.current
        var comp = cal.dateComponents([.year], from: Date())
        comp.month = nums[0]; comp.day = nums[1]
        guard var d = cal.date(from: comp) else { return nil }
        // 半年以上的"未来逾期"多半是去年的日期（1 月看 12 月的 due）
        if d.timeIntervalSinceNow > 180 * 86400 { d = cal.date(byAdding: .year, value: -1, to: d)! }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: d),
                                      to: cal.startOfDay(for: Date())).day ?? 0
        return days
    }

    /// 长期未动：逾期超过 3 天还没闭环的待办（真数据模式的指标卡用）。
    var staleTodos: [CrossTodo] { staleTodosCache }
    var maxOverdueDays: Int { maxOverdueDaysCache }

    // MARK: - 手动同步（菜单栏 / 铃铛里点）

    func syncNow() {
        guard Lark.available else { showToast("未检测到 lark-cli，安装并登录后即可同步飞书会议"); return }
        guard !sync.syncing else { return }
        showToast("正在同步最近 14 天的飞书会议…")
        Task {
            let before = meetings.count
            await sync.sync()
            if meetings.count == before { showToast("没有发现新会议") }
        }
    }

    // MARK: - 会前追问（真实模式）：同系列会议再次出现 → 用上一场的待办生成对比卡

    struct RecurringCard {
        let title: String                  // 系列名（日历日程名或上一场标题）
        let prevTitle: String              // 上一场会议的标题（勾选进度按它匹配跨会待办）
        let prevMeta: String
        let items: [FollowItem]
        var upcomingLabel: String? = nil   // 日历里下一场的时间（交叉比对命中时有值）
        var upcomingDate: Date? = nil      // 点击跳飞书日历用
    }

    // 日历缓存：前后 7 天日程，TTL 15 分钟 + 落盘（页面秒开，不每次都打 CLI）
    @Published var calEvents: [Lark.CalEvent] = []
    @Published var calLoading = false
    private var calFetchedAt: Date? = nil
    var upcomingEvents: [Lark.UpcomingEvent] {
        let out = DateFormatter(); out.locale = Locale(identifier: "zh_CN"); out.dateFormat = "M月d日 EEE HH:mm"
        var seen = Set<String>()
        return calEvents.filter { $0.start > Date() }.sorted { $0.start < $1.start }.compactMap { ev in
            guard !seen.contains(ev.summary) else { return nil }
            seen.insert(ev.summary)
            return Lark.UpcomingEvent(summary: ev.summary, dateLabel: out.string(from: ev.start), start: ev.start)
        }
    }

    func loadCalendar(force: Bool = false) {
        if !force, let t = calFetchedAt, Date().timeIntervalSince(t) < 15 * 60 { return }
        guard !calLoading, Lark.available else { return }
        calLoading = true
        Task {
            let events = await Lark.events(from: Date().addingTimeInterval(-7 * 86400),
                                           to: Date().addingTimeInterval(7 * 86400))
            if !events.isEmpty || force {
                calEvents = events
                CalCache.save(events)
            }
            calFetchedAt = Date()
            calLoading = false
            refreshDerived()
        }
    }

    /// 标题规范化：标题是模型按内容起的，同系列两场会几乎不会逐字相同 ——
    /// 去掉日期/期数/「会议纪要」类后缀后再比较，才追得上。
    private static let normLock = NSLock()
    nonisolated(unsafe) private static var normCache: [String: String] = [:]

    static func normalizedTitle(_ t: String) -> String {
        normLock.lock()
        if let hit = normCache[t] { normLock.unlock(); return hit }
        normLock.unlock()
        var s = t.lowercased()
        s = s.replacingOccurrences(of: #"[（(]第?[0-9一二三四五六七八九十xX]+[周期次]?[)）]"#,
                                   with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\d{1,2}[月/]\d{1,2}日?"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[qQ][1-4]"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"vol\.?\s*\d+"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"第?\d+[期次轮]"#, with: "", options: .regularExpression)
        for suffix in ["会议纪要", "研讨会议", "沟通会议", "对齐会议", "同步会议", "评审会议",
                       "复盘会议", "规划会议", "讨论会", "研讨会", "同步会", "评审会",
                       "复盘会", "规划会", "分享会", "周会", "例会", "会议", "纪要", "会"] {
            if s.hasSuffix(suffix) { s = String(s.dropLast(suffix.count)); break }
        }
        let out = s.filter { !$0.isWhitespace && !"·-—:：()（）&/".contains($0) }
        normLock.lock()
        if normCache.count > 2048 { normCache.removeAll() }   // 防无界增长
        normCache[t] = out
        normLock.unlock()
        return out
    }

    /// 同一系列：规范化后相等 / 一方包含另一方 / 共同前缀足够长且占短标题 70% 以上。
    /// （旧版「前缀 ≥8」会把 Live Studio 开头的两个不同会误判成一个系列）
    static func sameSeries(_ a: String, _ b: String) -> Bool {
        guard a.count >= 4, b.count >= 4 else { return false }
        if a == b { return true }
        if a.contains(b) || b.contains(a) { return true }
        let common = zip(a, b).prefix { $0 == $1 }.count
        return common >= 12 && Double(common) >= 0.7 * Double(min(a.count, b.count))
    }

    var recurringCards: [RecurringCard] { recurringCardsCache }
    var recurringCard: RecurringCard? { recurringCardsCache.first }

    /// 一天可能有多场周期会议：日历未来 7 天逐个交叉比对，全部命中都出卡（按开始时间排序）。
    private func computeRecurringCards() -> [RecurringCard] {
        guard usingRealData else { return [] }
        let normed = meetings.map { AppStore.normalizedTitle($0.title) }   // meetings 已按新→旧
        var cards: [RecurringCard] = []
        var usedSeries = Set<String>()

        for ev in upcomingEvents {                                          // 已按时间升序
            let evNorm = AppStore.normalizedTitle(ev.summary)
            guard !usedSeries.contains(evNorm),
                  let j = meetings.indices.first(where: { AppStore.sameSeries(evNorm, normed[$0]) })
            else { continue }
            let prev = meetings[j]
            let items = followItems(from: prev)
            guard !items.isEmpty else { continue }
            usedSeries.insert(evNorm)
            cards.append(RecurringCard(title: ev.summary, prevTitle: prev.title, prevMeta: prev.recentMeta,
                                       items: items, upcomingLabel: ev.dateLabel, upcomingDate: ev.start))
            if cards.count >= 5 { break }
        }
        if !cards.isEmpty { return cards }

        // 兜底：库内两场同系列（严格匹配），只出一张
        for i in meetings.indices {
            guard let j = meetings.indices.first(where: { $0 > i && AppStore.sameSeries(normed[i], normed[$0]) })
            else { continue }
            let items = followItems(from: meetings[j])
            guard !items.isEmpty else { continue }
            return [RecurringCard(title: meetings[i].title, prevTitle: meetings[j].title,
                                  prevMeta: meetings[j].recentMeta, items: items)]
        }
        return []
    }

    private func followItems(from prev: MeetingVM) -> [FollowItem] {
        prev.dtodos.enumerated().map { idx, t in
            let done = ctodos.contains {
                $0.text == t.text && $0.meeting.hasPrefix(prev.title) && $0.status == .done
            }
            return FollowItem(id: idx + 1, text: t.text, owner: t.owner ?? "待认领", done: done)
        }
    }

    // MARK: - 铃铛：需要你处理的事

    struct NotifItem: Identifiable {
        let id = UUID()
        let icon: String
        let text: String
        let meta: String
        let screen: Screen
    }

    var notifications: [NotifItem] {
        var out: [NotifItem] = []
        if pendingCount + unclaimedCount > 0 {
            out.append(NotifItem(icon: "checklist",
                                 text: "「\(current.title)」有待处理的待办",
                                 meta: confirmHint, screen: .detail))
        }
        let overdue = ctodos.filter { $0.status == .overdue }
        if !overdue.isEmpty {
            out.append(NotifItem(icon: "exclamationmark.circle",
                                 text: "\(overdue.count) 条待办已逾期",
                                 meta: overdue.prefix(2).map { $0.owner }.joined(separator: "、") + " 等人",
                                 screen: .todos))
        }
        if refining {
            out.append(NotifItem(icon: "wand.and.stars", text: "正在提炼会中纪要…",
                                 meta: "完成后可在顶栏查看", screen: .home))
        }
        if sync.syncing {
            out.append(NotifItem(icon: "arrow.triangle.2.circlepath", text: "正在同步飞书会议…",
                                 meta: "范围：最近 14 天", screen: .home))
        }
        return out
    }

    // MARK: - 搜索（⌘K）—— 多关键词 AND、字段加权排序、命中摘录，覆盖会议/待办/转写档案

    enum SearchKind: String { case meeting = "会议", todo = "待办", archive = "转写档案" }

    struct SearchHit: Identifiable {
        let id = UUID()
        let kind: SearchKind
        let icon: String
        let title: String
        let meta: String
        let snippet: AttributedString?
        let action: SearchAction
        let score: Int
    }
    enum SearchAction { case meeting(Int); case todos; case archive(String) }

    /// 转写档案索引（标题 + 全文小写），启动后台建好；搜索时只做 contains
    struct ArchiveEntry { let title: String; let body: String; let lcBody: String }
    private(set) var archiveIndex: [ArchiveEntry] = []
    @Published var archiveTargetTitle: String? = nil   // 搜索命中档案 → 会议库原始转写 tab 直接打开这条

    func buildArchiveIndex() {
        Task.detached(priority: .utility) {
            let files = TranscriptArchiveView.loadFiles()
            let entries = files.map { ArchiveEntry(title: $0.title, body: $0.body, lcBody: $0.body.lowercased()) }
            await MainActor.run { self.archiveIndex = entries }
        }
    }

    func search(_ raw: String) -> [SearchHit] {
        let tokens = raw.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return [] }
        var out: [SearchHit] = []

        // —— 会议：候选集来自 SQLite FTS5（≥3 字走 trigram 索引，短词 LIKE），
        //    打分与摘录用内存原文（标题 100 / 摘要 40 / 逐字稿 12 + 新近度）
        let idIndex = Dictionary(uniqueKeysWithValues: meetings.enumerated().map { ($1.id, $0) })
        let candidateIDs = usingRealData ? DB.shared.searchMeetings(tokens: tokens)
                                         : meetings.map { $0.id }      // 演示数据不在库里，全量内存匹配
        for id in candidateIDs {
            guard let idx = idIndex[id] else { continue }
            let m = meetings[idx]
            let lcTitle = m.title.lowercased()
            let lcSummary = m.summary.lowercased()
            let lcBody = m.rawTranscript.lowercased()
            var score = 0
            var ok = true
            for t in tokens {
                if lcTitle.contains(t) { score += 100 }
                else if lcSummary.contains(t) { score += 40 }
                else if lcBody.contains(t) { score += 12 }
                else { ok = false; break }
            }
            guard ok else { continue }
            score += max(0, 20 - idx)                                 // 越新越靠前
            let snippet: AttributedString? = {
                if tokens.contains(where: { lcSummary.contains($0) }) {
                    return AppStore.snippet(in: m.summary, tokens: tokens)
                }
                if !m.rawTranscript.isEmpty, tokens.contains(where: { lcBody.contains($0) }) {
                    return AppStore.snippet(in: m.rawTranscript, tokens: tokens)
                }
                return nil
            }()
            out.append(SearchHit(kind: .meeting, icon: "doc.text", title: m.title,
                                 meta: m.recentMeta, snippet: snippet,
                                 action: .meeting(idx), score: score))
        }

        // —— 待办：内容 / 负责人 / 所属会议
        for t in ctodos {
            let hay = "\(t.text) \(t.owner) \(t.meeting)".lowercased()
            guard tokens.allSatisfy({ hay.contains($0) }) else { continue }
            let overdue = t.status == .overdue ? " · 已逾期" : ""
            out.append(SearchHit(kind: .todo, icon: "checklist", title: t.text,
                                 meta: "\(t.owner) · \(t.meeting)\(overdue)", snippet: nil,
                                 action: .todos, score: 60))
        }

        // —— 转写档案：全文命中（会议纪要之外的原始记录也能搜到）
        for e in archiveIndex {
            let lcTitle = e.title.lowercased()
            guard tokens.allSatisfy({ lcTitle.contains($0) || e.lcBody.contains($0) }) else { continue }
            out.append(SearchHit(kind: .archive, icon: "waveform", title: e.title,
                                 meta: "\(e.body.count) 字 · 本地存档",
                                 snippet: AppStore.snippet(in: e.body, tokens: tokens),
                                 action: .archive(e.title), score: 30))
        }

        // 排序 + 每组限量（会议 6 / 待办 4 / 档案 3）
        var counts: [SearchKind: Int] = [:]
        let caps: [SearchKind: Int] = [.meeting: 6, .todo: 4, .archive: 3]
        return out.sorted { $0.score > $1.score }.filter { h in
            counts[h.kind, default: 0] += 1
            return counts[h.kind]! <= caps[h.kind]!
        }
    }

    /// 第一个命中词前后各 ~28 字的上下文，命中词加粗。
    /// 索引永远只在同一个串上（caseInsensitive 搜原串）—— lowercased() 会改变某些字符的
    /// 长度（İ/ẞ 等），拿小写串的 Range 去切原串会越界崩溃。
    static func snippet(in text: String, tokens: [String]) -> AttributedString? {
        guard let token = tokens.first(where: {
            text.range(of: $0, options: .caseInsensitive) != nil
        }), let r = text.range(of: token, options: .caseInsensitive) else { return nil }
        let start = text.index(r.lowerBound, offsetBy: -28, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(r.upperBound, offsetBy: 28, limitedBy: text.endIndex) ?? text.endIndex
        var window = String(text[start..<end]).replacingOccurrences(of: "\n", with: " ")
        if start > text.startIndex { window = "…" + window }
        if end < text.endIndex { window += "…" }
        var attr = AttributedString(window)
        for t in tokens {
            var searchFrom = window.startIndex
            while let hit = window.range(of: t, options: .caseInsensitive,
                                         range: searchFrom..<window.endIndex) {
                if let lo = AttributedString.Index(hit.lowerBound, within: attr),
                   let hi = AttributedString.Index(hit.upperBound, within: attr) {
                    attr[lo..<hi].font = .system(size: 11.5, weight: .bold)
                    attr[lo..<hi].foregroundColor = Theme.inkPrimary
                }
                searchFrom = hit.upperBound
            }
        }
        return attr
    }

    func open(_ hit: SearchHit) {
        switch hit.action {
        case .meeting(let idx):
            selectMeeting(idx)
        case .todos:
            flashTodoText = hit.title            // 落点行闪一下，2 秒后熄
            go(.todos)
            flashWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.flashTodoText = nil }
            flashWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
        case .archive(let title):
            archiveTargetTitle = title
            libraryRawTab = true
            go(.library)
        }
    }

    // MARK: - 转发到群（真发 · 缺 scope 时给出授权指引）

    func forward(to chat: Lark.Chat) {
        send(markdown: AppStore.noteMarkdown(current), to: chat, what: "纪要")
    }

    func send(markdown: String, to chat: Lark.Chat, what: String) {
        showToast("正在发到「\(chat.name)」…")
        Task {
            do {
                try await Lark.sendMarkdown(chatID: chat.id, markdown: markdown)
                showToast("\(what)已发到「\(chat.name)」")
            } catch {
                if Lark.isMissingScope(error) {
                    showToast("需要授权：请在终端运行 lark-cli auth login 开通消息发送权限")
                } else {
                    showToast("发送失败：\(error.localizedDescription)")
                }
            }
        }
    }

    /// 会前追问卡的 markdown（发群用）。
    static func followupMarkdown(_ card: RecurringCard) -> String {
        let done = card.items.filter { $0.done }
        let open = card.items.filter { !$0.done }
        var lines = ["**「\(card.title)」上次待办进度** （\(card.prevMeta)）", ""]
        lines.append("已完成 \(done.count) · 未动 \(open.count)")
        lines.append("")
        for i in card.items {
            lines.append("- \(i.done ? "✅" : "⏳") \(i.text)（\(i.owner)）")
        }
        lines.append("")
        lines.append("—— Aftermeet · 会前盘点")
        return lines.joined(separator: "\n")
    }

    /// 追问卡上勾选：把对应的跨会议待办翻转（按文本匹配上一场会的那条）。
    func toggleFollowItem(text: String, meetingTitle: String) {
        if let i = ctodos.firstIndex(where: { $0.text == text && $0.meeting.hasPrefix(meetingTitle) }) {
            toggleCtodo(ctodos[i].id)
        }
    }

    /// 把当前纪要排成飞书 markdown。
    static func noteMarkdown(_ m: MeetingVM) -> String {
        var lines = ["**\(m.title)**", ""]
        for b in m.displayBlocks {
            switch b.type {
            case "summary":
                if let t = b.text { lines.append(t); lines.append("") }
            case "decisions":
                if let it = b.items, !it.isEmpty {
                    lines.append("**结论与决策**")
                    lines += it.map { "- " + $0.replacingOccurrences(of: "|", with: " ") }
                    lines.append("")
                }
            case "keyPoints":
                if let it = b.items, !it.isEmpty {
                    lines.append("**要点**")
                    lines += it.map { "- \($0)" }
                    lines.append("")
                }
            case "disputes":
                if let it = b.items, !it.isEmpty {
                    lines.append("**分歧与未决**")
                    lines += it.map { "- " + $0.replacingOccurrences(of: "|", with: "：") }
                    lines.append("")
                }
            default: break
            }
        }
        let todos = m.dtodos
        if !todos.isEmpty {
            lines.append("**待办**")
            lines += todos.map { "- \($0.text)（\($0.owner ?? "待认领")\($0.due == "—" ? "" : " · \($0.due)")）" }
        }
        lines.append("")
        lines.append("—— Aftermeet")
        return lines.joined(separator: "\n")
    }

    // derived
    var openCount: Int { ctodos.filter { $0.status != .done }.count }
    var crossDone: Int { ctodos.filter { $0.status == .done }.count }
    var closeRatePct: Int { ctodos.isEmpty ? 0 : Int((Double(crossDone) / Double(ctodos.count) * 100).rounded()) }
    var pendingCount: Int { dtodos.filter { $0.status == .pending }.count }
    var unclaimedCount: Int { dtodos.filter { $0.status == .unclaimed }.count }

    var confirmHint: String {
        if pendingCount > 0 {
            return "\(pendingCount) 条待确认"
                + (unclaimedCount > 0 ? " · \(unclaimedCount) 条待认领" : "")
        }
        if unclaimedCount > 0 { return "\(unclaimedCount) 条待认领" }
        return "待办已全部确认"
    }
}
