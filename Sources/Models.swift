import SwiftUI
import Combine

// MARK: - Enums

enum Screen { case home, library, knowledge, calendar, detail, todos, followup, weekly, daily, settings }
enum KnowledgeTab: String, CaseIterable, Identifiable {
    case inbox
    case projects
    case ask
    var id: String { rawValue }
}
enum KnowledgeInboxFilter: String, CaseIterable, Identifiable {
    case pending
    case conflicts
    case missingOwner
    case duplicates
    case processed
    var id: String { rawValue }
}
enum KnowledgeDateFilter: String, CaseIterable, Identifiable {
    case all
    case last7Days
    case last30Days
    case last90Days
    var id: String { rawValue }
}
enum TodoFilter { case candidates, open, done }
enum DetailStatus { case pending, unclaimed, confirmed }
enum CrossStatus { case candidate, overdue, doing, done }

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
              owner: "周岚", initial: "周", color: Color(hex: "0075de"), due: "6/13", status: .candidate),
        .init(id: 2, text: "待办 → 飞书任务字段映射补充 open_id 兜底", meeting: "周三产品评审会 · 6/10",
              owner: "高翔", initial: "高", color: Color(hex: "1f7a4c"), due: "6/16", status: .candidate),
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
    private let noteRefiner: (String) async throws -> RefinedNote
    private let knowledgeStore: KnowledgeStore
    private let knowledgeWorker: KnowledgeExtractionWorker

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
    @Published var filter: TodoFilter = .candidates
    @Published var toast: String? = nil

    /// Real meetings — synced from Feishu (sync.sh) or captured live — else the sample fallback.
    @Published var meetings: [MeetingVM]
    @Published var usingRealData: Bool
    @Published var selectedMeeting = 0
    @Published var refining = false
    @Published var knowledgeEnabled = KnowledgeFeatureFlags.isEnabled
    @Published var knowledgeTab: KnowledgeTab = .inbox
    @Published private(set) var knowledgeUnits: [KnowledgeUnit] = []
    @Published private(set) var knowledgeInboxItems: [KnowledgeInboxItem] = []
    @Published private(set) var knowledgeProjects: [KnowledgeProject] = []
    @Published private(set) var knowledgeJobs: [KnowledgeExtractionJob] = []
    @Published private(set) var knowledgeUnavailableReason: String?
    @Published var knowledgeInboxFilter: KnowledgeInboxFilter = .pending
    @Published var knowledgeKindFilter: KnowledgeKind?
    @Published var knowledgeSourceFilter: KnowledgeSourceKind?
    @Published var knowledgeDateFilter: KnowledgeDateFilter = .all
    @Published var knowledgeBackfillRunning = false
    @Published var knowledgeBackfillPaused = true
    @Published var selectedKnowledgeEvidence: KnowledgeInboxEvidence?
    @Published var editingKnowledgeUnit: KnowledgeInboxItem?
    @Published var duplicateKnowledgeReview: KnowledgeDuplicateReview?
    @Published var conflictKnowledgeReview: KnowledgeConflictReview?
    @Published var archiveReviewSession: ArchiveReviewSession?
    @Published private(set) var archiveScanLoading = false
    private var archiveFilesByMatchID: [String: TranscriptFile] = [:]
    private var archiveMeetingTitles: [String: String] = [:]
    private var knowledgePilotJobIDs: Set<String> = []

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

    // 完整版 Markdown 纪要 — 每场会懒生成一次并缓存
    @Published var mdSummaries: [String: String] = MDSummaryStore.load()
    @Published var mdSummaryPending: Set<String> = []
    @Published var mdSummaryErrors: [String: String] = [:]

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
    /// 飞书写入尚未返回时保持原状态，避免把“请求已发出”误画成“任务已创建”。
    @Published private(set) var creatingTaskKeys: Set<String> = []
    @Published private(set) var bulkTaskCreationRemaining = 0
    private var bulkTaskCreationSucceeded = 0
    private var bulkTaskCreationFailed = 0

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
                let confirmed = t.status == .confirmed
                let status: CrossStatus = !confirmed ? .candidate
                    : doneTodoKeys.contains(key) ? .done
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

    /// `-demo YES`：跳过真实数据与飞书链路，只走内置示例（公开截图/演示用）。
    /// Hosted XCTest processes are forced into the same isolated path so tests never sync or mutate user data.
    static let demoMode = UserDefaults.standard.bool(forKey: "demo")
        || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    private static func realMeetingVMs(_ meetings: [RealMeeting],
                                       knowledgeStore: KnowledgeStore = .shared) -> [MeetingVM] {
        let sources = knowledgeStore.sources()
        var latestSourceByMeeting: [String: KnowledgeSourceDocument] = [:]
        for source in sources where source.sourceKind == .feishu {
            if latestSourceByMeeting[source.meetingID] == nil {
                latestSourceByMeeting[source.meetingID] = source
            }
        }
        let segmentsBySource = Dictionary(grouping: knowledgeStore.allSegments(), by: \.sourceID)
        return meetings.map { meeting in
            let source = latestSourceByMeeting[meeting.meeting_id]
            return MeetingVM(
                real: meeting,
                sourceText: source?.fullText,
                sourceSegments: source.flatMap { segmentsBySource[$0.id] } ?? [])
        }
    }

    init(loadPersistedData: Bool? = nil,
         knowledgeEnabledOverride: Bool? = nil,
         knowledgeStore: KnowledgeStore = .shared,
         noteRefiner: @escaping (String) async throws -> RefinedNote = { transcript in
             try await Refine.note(from: transcript)
         }) {
        self.noteRefiner = noteRefiner
        self.knowledgeStore = knowledgeStore
        self.knowledgeWorker = KnowledgeExtractionWorker(store: knowledgeStore)
        if let knowledgeEnabledOverride { self.knowledgeEnabled = knowledgeEnabledOverride }
        let shouldLoadPersistedData = loadPersistedData ?? !Self.demoMode
        let realRecords = shouldLoadPersistedData ? RealData.load() : []
        let reals = Self.realMeetingVMs(realRecords, knowledgeStore: knowledgeStore)
        let stored = shouldLoadPersistedData ? LiveStore.load() : []
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
        case "library":   screen = .library
        case "knowledge": screen = .knowledge
        case "calendar":  screen = .calendar
        case "settings": screen = .settings
        case "detail":   screen = .detail
        case "todos":    screen = .todos
        case "followup": screen = .followup
        case "weekly":   screen = .weekly
        case "daily":    screen = .daily
        default:         break
        }
        if UserDefaults.standard.bool(forKey: "archive") {
            libraryRawTab = true
            screen = .library
        }
        // 首启自动引导：老用户（库里已有数据）静默豁免，之后可从设置重看
        if UserDefaults.standard.bool(forKey: "onboarding") {
            showOnboarding = true
            obStep = min(4, max(0, UserDefaults.standard.integer(forKey: "obstep")))   // dev: 直跳某步
        } else if !Self.demoMode && !UserDefaults.standard.bool(forKey: "onboarded") {
            if usingRealData {
                UserDefaults.standard.set(true, forKey: "onboarded")   // 老用户，不打扰
            } else {
                showOnboarding = true
            }
        }

        if !Self.demoMode {
            Task { if let me = await Lark.me() { self.userName = me.name } }
        }
        sync.onNewMeetings = { [weak self] fresh in self?.mergeSynced(fresh) }
        // FeishuSync 是嵌套 ObservableObject，把它的变化转发出去，侧栏状态卡才会刷新
        syncForward = sync.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        if !Self.demoMode {
            sync.start()
            buildArchiveIndex()      // 转写档案全文进搜索
            calEvents = CalCache.load()   // 上次的日历先顶上（秒开），随后后台刷新
            loadCalendar()
            autoRecoverOrphans()     // 近 7 天有转写没纪要的录音，默认补生成
        }
        knowledgePilotJobIDs = knowledgeStore.pilotJobIDs()
        refreshDerived()
        refreshKnowledgeState()
        recoverPendingRefinements()
    }

    /// 自动同步拉到新会 → 并进列表并提示（本地捕获的仍排最上面）。
    private func mergeSynced(_ fresh: [RealMeeting]) {
        let vms = Self.realMeetingVMs(fresh, knowledgeStore: knowledgeStore)
        if !usingRealData { meetings = [] }
        usingRealData = true
        let liveCount = meetings.prefix(while: { $0.id.hasPrefix("live-") }).count
        meetings.insert(contentsOf: vms, at: liveCount)
        if selectedMeeting >= liveCount { selectedMeeting += vms.count }   // 正在看的那场别被顶换
        rederiveTodos()
        refreshDerived()
        refreshKnowledgeState()
        showToast("已同步 \(vms.count) 场新会议")
    }

    func selectMeeting(_ i: Int) {
        selectedMeeting = i
        dtodos = applyConfirmations(current.dtodos, meetingID: current.id)
        go(.detail)
    }

    /// Persist the raw capture first; note generation is a replaceable asynchronous derivative.
    func ingestLive(capture result: CapturedTranscript,
                    capturedName: String,
                    sourceKindOverride: KnowledgeSourceKind? = nil,
                    insertChronologically: Bool = false,
                    quiet: Bool = false) {
        let stopped = Date(timeIntervalSince1970: result.endedAt)
        let storedID = "live-\(Int(result.endedAt))"
        let userTitle = capturedName.trimmingCharacters(in: .whitespaces)
        let initialTitle = userTitle.isEmpty ? "未命名会议" : userTitle
        let pendingNote = RefinedNote.processing()
        let persisted = LiveStore.append(StoredLiveMeeting(
            id: storedID,
            title: initialTitle,
            timestamp: result.endedAt,
            durationSec: result.durationSec,
            transcript: result.text,
            note: pendingNote))
        if !persisted { showToast("录音写入数据库失败，已导出救援文件到数据目录") }

        liveDurations[storedID] = result.durationSec
        let pendingVM = MeetingVM(
            live: pendingNote,
            transcript: result.text,
            durationSec: result.durationSec,
            now: stopped,
            title: initialTitle)
        if let index = meetings.firstIndex(where: { $0.id == storedID }) {
            meetings[index] = pendingVM
            rederiveTodos()
            refreshDerived()
        } else if insertChronologically {
            insertLiveMeetingSorted(pendingVM, ts: result.endedAt)
        } else {
            addLiveMeeting(pendingVM)
        }
        freshLiveID = storedID
        refining = true

        if knowledgeStore.isAvailable {
            let sensitivity = KnowledgeSensitivityClassifier.classify(
                title: initialTitle,
                content: result.text)
            let bundle = KnowledgeSegmenter.sourceBundle(
                from: result,
                meetingID: storedID,
                sourceKindOverride: sourceKindOverride,
                sensitivity: sensitivity)
            if !knowledgeStore.saveSource(
                bundle.document, segments: bundle.segments, meetingTitle: initialTitle) {
                showToast("录音已保存，知识来源索引将在稍后补齐")
            } else {
                if knowledgeEnabled {
                    _ = KnowledgeJobPlanner.planExtraction(
                        for: bundle.document,
                        store: knowledgeStore,
                        enabled: true)
                    refreshKnowledgeState()
                }
                if !quiet { showToast("录音与逐字稿已保存，正在生成纪要…") }
            }
        } else if !quiet {
            showToast("录音与逐字稿已保存，正在生成纪要…")
        }

        Task {
            let note: RefinedNote
            let refineError: String?
            do {
                note = try await noteRefiner(result.text)
                refineError = nil
            } catch {
                refineError = error.localizedDescription
                note = .failed(reason: refineError!)
            }
            if userTitle.isEmpty, refineError == nil {
                capture.setStoredMeetingName(note.title, transcriptPath: result.transcriptPath)
            }
            let title = userTitle.isEmpty && refineError == nil ? note.title : initialTitle
            LiveStore.replaceNote(id: storedID, note: note, title: title)
            if let index = meetings.firstIndex(where: { $0.id == storedID }) {
                meetings[index] = MeetingVM(
                    live: note,
                    transcript: result.text,
                    durationSec: result.durationSec,
                    now: stopped,
                    title: title)
                rederiveTodos()
                refreshDerived()
            }
            refining = false
            if !quiet || refineError != nil {
                showToast(refineError == nil ? "纪要已生成：\(title)"
                                             : "提炼失败，录音已保存，可在详情页重新生成")
            }
        }
    }

    /// 提炼失败或上次异常退出时仍处于 processing 的会议，原地重试。
    @Published var regenPending: Set<String> = []
    func regenerateNote(id: String) {
        guard !regenPending.contains(id),
              let meeting = meetings.first(where: { $0.id == id }) else { return }
        let transcript = meeting.rawTranscript
        guard transcript.count >= 4 else { showToast("这场会没有可用的转写文本"); return }
        regenPending.insert(id)
        refining = true
        replaceLiveMeetingNote(id: id, note: .processing(), title: meeting.title)
        Task {
            do {
                let note = try await noteRefiner(transcript)
                let keepTitle = !(meeting.title.isEmpty || meeting.title.hasPrefix("未命名会议"))
                let title = keepTitle ? meeting.title : note.title
                replaceLiveMeetingNote(id: id, note: note, title: title)
                showToast("纪要已生成：\(title)")
            } catch {
                let failed = RefinedNote.failed(reason: error.localizedDescription)
                replaceLiveMeetingNote(id: id, note: failed, title: meeting.title)
                showToast("提炼失败：\(error.localizedDescription)")
            }
            regenPending.remove(id)
            refining = false
        }
    }

    private func replaceLiveMeetingNote(id: String, note: RefinedNote, title: String) {
        LiveStore.replaceNote(id: id, note: note, title: title)
        guard let index = meetings.firstIndex(where: { $0.id == id }),
              let stored = LiveStore.load().first(where: { $0.id == id }) else { return }
        meetings[index] = MeetingVM(
            live: note,
            transcript: stored.transcript,
            durationSec: stored.durationSec,
            now: Date(timeIntervalSince1970: stored.timestamp),
            title: title)
        rederiveTodos()
        refreshDerived()
    }

    private func recoverPendingRefinements() {
        let ids = meetings.filter {
            $0.id.hasPrefix("live-") && $0.displayBlocks.contains(where: { $0.type == "refinePending" })
        }.map(\.id)
        for id in ids { regenerateNote(id: id) }
    }

    /// 转写档案里的孤儿录音（app 早期版本提炼失败被丢弃的）→ 补生成纪要入库。
    @Published var archivePending: Set<String> = []
    /// 该时间段是否已有本地会议（档案条目对应的会存在 → 不用补生成）
    func hasLiveMeeting(overlapping start: Date, _ end: Date) -> Bool {
        for m in meetings where m.id.hasPrefix("live-") {
            guard let ts = Double(m.id.dropFirst("live-".count)) else { continue }
            let mEnd = ts
            let mStart = ts - Double(liveDurations[m.id] ?? 600)
            // ±10 分钟余量：转写文件时间和停录时间戳有偏移
            if mStart - 600 < end.timeIntervalSince1970, start.timeIntervalSince1970 < mEnd + 600 {
                return true
            }
        }
        return false
    }

    func generateFromArchive(_ f: TranscriptFile) {
        guard !archivePending.contains(f.title) else { return }
        archivePending.insert(f.title)
        Task {
            await ingestArchive(f, quiet: false)
            archivePending.remove(f.title)
        }
    }

    /// 档案 → 会议（提炼失败也入库，详情页可重试 —— 和 ingestLive 同一条"绝不丢会"原则）
    private func ingestArchive(_ file: TranscriptFile, quiet: Bool) async {
        let start = min(file.start.timeIntervalSince1970, file.end.timeIntervalSince1970)
        let end = max(file.start.timeIntervalSince1970, file.end.timeIntervalSince1970)
        let duration = max(60, Int(end - start))
        let result = CapturedTranscript(
            text: file.body,
            segments: [],
            transcriptionMode: .unknown,
            sessionID: "archive-" + String(KnowledgeIdentity.contentHash(file.body).prefix(20)),
            startedAt: start,
            endedAt: end,
            durationSec: duration,
            transcriptPath: file.url.path,
            segmentSidecarPath: nil)
        ingestLive(
            capture: result,
            capturedName: "",
            sourceKindOverride: .archive,
            insertChronologically: true,
            quiet: quiet)
    }

    /// 启动自动恢复：近 7 天的孤儿录音（有转写、没会议）默认补生成纪要，不用用户动手。
    /// 更早的陈年档案留给列表里的手动按钮，避免首次升级时批量轰炸。
    /// 转写内容指纹：去掉所有空白后取前若干字。用来判断"这份转写是不是已经入过库"。
    ///
    /// 原先只靠时间区间重叠判断，但 TranscriptFile 的 start 来自**文件名字符串**（时区无关），
    /// end 来自**文件 mtime**（绝对时刻）。跨时区旅行后（如 UTC+10 → UTC+8），旧文件的
    /// 文件名时间会被按新时区重新解读，与 mtime 错开数小时、区间甚至倒挂，导致同一批录音
    /// 每次启动都被重新判成孤儿、反复补生成。内容指纹与时间无关，不受影响。
    /// 纯字符串计算、不碰任何状态，所以标 nonisolated，后台队列也能直接算。
    nonisolated static func transcriptFingerprint(_ s: String) -> String {
        String(s.components(separatedBy: .whitespacesAndNewlines).joined().prefix(160))
    }

    func autoRecoverOrphans() {
        guard !Self.demoMode else { return }
        Task {
            let files = await Task.detached(priority: .utility) { TranscriptArchiveView.loadFiles() }.value
            let ingested = await Task.detached(priority: .utility) {
                Set(LiveStore.load().map { Self.transcriptFingerprint($0.transcript) })
            }.value
            let now = Date()
            let orphans = files.filter { f in
                f.chars >= 300                                            // 噪音碎片不成会
                && f.end > now.addingTimeInterval(-7 * 86400)             // 只自动救近 7 天
                && f.end < now.addingTimeInterval(-120)                   // 正在写入的（录音中）不碰
                && !ingested.contains(Self.transcriptFingerprint(f.body)) // 内容已入库 → 不是孤儿
                && !hasLiveMeeting(overlapping: f.start, f.end)           // 时间重叠仍作为兜底
            }
            guard !orphans.isEmpty else { return }
            showToast("发现 \(orphans.count) 场未生成纪要的录音，正在补生成…")
            for f in orphans.sorted(by: { $0.end < $1.end }) {            // 串行，旧的先落
                guard !archivePending.contains(f.title) else { continue }
                archivePending.insert(f.title)
                await ingestArchive(f, quiet: false)
                archivePending.remove(f.title)
            }
        }
    }

    /// 补生成的会是旧会，按时间戳落到正确位置（meetings 新→旧）。
    private func insertLiveMeetingSorted(_ vm: MeetingVM, ts: Double) {
        if !usingRealData { meetings = [] }
        usingRealData = true
        let idx = meetings.firstIndex { m in
            guard m.id.hasPrefix("live-"), let t = Double(m.id.dropFirst("live-".count)) else { return false }
            return t < ts
        } ?? meetings.count
        meetings.insert(vm, at: idx)
        if idx <= selectedMeeting { selectedMeeting += 1 }
        rederiveTodos()
        refreshDerived()
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
        watcher.onMeetingChanged = { [weak self] in self?.handleMeetingChanged() }
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

    /// 顶栏「暂停/继续」——录制中才有意义
    func togglePause() {
        guard capture.isCapturing else { return }
        capture.togglePause()
        showToast(capture.isPaused ? "已暂停，音频不再录入" : "已继续录制")
    }

    /// 幂等 start：面板按钮 / 菜单栏 / 自动检测同拍触发也只起一条流。
    private func beginCapture(openPanel: Bool) {
        guard !capture.isCapturing, !startInFlight, !stopInFlight else { return }
        guard CloudASRConfig.isConfigured || Whisper.available() else {
            showToast(Whisper.serverAvailable ? "未配置云端转写，也缺少本地转写模型，请在设置中处理" : "转写引擎异常，请重新安装应用")
            showRecPanel = true          // 面板里有黄条和「去设置」
            return
        }
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
        let capturedName = capture.meetingName
        Task {
            let result = await capture.stop()
            stopInFlight = false
            if result.text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 4 {
                ingestLive(capture: result, capturedName: capturedName)
            }
        }
    }

    /// 麦克风全程没释放、但 watcher 判断换了场会（连轴转）——收掉当前这场，立刻续上新的一场。
    /// 和 endCapture 不一样的地方只有一处：stop 完之后紧接着 beginCapture，而不是停在那不动。
    private func handleMeetingChanged() {
        guard capture.isCapturing, !stopInFlight else { return }
        stopInFlight = true
        let capturedName = capture.meetingName
        showToast("检测到新会议，已保存上一场并开始新录制")
        Task {
            let result = await capture.stop()
            stopInFlight = false
            if result.text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 4 {
                ingestLive(capture: result, capturedName: capturedName)
            }
            beginCapture(openPanel: false)
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

        staleTodosCache = ctodos.filter { $0.status == .overdue && (Self.overdueDays(due: $0.due) ?? 0) > 3 }
        maxOverdueDaysCache = ctodos.filter { $0.status == .overdue }
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
        // 多轮追问的上下文：本会已完成的问答轮（失败轮不带）
        let history: [(q: String, a: String)] = (qaThreads[id] ?? []).compactMap { t in
            guard let a = t.answer, !a.hasPrefix("回答失败") else { return nil }
            return (q: t.question, a: a)
        }
        qaThreads[id, default: []].append(QATurn(question: q, answer: nil))
        qaPending.insert(id)
        QAStore.save(qaThreads)
        Task {
            let answer: String
            do { answer = try await Refine.ask(transcript: transcript, history: history, question: q) }
            catch { answer = "回答失败：\(error.localizedDescription)" }
            if var t = qaThreads[id], let i = t.lastIndex(where: { $0.answer == nil }) {
                t[i].answer = answer
                qaThreads[id] = t
                QAStore.save(qaThreads)
            }
            qaPending.remove(id)
        }
    }

    /// 懒生成当前会议的完整版 Markdown 纪要；已有缓存或正在生成则不重复调用。
    func generateMarkdownSummary() {
        let id = current.id
        guard mdSummaries[id] == nil, !mdSummaryPending.contains(id) else { return }
        let transcript = current.rawTranscript
        mdSummaryPending.insert(id)
        mdSummaryErrors[id] = nil
        Task {
            do {
                let text = try await Refine.markdownSummary(from: transcript)
                mdSummaries[id] = text
                MDSummaryStore.save(id, text)
            } catch {
                mdSummaryErrors[id] = error.localizedDescription
            }
            mdSummaryPending.remove(id)
        }
    }

    /// 清掉缓存（内存 + DB 下次保存会覆盖旧行）重新调一次，用于 prompt 改了或用户手动要求刷新
    func regenerateMarkdownSummary() {
        let id = current.id
        mdSummaries[id] = nil
        mdSummaryErrors[id] = nil
        generateMarkdownSummary()
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
            guard let candidates = await Lark.eventsOverlapping(start: recStart, durationSec: dur) else {
                calendarChecked.remove(m.id)   // 查询失败 ≠ 没会：下次打开再试
                return
            }
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

    func setKnowledgeEnabled(_ enabled: Bool) {
        knowledgeEnabled = enabled
        KnowledgeFeatureFlags.setEnabled(enabled)
        if enabled { refreshKnowledgeState() }
    }

    func refreshKnowledgeState() {
        knowledgeUnavailableReason = knowledgeStore.unavailableReason
        knowledgeUnits = knowledgeStore.units()
        knowledgeInboxItems = knowledgeStore.inboxItems()
        knowledgeProjects = knowledgeStore.projects(includeArchived: true)
        knowledgeJobs = knowledgeStore.jobs()
    }

    func beginConflictReview(_ item: KnowledgeInboxItem) {
        let pending = knowledgeInboxItems.filter {
            $0.id != item.id
                && $0.unit.reviewStatus != .rejected
                && $0.unit.conflictStatus == .pending
        }
        let sameSubject = pending.filter {
            let subjectMatches = item.unit.subject != nil && $0.unit.subject == item.unit.subject
            let predicateMatches = item.unit.predicate != nil && $0.unit.predicate == item.unit.predicate
            return subjectMatches || predicateMatches
        }
        let alternatives = sameSubject.isEmpty ? pending : sameSubject
        guard !alternatives.isEmpty else {
            showToast("没有找到另一条待处理冲突")
            return
        }
        conflictKnowledgeReview = KnowledgeConflictReview(
            id: item.id,
            primary: item,
            alternatives: alternatives)
    }

    @discardableResult
    func resolveKnowledgeConflict(otherID: String,
                                  resolution: KnowledgeConflictResolution) -> Bool {
        guard let review = conflictKnowledgeReview,
              review.alternatives.contains(where: { $0.id == otherID }),
              knowledgeStore.resolveConflict(
                primaryID: review.primary.id,
                otherID: otherID,
                resolution: resolution,
                reason: "用户在冲突确认中处理") else {
            showToast("冲突处理失败，知识状态可能已变化")
            return false
        }
        conflictKnowledgeReview = nil
        refreshKnowledgeState()
        showToast("冲突已处理，历史版本仍保留")
        return true
    }

    func beginDuplicateReview(_ item: KnowledgeInboxItem) {
        let matches = knowledgeInboxItems.filter {
            $0.unit.fingerprint == item.unit.fingerprint && $0.unit.reviewStatus != .rejected
        }
        guard matches.count > 1 else {
            showToast("没有可合并的重复知识")
            return
        }
        duplicateKnowledgeReview = KnowledgeDuplicateReview(
            id: item.unit.fingerprint,
            items: matches)
    }

    @discardableResult
    func mergeDuplicateKnowledge(primaryID: String) -> Bool {
        guard let review = duplicateKnowledgeReview,
              review.items.contains(where: { $0.id == primaryID }) else { return false }
        let duplicates = review.items.filter { $0.id != primaryID }
        for duplicate in duplicates {
            guard knowledgeStore.mergeUnits(
                primaryID: primaryID,
                duplicateID: duplicate.id,
                reason: "用户在重复知识确认中合并") else {
                refreshKnowledgeState()
                showToast("部分合并失败，请检查剩余候选")
                return false
            }
        }
        duplicateKnowledgeReview = nil
        refreshKnowledgeState()
        showToast("已合并 \(duplicates.count) 条重复知识")
        return true
    }

    func rejectKnowledgeUnit(id: String) {
        guard knowledgeStore.rejectUnit(id: id) else {
            showToast("忽略失败：知识状态已变化")
            return
        }
        refreshKnowledgeState()
        showToast("已忽略，可在“已处理”中恢复")
    }

    func restoreKnowledgeUnit(id: String) {
        let meetingID = knowledgeInboxItems.first(where: { $0.id == id })?.sources.first?.meetingID
        let title = meetingID.flatMap { sourceID in
            meetings.first(where: { $0.id == sourceID })?.title
        } ?? meetingID ?? "会议知识"
        guard knowledgeStore.restoreUnit(id: id, meetingTitle: title) else {
            showToast("恢复失败：来源证据不可用")
            return
        }
        refreshKnowledgeState()
        showToast("已恢复到待确认")
    }

    func beginEditingKnowledgeUnit(_ item: KnowledgeInboxItem) {
        editingKnowledgeUnit = item
    }

    @discardableResult
    func editKnowledgeUnit(id: String, edits: KnowledgeUnitEdits) -> Bool {
        let meetingID = knowledgeInboxItems.first(where: { $0.id == id })?.sources.first?.meetingID
        let title = meetingID.flatMap { sourceID in
            meetings.first(where: { $0.id == sourceID })?.title
        } ?? meetingID ?? "会议知识"
        guard knowledgeStore.editUnit(id: id, edits: edits, meetingTitle: title) else {
            showToast("保存失败：请检查内容和证据状态")
            return false
        }
        editingKnowledgeUnit = nil
        refreshKnowledgeState()
        showToast("已修改并加入知识库")
        return true
    }

    func confirmKnowledgeUnit(id: String) {
        guard knowledgeStore.confirmUnit(id: id) else {
            showToast("确认失败：候选缺少有效证据或状态已变化")
            return
        }
        refreshKnowledgeState()
        showToast("已加入知识库")
    }

    func knowledgeEvidenceWindow(for evidence: KnowledgeInboxEvidence) -> [KnowledgeSourceSegment] {
        let segments = knowledgeStore.segments(sourceID: evidence.source.id)
        guard let index = segments.firstIndex(where: { $0.id == evidence.segment.id }) else {
            return [evidence.segment]
        }
        let lower = max(segments.startIndex, index - 1)
        let upper = min(segments.endIndex, index + 2)
        return Array(segments[lower..<upper])
    }

    func openKnowledgeEvidence(_ evidence: KnowledgeInboxEvidence) {
        selectedKnowledgeEvidence = evidence
    }

    func openKnowledgeEvidenceMeeting(_ evidence: KnowledgeInboxEvidence) {
        guard let index = meetings.firstIndex(where: { $0.id == evidence.source.meetingID }) else {
            showToast("来源会议当前不在会议库中")
            return
        }
        selectedKnowledgeEvidence = nil
        selectMeeting(index)
    }

    func startArchiveReviewScan() {
        guard !archiveScanLoading else { return }
        archiveScanLoading = true
        Task {
            let files = await Task.detached(priority: .utility) {
                TranscriptArchiveView.loadFiles()
            }.value
            let stored = await Task.detached(priority: .utility) { LiveStore.load() }.value
            prepareArchiveReview(archives: files, storedMeetings: stored)
            archiveScanLoading = false
        }
    }

    @discardableResult
    func prepareArchiveReview(archives: [TranscriptFile],
                              storedMeetings: [StoredLiveMeeting]) -> ArchiveMatchReport {
        let report = KnowledgeArchiveMatcher.reconcile(
            archives: archives,
            meetings: storedMeetings)
        archiveMeetingTitles = Dictionary(uniqueKeysWithValues: storedMeetings.map { ($0.id, $0.title) })
        let filesByPath = Dictionary(uniqueKeysWithValues: archives.map { ($0.url.path, $0) })
        archiveFilesByMatchID = Dictionary(uniqueKeysWithValues: report.records.compactMap { record in
            filesByPath[record.archivePath].map { (record.id, $0) }
        })
        archiveReviewSession = ArchiveReviewSession(report: report)
        return report
    }

    @discardableResult
    func bindArchiveRecord(_ recordID: String, to meetingID: String) -> Bool {
        guard let session = archiveReviewSession,
              let record = session.report.records.first(where: { $0.id == recordID }),
              record.status == .ambiguous,
              record.candidateMeetingIDs.contains(meetingID),
              let file = archiveFilesByMatchID[recordID] else { return false }
        let title = meetings.first(where: { $0.id == meetingID })?.title
            ?? archiveMeetingTitles[meetingID] ?? meetingID
        let sensitivity = KnowledgeSensitivityClassifier.classify(title: title, content: file.body)
        let bundle = KnowledgeSegmenter.plainTextSourceBundle(
            content: file.body,
            meetingID: meetingID,
            sourceKind: .archive,
            locator: file.url.path,
            startedAt: min(file.start, file.end).timeIntervalSince1970,
            endedAt: max(file.start, file.end).timeIntervalSince1970,
            observedAt: max(file.start, file.end).timeIntervalSince1970,
            sensitivity: sensitivity)
        guard knowledgeStore.saveSource(
            bundle.document,
            segments: bundle.segments,
            meetingTitle: title) else { return false }
        _ = knowledgeStore.appendFeedback(KnowledgeFeedbackEvent(
            id: UUID().uuidString.lowercased(),
            targetType: "source_document",
            targetID: bundle.document.id,
            action: .relate,
            beforeJSON: "{\"archive_match\":\"ambiguous\"}",
            afterJSON: "{\"meeting_id\":\"\(meetingID)\"}",
            reason: "用户确认档案所属会议",
            actor: "user",
            createdAt: Date().timeIntervalSince1970))
        if knowledgeEnabled {
            let result = KnowledgeJobPlanner.planExtraction(
                for: bundle.document,
                store: knowledgeStore,
                enabled: true)
            switch result {
            case .enqueued(let job), .existing(let job):
                knowledgePilotJobIDs.insert(job.id)
                _ = knowledgeStore.savePilotJobIDs(knowledgePilotJobIDs)
            default: break
            }
        }
        markArchiveRecordResolved(recordID, meetingID: meetingID)
        refreshKnowledgeState()
        showToast("转写档案已绑定到「\(title)」")
        return true
    }

    func importArchiveRecordAsMeeting(_ recordID: String) async -> Bool {
        guard let session = archiveReviewSession,
              let record = session.report.records.first(where: { $0.id == recordID }),
              record.status == .orphan || record.status == .ambiguous,
              let file = archiveFilesByMatchID[recordID],
              !archivePending.contains(file.title) else { return false }
        let end = max(file.start, file.end).timeIntervalSince1970
        let meetingID = "live-\(Int(end))"
        guard !meetings.contains(where: { $0.id == meetingID }),
              !LiveStore.load().contains(where: { $0.id == meetingID }) else {
            showToast("该时间点已有会议，请改为绑定到已有会议")
            return false
        }
        archivePending.insert(file.title)
        await ingestArchive(file, quiet: false)
        archivePending.remove(file.title)
        markArchiveRecordResolved(recordID, meetingID: meetingID)
        refreshKnowledgeState()
        return true
    }

    private func markArchiveRecordResolved(_ recordID: String, meetingID: String) {
        guard let session = archiveReviewSession,
              let index = session.report.records.firstIndex(where: { $0.id == recordID }) else { return }
        var records = session.report.records
        let previous = records[index]
        records[index] = ArchiveMatchRecord(
            id: previous.id,
            archiveTitle: previous.archiveTitle,
            archivePath: previous.archivePath,
            characterCount: previous.characterCount,
            startedAt: previous.startedAt,
            endedAt: previous.endedAt,
            contentHash: previous.contentHash,
            status: .matched,
            basis: previous.basis,
            candidateMeetingIDs: [meetingID])
        archiveFilesByMatchID[recordID] = nil
        archiveReviewSession = ArchiveReviewSession(
            id: session.id,
            report: ArchiveMatchReport(records: records))
    }

    var knowledgeBackfillProgress: KnowledgeBackfillProgress {
        let pilotJobs = knowledgeJobs.filter { knowledgePilotJobIDs.contains($0.id) }
        return KnowledgeBackfillProgress(
            total: pilotJobs.count,
            completed: pilotJobs.filter { $0.state == .done }.count,
            running: pilotJobs.filter { $0.state == .running }.count,
            waiting: pilotJobs.filter { $0.state == .pending || $0.state == .retry }.count,
            failed: pilotJobs.filter { $0.state == .failed }.count,
            cancelled: pilotJobs.filter { $0.state == .cancelled }.count,
            candidateUnits: knowledgeInboxItems.filter { item in
                item.unit.reviewStatus == .candidate
                    && item.sources.contains { source in
                        pilotJobs.contains { $0.sourceID == source.id }
                    }
            }.count)
    }

    @discardableResult
    func prepareKnowledgePilot(from storedMeetings: [StoredLiveMeeting], limit: Int = 10) -> Int {
        guard knowledgeEnabled, knowledgeStore.isAvailable, limit > 0 else { return 0 }
        var prepared = 0
        var sourceByMeeting = Dictionary(
            grouping: knowledgeStore.sources(), by: \.meetingID)
            .compactMapValues { $0.sorted { $0.updatedAt > $1.updatedAt }.first }
        let jobsBySource = Dictionary(grouping: knowledgeStore.jobs(), by: \.sourceID)
        for meeting in storedMeetings.sorted(by: { $0.timestamp > $1.timestamp }) {
            guard prepared < limit,
                  meeting.transcript.trimmingCharacters(in: .whitespacesAndNewlines).count >= 300,
                  KnowledgeSensitivityClassifier.classify(
                    title: meeting.title, content: meeting.transcript) == .normal else { continue }
            let source: KnowledgeSourceDocument
            if let existing = sourceByMeeting[meeting.id] {
                if jobsBySource[existing.id]?.isEmpty == false { continue }
                source = existing
            } else {
                let bundle = KnowledgeSegmenter.plainTextSourceBundle(
                    content: meeting.transcript,
                    meetingID: meeting.id,
                    sourceKind: .archive,
                    startedAt: meeting.timestamp - Double(max(0, meeting.durationSec)),
                    endedAt: meeting.timestamp,
                    observedAt: meeting.timestamp,
                    sensitivity: .normal)
                guard knowledgeStore.saveSource(
                    bundle.document, segments: bundle.segments, meetingTitle: meeting.title) else { continue }
                source = bundle.document
                sourceByMeeting[meeting.id] = source
            }
            let result = KnowledgeJobPlanner.planExtraction(
                for: source,
                store: knowledgeStore,
                enabled: true,
                now: Date().timeIntervalSince1970)
            switch result {
            case .enqueued(let job), .existing(let job):
                knowledgePilotJobIDs.insert(job.id)
                prepared += 1
            default: break
            }
        }
        _ = knowledgeStore.savePilotJobIDs(knowledgePilotJobIDs)
        refreshKnowledgeState()
        return prepared
    }

    func startKnowledgePilot() {
        guard !knowledgeBackfillRunning else { return }
        let prepared = prepareKnowledgePilot(from: LiveStore.load(), limit: 10)
        guard prepared > 0 || knowledgeBackfillProgress.waiting > 0 else {
            showToast("没有可试跑的非敏感历史会议")
            return
        }
        knowledgeBackfillPaused = false
        Task { await runKnowledgeQueue() }
    }

    func pauseKnowledgeBackfill() {
        knowledgeBackfillPaused = true
        showToast(knowledgeBackfillRunning ? "将在当前来源完成后暂停" : "知识提炼已暂停")
    }

    func continueKnowledgeBackfill() {
        guard !knowledgeBackfillRunning else { return }
        knowledgeBackfillPaused = false
        Task { await runKnowledgeQueue() }
    }

    func retryFailedKnowledgeJobs() {
        let failedIDs = knowledgeJobs.filter {
            $0.state == .failed && knowledgePilotJobIDs.contains($0.id)
        }.map(\.id)
        guard !failedIDs.isEmpty else { return }
        Task {
            for id in failedIDs { _ = await knowledgeWorker.retry(jobID: id) }
            refreshKnowledgeState()
            continueKnowledgeBackfill()
        }
    }

    func runKnowledgeQueue(client: any KnowledgeExtractionClient = RefineKnowledgeExtractionClient()) async {
        guard !knowledgeBackfillRunning, !knowledgeBackfillPaused, knowledgeEnabled else { return }
        knowledgeBackfillRunning = true
        defer {
            knowledgeBackfillRunning = false
            refreshKnowledgeState()
        }
        let metadata = Dictionary(uniqueKeysWithValues: meetings.map {
            ($0.id, KnowledgeMeetingMetadata(title: $0.title, dateLabel: $0.recentMeta))
        })
        let pipeline = KnowledgeExtractionPipeline(
            store: knowledgeStore,
            client: client,
            meetingMetadata: { meetingID in
                metadata[meetingID] ?? KnowledgeMeetingMetadata(title: meetingID, dateLabel: nil)
            })
        while !knowledgeBackfillPaused {
            let processed = await knowledgeWorker.runNext(allowedJobIDs: knowledgePilotJobIDs) { job in
                try await pipeline.execute(job)
            }
            refreshKnowledgeState()
            if !processed { break }
        }
    }

    var visibleKnowledgeInboxItems: [KnowledgeInboxItem] {
        Self.filterKnowledgeInbox(
            knowledgeInboxItems,
            state: knowledgeInboxFilter,
            kind: knowledgeKindFilter,
            source: knowledgeSourceFilter,
            date: knowledgeDateFilter,
            now: Date())
    }

    func knowledgeInboxCount(_ filter: KnowledgeInboxFilter) -> Int {
        Self.filterKnowledgeInbox(
            knowledgeInboxItems,
            state: filter,
            kind: knowledgeKindFilter,
            source: knowledgeSourceFilter,
            date: knowledgeDateFilter,
            now: Date()).count
    }

    nonisolated static func filterKnowledgeInbox(_ items: [KnowledgeInboxItem],
                                     state: KnowledgeInboxFilter,
                                     kind: KnowledgeKind?,
                                     source: KnowledgeSourceKind?,
                                     date: KnowledgeDateFilter,
                                     now: Date) -> [KnowledgeInboxItem] {
        let cutoff: TimeInterval? = switch date {
        case .all: nil
        case .last7Days: now.addingTimeInterval(-7 * 86_400).timeIntervalSince1970
        case .last30Days: now.addingTimeInterval(-30 * 86_400).timeIntervalSince1970
        case .last90Days: now.addingTimeInterval(-90 * 86_400).timeIntervalSince1970
        }
        return items.filter { item in
            let stateMatches: Bool = switch state {
            case .pending: item.unit.reviewStatus == .candidate
            case .conflicts: item.unit.conflictStatus == .pending
            case .missingOwner: item.unit.reviewStatus == .candidate && item.isMissingOwner
            case .duplicates: item.unit.reviewStatus == .candidate && item.duplicateCount > 1
            case .processed: item.unit.reviewStatus != .candidate
            }
            return stateMatches
                && (kind == nil || item.unit.kind == kind)
                && (source == nil || item.sourceKinds.contains(source!))
                && (cutoff == nil || item.unit.observedAt >= cutoff!)
        }.sorted { left, right in
            let leftPriority = knowledgeKindPriority(left.unit.kind)
            let rightPriority = knowledgeKindPriority(right.unit.kind)
            if leftPriority != rightPriority { return leftPriority < rightPriority }
            if left.unit.evidenceLevel != right.unit.evidenceLevel {
                return left.unit.evidenceLevel == .direct
            }
            if left.unit.observedAt != right.unit.observedAt {
                return left.unit.observedAt > right.unit.observedAt
            }
            return left.id < right.id
        }
    }

    nonisolated private static func knowledgeKindPriority(_ kind: KnowledgeKind) -> Int {
        switch kind {
        case .decision: return 0
        case .action: return 1
        case .openQuestion: return 2
        case .metric: return 3
        case .risk: return 4
        case .dispute: return 5
        case .fact: return 6
        }
    }

    var knowledgeAttentionCount: Int {
        guard knowledgeEnabled else { return 0 }
        return knowledgeUnits.filter { $0.reviewStatus == .candidate }.count
            + knowledgeJobs.filter { $0.state == .failed }.count
    }

    var knowledgeBadge: String? {
        knowledgeAttentionCount > 0 ? String(knowledgeAttentionCount) : nil
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

    func isCreatingTask(_ todoID: Int) -> Bool { creatingTaskKeys.contains(linkKey(todoID)) }
    var isBulkCreatingTasks: Bool { bulkTaskCreationRemaining > 0 }

    func confirmDTodo(_ id: Int) {
        guard let i = dtodos.firstIndex(where: { $0.id == id }) else { return }
        if dtodos[i].status == .confirmed {
            showToast("该待办已经创建过飞书任务")
            return
        }
        guard !isCreatingTask(id) else { return }
        if !usingRealData || !Lark.available { dtodos[i].status = .confirmed }
        createLarkTask(for: dtodos[i], assignToSelf: false)
    }

    func claimDTodo(_ id: Int) {
        guard let i = dtodos.firstIndex(where: { $0.id == id }) else { return }
        guard !isCreatingTask(id) else { return }
        if !usingRealData || !Lark.available {
            dtodos[i].status = .confirmed
            dtodos[i].owner = userName.isEmpty ? "我" : userName
            dtodos[i].initial = userName.isEmpty ? "我" : userInitial
            dtodos[i].color = Theme.green500
        }
        createLarkTask(for: dtodos[i], assignToSelf: true)
    }

    func confirmAll() {
        // “全部”必须同时覆盖待确认和待认领；待认领项建成未指派任务，之后仍可在飞书认领。
        let candidates = dtodos.filter {
            $0.status != .confirmed && taskLinks[linkKey($0.id)] == nil && !isCreatingTask($0.id)
        }
        guard !candidates.isEmpty else {
            showToast("没有需要创建的待办")
            return
        }
        guard usingRealData && Lark.available else {
            for i in dtodos.indices where dtodos[i].status != .confirmed { dtodos[i].status = .confirmed }
            showToast("已确认 \(candidates.count) 条（未创建真实飞书任务）")
            return
        }

        bulkTaskCreationRemaining = candidates.count
        bulkTaskCreationSucceeded = 0
        bulkTaskCreationFailed = 0
        showToast("正在创建 \(candidates.count) 个飞书任务…")
        for todo in candidates { createLarkTask(for: todo, assignToSelf: false, quiet: true) }
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
        let meetingID = current.id
        let key = "\(meetingID)|\(todo.id)"
        guard taskLinks[key] == nil else {
            if !quiet { showToast("该待办已创建过飞书任务") }
            return
        }
        guard !creatingTaskKeys.contains(key) else { return }
        creatingTaskKeys.insert(key)
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
                if assignToSelf, current.id == meetingID,
                   let i = dtodos.firstIndex(where: { $0.id == todo.id }) {
                    dtodos[i].owner = userName.isEmpty ? "我" : userName
                    dtodos[i].initial = userName.isEmpty ? "我" : userInitial
                    dtodos[i].color = Theme.green500
                }
                refreshDerived()
                finishTaskCreation(key: key, succeeded: true, quiet: quiet,
                                   message: assignToSelf ? "已认领，飞书任务已创建"
                                                        : "飞书任务已创建：\(todo.text.prefix(14))…\(note)")
            } catch {
                finishTaskCreation(key: key, succeeded: false, quiet: quiet,
                                   message: "创建飞书任务失败：\(error.localizedDescription)")
            }
        }
    }

    private func finishTaskCreation(key: String, succeeded: Bool, quiet: Bool, message: String) {
        creatingTaskKeys.remove(key)
        guard quiet else {
            showToast(message)
            return
        }
        if succeeded { bulkTaskCreationSucceeded += 1 } else { bulkTaskCreationFailed += 1 }
        bulkTaskCreationRemaining = max(0, bulkTaskCreationRemaining - 1)
        guard bulkTaskCreationRemaining == 0 else { return }
        if bulkTaskCreationFailed == 0 {
            showToast("已创建 \(bulkTaskCreationSucceeded) 个飞书任务")
        } else {
            showToast("已创建 \(bulkTaskCreationSucceeded) 个，失败 \(bulkTaskCreationFailed) 个；失败项可重试")
        }
    }

    // cross-meeting todos
    func toggleCtodo(_ id: Int) {
        guard let i = ctodos.firstIndex(where: { $0.id == id }) else { return }
        guard ctodos[i].status != .candidate else {
            openCandidate(ctodos[i])
            return
        }
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

    /// 自动抽取的行动项只是候选；集中页点击后回到原会议确认，不能直接当成已完成任务。
    func openCandidate(_ todo: CrossTodo) {
        guard let i = meetings.firstIndex(where: { todo.key.hasPrefix("\($0.id)|") }) else { return }
        selectMeeting(i)
    }

    func toggleFitem(_ id: Int) {
        guard let i = fitems.firstIndex(where: { $0.id == id }) else { return }
        fitems[i].done.toggle()
    }

    // onboarding
    func obNext() {
        if obStep >= 4 {
            showOnboarding = false
            obStep = 0
            UserDefaults.standard.set(true, forKey: "onboarded")
            showToast(Whisper.available() ? "就绪，检测到会议时会自动提示录制" : "已完成，记得在设置中下载转写模型")
        } else {
            withAnimation(.easeOut(duration: 0.2)) { obStep += 1 }
        }
    }

    func obSkip() {
        showOnboarding = false
        obStep = 0
        UserDefaults.standard.set(true, forKey: "onboarded")
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
            if let events, !events.isEmpty || force {   // 查询失败（nil）不覆盖缓存
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

    /// 追问卡上勾选：把对应的跨会议待办翻转（按文本匹配上一场会的那条）。
    func toggleFollowItem(text: String, meetingTitle: String) {
        if let i = ctodos.firstIndex(where: { $0.text == text && $0.meeting.hasPrefix(meetingTitle) }) {
            toggleCtodo(ctodos[i].id)
        }
    }

    // derived
    var candidateCount: Int { ctodos.filter { $0.status == .candidate }.count }
    var officialTodos: [CrossTodo] { ctodos.filter { $0.status != .candidate } }
    var openCount: Int { officialTodos.filter { $0.status != .done }.count }
    var crossDone: Int { ctodos.filter { $0.status == .done }.count }
    var closeRatePct: Int {
        officialTodos.isEmpty ? 0 : Int((Double(crossDone) / Double(officialTodos.count) * 100).rounded())
    }
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
