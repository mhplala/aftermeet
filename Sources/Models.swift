import SwiftUI
import Combine

// MARK: - Enums

enum Screen { case home, live, history, detail, todos, followup, weekly, daily }
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

    // 已在飞书真实建卡的待办：meetingID|todoID → task guid（防重复建）。
    @Published var taskLinks: [String: String] = TaskLinkStore.load()

    var current: MeetingVM { meetings.isEmpty ? .sample : meetings[min(max(0, selectedMeeting), meetings.count - 1)] }

    private var toastWork: DispatchWorkItem?
    private var syncForward: AnyCancellable?

    init() {
        let reals = RealData.load().map { MeetingVM(real: $0) }
        let live = LiveStore.load()
            .sorted { $0.timestamp > $1.timestamp }                       // newest first
            .map { MeetingVM(live: $0.note, transcript: $0.transcript, durationSec: $0.durationSec,
                             now: Date(timeIntervalSince1970: $0.timestamp), title: $0.title) }
        let all = live + reals                                            // local captures on top, sync’d below
        usingRealData = !all.isEmpty
        meetings = all.isEmpty ? [MeetingVM.sample] : all
        dtodos = meetings[0].dtodos
        if !all.isEmpty { ctodos = AppStore.deriveCrossTodos(from: meetings) }

        // Dev affordance: `open AfterMeet.app --args -screen detail [-onboarding YES]`
        switch UserDefaults.standard.string(forKey: "screen") {
        case "live":     screen = .live
        case "history":  screen = .history
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
    }

    /// 自动同步拉到新会 → 并进列表并提示（本地捕获的仍排最上面）。
    private func mergeSynced(_ fresh: [RealMeeting]) {
        let vms = fresh.map { MeetingVM(real: $0) }
        if !usingRealData { meetings = [] }
        usingRealData = true
        let liveCount = meetings.prefix(while: { $0.id.hasPrefix("live-") }).count
        meetings.insert(contentsOf: vms, at: liveCount)
        ctodos = AppStore.deriveCrossTodos(from: meetings)
        dtodos = current.dtodos
        showToast("同步到 \(vms.count) 场新会议纪要")
    }

    func selectMeeting(_ i: Int) {
        selectedMeeting = i
        dtodos = current.dtodos
        go(.detail)
    }

    /// A live-captured transcript came back — refine it, then drop the result in as a real meeting.
    func ingestLive(transcript: String, durationSec: Int) {
        refining = true
        Task {
            do {
                let note = try await Refine.note(from: transcript)
                let userName = capture.meetingName.trimmingCharacters(in: .whitespaces)
                if userName.isEmpty { capture.setMeetingName(note.title) }   // 豆包 names the file by content
                let now = Date()
                let title = userName.isEmpty ? note.title : userName
                LiveStore.append(StoredLiveMeeting(                          // persist → survives a restart
                    id: "live-\(Int(now.timeIntervalSince1970))", title: title,
                    timestamp: now.timeIntervalSince1970, durationSec: durationSec,
                    transcript: transcript, note: note))
                let vm = MeetingVM(live: note, transcript: transcript, durationSec: durationSec,
                                   now: now, title: title)
                addLiveMeeting(vm)
                refining = false
                showToast("已生成会中纪要：\(vm.title)")
            } catch {
                refining = false
                showToast("提炼失败：\(error.localizedDescription)")
            }
        }
    }

    func addLiveMeeting(_ vm: MeetingVM) {
        if !usingRealData { meetings = [] }          // drop the sample fallback once real content exists
        usingRealData = true
        meetings.insert(vm, at: 0)
        ctodos = AppStore.deriveCrossTodos(from: meetings)
        selectedMeeting = 0
        dtodos = vm.dtodos
        go(.detail)
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
        if on && meetingActive && !capture.isCapturing {     // already mid-meeting → start now
            go(.live)
            Task { await capture.start() }
        }
    }

    private func handleMeeting(_ active: Bool) {
        meetingActive = active
        if active {
            if autoStart && !capture.isCapturing {
                go(.live)
                Task { await capture.start() }
            }
        } else if capture.isCapturing {
            Task {
                let text = await capture.stop()
                if text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 4 {
                    ingestLive(transcript: text, durationSec: capture.elapsed)
                }
            }
        }
    }

    /// Start (→ live) or stop (→ refine & ingest) capture — shared by LiveScreen and the menu-bar item.
    func toggleCapture() {
        if capture.isCapturing {
            Task {
                let text = await capture.stop()
                if text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 4 {
                    ingestLive(transcript: text, durationSec: capture.elapsed)
                }
            }
        } else {
            go(.live)
            Task { await capture.start() }
        }
    }

    // MARK: - 每日综述

    /// Meetings grouped by day (dayChip), newest day first — preserves the meetings-array order.
    var meetingsByDay: [(day: String, items: [MeetingVM])] {
        var order: [String] = []
        var map: [String: [MeetingVM]] = [:]
        for m in meetings where m.dayChip != "·" {
            if map[m.dayChip] == nil { order.append(m.dayChip) }
            map[m.dayChip, default: []].append(m)
        }
        return order.map { (day: $0, items: map[$0] ?? []) }
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

    // navigation
    func go(_ s: Screen) { withAnimation(.easeOut(duration: 0.18)) { screen = s } }

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
            showToast("正在把 \(pending.count) 条待办落成飞书任务…")
        } else {
            showToast("\(pending.count) 条待办已确认（演示数据，未建真实任务）")
        }
    }

    /// 真·建飞书任务。负责人姓名只认精确唯一匹配（宁可不指派不可派错）；
    /// 已建过的（task-links 台账里有）不重复建。
    private func createLarkTask(for todo: DetailTodo, assignToSelf: Bool, quiet: Bool = false) {
        guard usingRealData else {
            if !quiet { showToast("已确认（演示数据，未建真实任务）") }
            return
        }
        guard Lark.available else {
            if !quiet { showToast("未找到 lark-cli，任务只记在本地") }
            return
        }
        let key = linkKey(todo.id)
        guard taskLinks[key] == nil else {
            if !quiet { showToast("这条已建过飞书任务") }
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
                if assignee == nil { note = "（没找到「\(owner)」的唯一飞书账号，任务未指派）" }
            }
            do {
                let created = try await Lark.createTask(
                    summary: todo.text,
                    description: "来自会议「\(meetingTitle)」 · AfterMeet 会后秘书"
                        + (owner.map { " · 负责人：\($0)" } ?? ""),
                    due: todo.due == "—" ? nil : todo.due,
                    assigneeOpenID: assignee)
                taskLinks[key] = created.guid
                TaskLinkStore.save(taskLinks)
                if !quiet {
                    showToast(assignToSelf ? "已认领并建飞书任务，负责人记为你"
                                           : "飞书任务已建：\(todo.text.prefix(14))…\(note)")
                } else if !note.isEmpty {
                    showToast(note)
                }
            } catch {
                showToast("建飞书任务失败：\(error.localizedDescription)")
            }
        }
    }

    // cross-meeting todos
    func toggleCtodo(_ id: Int) {
        guard let i = ctodos.firstIndex(where: { $0.id == id }) else { return }
        if ctodos[i].status == .done {
            ctodos[i].status = ctodos[i].wasBeforeDone ?? .doing
        } else {
            ctodos[i].wasBeforeDone = ctodos[i].status
            ctodos[i].status = .done
        }
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
            showToast("接入完成 · 秘书已开始监听")
        } else {
            withAnimation(.easeOut(duration: 0.2)) { obStep += 1 }
        }
    }

    func obSkip() {
        showOnboarding = false
        obStep = 0
    }

    /// Flatten every meeting's refined todos into the cross-meeting list (real-data mode).
    /// 截止日期已过、还没勾掉的 → 逾期（真实计算，不是摆设）。
    static func deriveCrossTodos(from meetings: [MeetingVM]) -> [CrossTodo] {
        var out: [CrossTodo] = []
        var id = 1
        for mv in meetings {
            for t in mv.dtodos {
                let label = mv.dayChip == "·" ? mv.title : "\(mv.title) · \(mv.dayChip)"
                let done = t.status == .confirmed
                let status: CrossStatus = done ? .done
                    : (Self.overdueDays(due: t.due) ?? 0) > 0 ? .overdue : .doing
                out.append(CrossTodo(id: id, text: t.text, meeting: label,
                                     owner: t.owner ?? "待认领", initial: t.initial, color: t.color,
                                     due: t.due, status: status))
                id += 1
            }
        }
        return out
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
    var staleTodos: [CrossTodo] {
        ctodos.filter { $0.status != .done && (Self.overdueDays(due: $0.due) ?? 0) > 3 }
    }
    var maxOverdueDays: Int {
        ctodos.filter { $0.status != .done }
            .compactMap { Self.overdueDays(due: $0.due) }.filter { $0 > 0 }.max() ?? 0
    }

    // MARK: - 手动同步（菜单栏 / 铃铛里点）

    func syncNow() {
        guard Lark.available else { showToast("未找到 lark-cli，装好并登录后才能同步飞书会议"); return }
        guard !sync.syncing else { return }
        showToast("正在扫最近 14 天的飞书会议…")
        Task {
            let before = meetings.count
            await sync.sync()
            if meetings.count == before { showToast("没有新会议（已有 \(before) 场）") }
        }
    }

    // MARK: - 会前追问（真实模式）：同名会议开过 ≥2 次 → 用上一场的待办生成对比卡

    struct RecurringCard {
        let title: String
        let prevMeta: String
        let items: [FollowItem]
    }

    var recurringCard: RecurringCard? {
        guard usingRealData else { return nil }
        var byTitle: [String: [MeetingVM]] = [:]
        for m in meetings { byTitle[m.title, default: []].append(m) }   // meetings 已按新→旧
        guard let (title, group) = byTitle.first(where: { $0.value.count >= 2 }) else { return nil }
        let prev = group[1]                                             // 上一场
        let items = prev.dtodos.enumerated().map { idx, t in
            let done = ctodos.contains {
                $0.text == t.text && $0.meeting.hasPrefix(prev.title) && $0.status == .done
            }
            return FollowItem(id: idx + 1, text: t.text, owner: t.owner ?? "待认领", done: done)
        }
        guard !items.isEmpty else { return nil }
        return RecurringCard(title: title, prevMeta: "\(prev.recentMeta)", items: items)
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
                                 text: "「\(current.title)」还有待办要处理",
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
                                 meta: "完成后自动打开", screen: .live))
        }
        if sync.syncing {
            out.append(NotifItem(icon: "arrow.triangle.2.circlepath", text: "正在同步飞书会议…",
                                 meta: "扫最近 14 天", screen: .home))
        }
        return out
    }

    // MARK: - 搜索（⌘K）

    struct SearchHit: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let meta: String
        let action: SearchAction
    }
    enum SearchAction { case meeting(Int); case todos }

    func search(_ raw: String) -> [SearchHit] {
        let q = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard q.count >= 1 else { return [] }
        var out: [SearchHit] = []
        for (idx, m) in meetings.enumerated() {
            let hay = "\(m.title) \(m.summary) \(m.rawTranscript)".lowercased()
            if hay.contains(q) {
                out.append(SearchHit(icon: "doc.text", title: m.title,
                                     meta: m.recentMeta, action: .meeting(idx)))
            }
        }
        let todoHits = ctodos.filter {
            $0.text.lowercased().contains(q) || $0.owner.lowercased().contains(q)
        }
        for t in todoHits.prefix(5) {
            out.append(SearchHit(icon: "checklist", title: t.text,
                                 meta: "\(t.owner) · \(t.meeting)", action: .todos))
        }
        return Array(out.prefix(8))
    }

    func open(_ hit: SearchHit) {
        switch hit.action {
        case .meeting(let idx): selectMeeting(idx)
        case .todos:            go(.todos)
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
                    showToast("差一步：终端跑 lark-cli auth login 补 im 发送权限")
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
        lines.append("—— AfterMeet 会后秘书 · 会前盘点")
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
        lines.append("—— AfterMeet 会后秘书")
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
            return "还有 \(pendingCount) 条待确认"
                + (unclaimedCount > 0 ? "、\(unclaimedCount) 条待认领" : "")
        }
        if unclaimedCount > 0 { return "\(unclaimedCount) 条待认领，认领后建任务" }
        return "全部待办已确认"
    }
}
