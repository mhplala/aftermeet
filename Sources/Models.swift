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

    var current: MeetingVM { meetings.isEmpty ? .sample : meetings[min(max(0, selectedMeeting), meetings.count - 1)] }

    private var toastWork: DispatchWorkItem?

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

    // detail todos
    func confirmDTodo(_ id: Int) {
        guard let i = dtodos.firstIndex(where: { $0.id == id }) else { return }
        dtodos[i].status = dtodos[i].status == .confirmed ? dtodos[i].orig : .confirmed
    }

    func claimDTodo(_ id: Int) {
        guard let i = dtodos.firstIndex(where: { $0.id == id }) else { return }
        dtodos[i].status = .confirmed
        dtodos[i].owner = "我"
        dtodos[i].initial = "林"
        dtodos[i].color = Theme.green500
        showToast("已认领并建任务，负责人记为你")
    }

    func confirmAll() {
        let n = dtodos.filter { $0.status == .pending }.count
        for i in dtodos.indices where dtodos[i].status == .pending {
            dtodos[i].status = .confirmed
        }
        showToast("\(n) 条待办已确认并落成飞书任务")
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
    static func deriveCrossTodos(from meetings: [MeetingVM]) -> [CrossTodo] {
        var out: [CrossTodo] = []
        var id = 1
        for mv in meetings {
            for t in mv.dtodos {
                let label = mv.dayChip == "·" ? mv.title : "\(mv.title) · \(mv.dayChip)"
                out.append(CrossTodo(id: id, text: t.text, meeting: label,
                                     owner: t.owner ?? "待认领", initial: t.initial, color: t.color,
                                     due: t.due, status: t.status == .confirmed ? .done : .doing))
                id += 1
            }
        }
        return out
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
