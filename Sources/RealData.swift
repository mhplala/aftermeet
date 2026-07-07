import SwiftUI

// MARK: - Codable mirror of meetings.json (produced by sync.sh)

struct RealStore: Codable { let meetings: [RealMeeting] }

struct RealMeeting: Codable {
    let meeting_id: String
    let title: String
    let dateLabel: String?
    let durationLabel: String?
    let participants: Int?
    let organizer: String?
    let summary: String
    let keyPoints: [String]?
    let decisions: [RDecision]
    let todos: [RTodo]
    let disputes: [RDispute]
    let nextAgenda: [String]
    let excerpts: [RExcerpt]
    let blocks: [NoteBlock]?

    enum CodingKeys: String, CodingKey {
        case meeting_id, title, dateLabel, durationLabel, participants, organizer,
             summary, keyPoints, decisions, todos, disputes, nextAgenda, excerpts, blocks
    }

    // 容错解码：mini 模型偶尔漏掉某个空数组字段，别让一个字段废掉整场会。
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        meeting_id    = try c.decode(String.self, forKey: .meeting_id)
        title         = (try? c.decode(String.self, forKey: .title)) ?? "未命名会议"
        dateLabel     = try? c.decodeIfPresent(String.self, forKey: .dateLabel)
        durationLabel = try? c.decodeIfPresent(String.self, forKey: .durationLabel)
        participants  = try? c.decodeIfPresent(Int.self, forKey: .participants)
        organizer     = try? c.decodeIfPresent(String.self, forKey: .organizer)
        summary       = (try? c.decode(String.self, forKey: .summary)) ?? ""
        keyPoints     = try? c.decodeIfPresent([String].self, forKey: .keyPoints)
        decisions     = (try? c.decode([RDecision].self, forKey: .decisions)) ?? []
        todos         = (try? c.decode([RTodo].self, forKey: .todos)) ?? []
        disputes      = (try? c.decode([RDispute].self, forKey: .disputes)) ?? []
        nextAgenda    = (try? c.decode([String].self, forKey: .nextAgenda)) ?? []
        excerpts      = (try? c.decode([RExcerpt].self, forKey: .excerpts)) ?? []
        blocks        = try? c.decodeIfPresent([NoteBlock].self, forKey: .blocks)
    }
}
struct RDecision: Codable { let no: String?; let text: String }
struct RTodo: Codable { let text: String; let owner: String?; let due: String?; let confidence: String? }
struct RDispute: Codable { let title: String; let body: String }
struct RExcerpt: Codable { let time: String?; let who: String?; let text: String }

// MARK: - Generative note spec — 豆包 emits an ordered list of these; NoteBlocksView renders them.
// One flexible struct per block; the renderer reads only the fields relevant to `type`.

struct NoteBlock: Codable {
    let type: String
    var text: String? = nil       // summary / quote text
    var who: String? = nil        // quote speaker
    var items: [String]? = nil    // each "a|b|c" — sub-fields pipe-delimited (flat = the mini model emits it reliably)
    var before: String? = nil     // beforeAfter: "label|detail"
    var after: String? = nil

    init(type: String, text: String? = nil, who: String? = nil,
         items: [String]? = nil, before: String? = nil, after: String? = nil) {
        self.type = type; self.text = text; self.who = who
        self.items = items; self.before = before; self.after = after
    }

    enum CodingKeys: String, CodingKey { case type, text, who, items, before, after }

    // Tolerant decode: the mini model sometimes emits `items` as one delimited String instead of a
    // [String] — accept both so one slip doesn't fail the block (and, via the array decode, the whole file).
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        type   = try c.decode(String.self, forKey: .type)
        text   = try? c.decodeIfPresent(String.self, forKey: .text)
        who    = try? c.decodeIfPresent(String.self, forKey: .who)
        before = try? c.decodeIfPresent(String.self, forKey: .before)
        after  = try? c.decodeIfPresent(String.self, forKey: .after)
        if let arr = try? c.decodeIfPresent([String].self, forKey: .items) {
            items = arr
        } else if let s = try? c.decodeIfPresent(String.self, forKey: .items), !s.isEmpty {
            items = s.components(separatedBy: CharacterSet(charactersIn: "、；;\n"))
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        } else {
            items = nil
        }
    }
}

enum RealData {
    /// ~/Library/Application Support/AfterMeet/meetings.json
    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("AfterMeet/meetings.json")
    }
    static func load() -> [RealMeeting] {
        guard let data = try? Data(contentsOf: fileURL),
              let store = try? JSONDecoder().decode(RealStore.self, from: data)
        else { return [] }
        return store.meetings
    }
    static func save(_ meetings: [RealMeeting]) {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(RealStore(meetings: meetings)) {
            try? data.write(to: fileURL)
        }
    }
}

// MARK: - Locally-captured meetings, persisted to disk so they survive a restart

struct StoredLiveMeeting: Codable {
    let id: String
    let title: String
    let timestamp: Double
    let durationSec: Int
    let transcript: String
    let note: RefinedNote
}

enum LiveStore {
    /// ~/Library/Application Support/AfterMeet/live-meetings.json — separate from sync.sh's meetings.json
    /// so a Feishu sync can never clobber locally-captured meetings.
    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("AfterMeet/live-meetings.json")
    }
    static func load() -> [StoredLiveMeeting] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let dec = JSONDecoder()
        if let items = try? dec.decode([StoredLiveMeeting].self, from: data) { return items }
        // one corrupt record must not drop them all — decode element-by-element, skip only the broken ones
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return [] }
        return raw.compactMap { obj in
            (try? JSONSerialization.data(withJSONObject: obj)).flatMap { try? dec.decode(StoredLiveMeeting.self, from: $0) }
        }
    }
    static func rename(id: String, title: String) {
        let items = load().map { m -> StoredLiveMeeting in
            guard m.id == id else { return m }
            return StoredLiveMeeting(id: m.id, title: title, timestamp: m.timestamp,
                                     durationSec: m.durationSec, transcript: m.transcript, note: m.note)
        }
        if let data = try? JSONEncoder().encode(items) { try? data.write(to: fileURL) }
    }

    static func append(_ m: StoredLiveMeeting) {
        var items = load()
        items.append(m)
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(items) { try? data.write(to: fileURL) }
    }
}

// MARK: - 每日综述 cache — one digest (block list) per day, keyed by dayChip ("6/22")

enum DailyStore {
    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("AfterMeet/daily-digests.json")
    }
    static func load() -> [String: [NoteBlock]] {
        guard let data = try? Data(contentsOf: fileURL),
              let m = try? JSONDecoder().decode([String: [NoteBlock]].self, from: data) else { return [:] }
        return m
    }
    static func save(_ m: [String: [NoteBlock]]) {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(m) { try? data.write(to: fileURL) }
    }
}

// MARK: - 纪要问答 — per-meeting Q&A thread, persisted

struct QATurn: Identifiable, Codable {
    var id = UUID()
    let question: String
    var answer: String?
    enum CodingKeys: String, CodingKey { case question, answer }   // id is regenerated, not persisted
}

enum QAStore {
    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("AfterMeet/qa.json")
    }
    static func load() -> [String: [QATurn]] {
        guard let data = try? Data(contentsOf: fileURL),
              let m = try? JSONDecoder().decode([String: [QATurn]].self, from: data) else { return [:] }
        return m
    }
    static func save(_ m: [String: [QATurn]]) {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(m) { try? data.write(to: fileURL) }
    }
}

// MARK: - View model the detail / home screens render (real or sample)

struct MeetingVM: Identifiable {
    let id: String
    var title: String
    let badge: String
    let metaParts: [String]
    let metaAccent: String
    let summary: String
    let decisions: [Decision]
    let disputes: [Dispute]
    let nextAgenda: [String]
    let transcript: [TranscriptLine]
    let transcriptNote: String
    let dtodos: [DetailTodo]
    let dayChip: String
    let recentMeta: String
    let keyPoints: [String]
    let blocks: [NoteBlock]
    let rawTranscript: String      // full text, fed to 豆包 for Q&A
    var searchBlob: String = ""    // 预小写的检索索引（标题+摘要+逐字稿），免得每敲一键全量 lowercased
}

extension MeetingVM {
    /// Map refined todos → DetailTodo. Low confidence / no owner → 待认领 (宁可多问不可派错).
    static func mapTodos(_ ts: [RTodo]) -> [DetailTodo] {
        let palette = [Color(hex: "0075de"), Color(hex: "1f7a4c"), Color(hex: "d06a3a"),
                       Color(hex: "6c5c7a"), Color(hex: "005bab")]
        func colorFor(_ name: String) -> Color {
            let sum = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
            return palette[sum % palette.count]
        }
        return ts.enumerated().map { idx, t in
            // 豆包偶尔把 owner 写成字符串 "null"/"无"，一律当未指派
            let rawOwner = t.owner?.trimmingCharacters(in: .whitespaces)
            let owner: String? = {
                guard let o = rawOwner, !o.isEmpty,
                      !["null", "none", "无", "待定", "tbd", "n/a"].contains(o.lowercased())
                else { return nil }
                return o
            }()
            let unclaimed = (owner == nil) || (t.confidence?.lowercased() == "low")
            if unclaimed {
                return DetailTodo(id: idx + 1, owner: nil, initial: "?", color: Color(hex: "a86a1a"),
                                  text: t.text, due: t.due ?? "—", status: .unclaimed, orig: .unclaimed,
                                  note: "置信度低 · 未识别明确负责人")
            }
            let name = owner ?? ""
            return DetailTodo(id: idx + 1, owner: name, initial: String(name.prefix(1)),
                              color: colorFor(name), text: t.text, due: t.due ?? "—",
                              status: .pending, orig: .pending)
        }
    }

    init(real m: RealMeeting) {
        let mapped = MeetingVM.mapTodos(m.todos)

        var parts: [String] = []
        if let d = m.dateLabel, !d.isEmpty { parts.append(d) }
        if let dur = m.durationLabel, !dur.isEmpty { parts.append(dur) }
        if let p = m.participants { parts.append("\(p) 人参会") }
        if let o = m.organizer, !o.isEmpty { parts.append("组织者 \(o)") }

        self.id = m.meeting_id
        self.title = m.title
        self.badge = "妙记已生成"
        self.metaParts = parts
        self.metaAccent = "豆包基于逐字稿提炼"
        self.summary = m.summary
        self.keyPoints = m.keyPoints ?? []
        self.blocks = m.blocks ?? []
        self.decisions = m.decisions.enumerated().map { i, d in
            Decision(no: d.no ?? String(format: "%02d", i + 1), text: d.text)
        }
        self.disputes = m.disputes.map { Dispute(title: $0.title, body: $0.body) }
        self.nextAgenda = m.nextAgenda
        self.transcript = m.excerpts.map { TranscriptLine(time: $0.time ?? "", who: $0.who ?? "", text: $0.text) }
        self.rawTranscript = m.excerpts.map { $0.text }.joined(separator: "\n")
        self.transcriptNote = "妙记逐字稿 · 豆包提炼"
        self.dtodos = mapped
        self.dayChip = MeetingVM.dayChip(from: m.dateLabel)
        let people = m.participants.map { "\($0)人" } ?? ""
        self.recentMeta = [m.dateLabel ?? "", people, "\(m.todos.count) 条待办"]
            .filter { !$0.isEmpty }.joined(separator: " · ")
        self.searchBlob = "\(self.title) \(self.summary) \(self.rawTranscript)".lowercased()
    }

    /// Build a meeting from a locally-captured + refined live session.
    init(live note: RefinedNote, transcript: String, durationSec: Int, now: Date, title: String? = nil) {
        let df = DateFormatter()
        df.locale = Locale(identifier: "zh_CN")
        df.dateFormat = "M月d日 EEE"
        let dateStr = df.string(from: now)
        let dur = String(format: "%d:%02d", durationSec / 60, durationSec % 60)

        self.id = "live-\(Int(now.timeIntervalSince1970))"
        let userTitle = (title ?? "").trimmingCharacters(in: .whitespaces)
        self.title = !userTitle.isEmpty ? userTitle : (note.title.isEmpty ? "会中纪要" : note.title)
        self.badge = "本地转写"
        self.metaParts = [dateStr, "时长 \(dur)", "本地实时转写"]
        self.metaAccent = "音频未出网 · 端上转写"
        self.summary = note.summary ?? ""
        self.keyPoints = note.keyPoints ?? []
        self.blocks = note.blocks ?? []
        self.decisions = (note.decisions ?? []).enumerated().map { i, d in
            Decision(no: d.no ?? String(format: "%02d", i + 1), text: d.text)
        }
        self.disputes = (note.disputes ?? []).map { Dispute(title: $0.title, body: $0.body) }
        self.nextAgenda = note.nextAgenda ?? []
        let chunks = transcript
            .split(whereSeparator: { "。！？\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        self.transcript = chunks.prefix(40).map { TranscriptLine(time: "", who: "现场", text: $0) }
        self.rawTranscript = transcript
        self.transcriptNote = "本地转写 · \(transcript.count) 字"
        self.dtodos = MeetingVM.mapTodos(note.todos)
        self.dayChip = MeetingVM.dayChip(from: dateStr)
        self.recentMeta = [dateStr, "时长 \(dur)", "\(note.todos.count) 条待办"].joined(separator: " · ")
        self.searchBlob = "\(self.title) \(self.summary) \(transcript)".lowercased()
    }

    static func dayChip(from label: String?) -> String {
        guard let s = label else { return "·" }
        let nums = s.components(separatedBy: CharacterSet(charactersIn: "月日"))
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        return nums.count >= 2 ? "\(nums[0])/\(nums[1])" : "·"
    }

    /// Blocks to render in the detail screen: the model's bespoke layout, or — for notes captured
    /// before generative specs (sync.sh, sample, older live captures) — blocks synthesized from
    /// the flat fields so every meeting still renders through the generative renderer.
    var displayBlocks: [NoteBlock] {
        blocks.isEmpty
            ? MeetingVM.synthBlocks(summary: summary, keyPoints: keyPoints, decisions: decisions,
                                    disputes: disputes, nextAgenda: nextAgenda)
            : blocks
    }

    static func synthBlocks(summary: String, keyPoints: [String], decisions: [Decision],
                            disputes: [Dispute], nextAgenda: [String]) -> [NoteBlock] {
        var b: [NoteBlock] = []
        if !summary.isEmpty { b.append(NoteBlock(type: "summary", text: summary)) }
        if !keyPoints.isEmpty { b.append(NoteBlock(type: "keyPoints", items: keyPoints)) }
        if !decisions.isEmpty { b.append(NoteBlock(type: "decisions", items: decisions.map { "\($0.no)|\($0.text)" })) }
        if !disputes.isEmpty { b.append(NoteBlock(type: "disputes", items: disputes.map { "\($0.title)|\($0.body)" })) }
        if !nextAgenda.isEmpty { b.append(NoteBlock(type: "nextAgenda", items: nextAgenda)) }
        return b
    }

    // Fallback sample meeting (the original 周三产品评审会).
    static let sample = MeetingVM(
        id: "sample",
        title: "周三产品评审会",
        badge: "妙记已生成",
        metaParts: ["6月10日 周三 · 14:00–15:12", "7 人参会", "组织者 林涛"],
        metaAccent: "纪要送达用时 4 分 12 秒",
        summary: "这次评审定下 V2.3 优先打「会前追问」闭环，灰度先开 3 个内部团队。待办里有 2 条因负责人不明确，我已标为待认领 —— 宁可多问，不替你乱派。",
        decisions: [
            Decision(no: "01", text: "V2.3 优先打「会前追问」闭环，会后纪要次之 —— 资源向闭环倾斜。"),
            Decision(no: "02", text: "待办负责人遵循「宁可多问、不可派错」：低置信度一律不自动指派，走待认领。"),
            Decision(no: "03", text: "灰度范围先开 3 个内部团队，6 月 20 日前不扩量，先测确认率与闭环率基线。"),
        ],
        disputes: [
            Dispute(title: "周报是否做趋势图",
                    body: "林涛倾向克制、不堆图表；王凯认为需要闭环率趋势图。未达成共识，下次会拍板。"),
            Dispute(title: "会中提醒是否进 P1",
                    body: "取决于 vc-agent 灰度政策是否 GA。政策未定，本项挂起，不进本期排期。"),
        ],
        nextAgenda: ["灰度首周数据回看（确认率 / 闭环率基线）", "周报形态二选一 —— 做不做趋势图，拍板"],
        transcript: [
            TranscriptLine(time: "14:03", who: "林涛", text: "这次评审重点就一个：V2.3 到底先打哪个点。"),
            TranscriptLine(time: "14:05", who: "王凯", text: "数据上看，用户最容易流失在「收到纪要但没人跟」这一步，所以我倾向先做追问。"),
            TranscriptLine(time: "14:09", who: "陈默", text: "那追问卡公开转发要不要默认匿名？点名这事得想清楚，不然容易得罪人。"),
            TranscriptLine(time: "14:14", who: "林涛", text: "不默认匿名，但点不点名让用户自己拍板 —— 卡片上给个开关。"),
            TranscriptLine(time: "14:21", who: "高翔", text: "负责人映射我担心派错，建议低置信度统一走待认领。"),
        ],
        transcriptNote: "妙记 · 4,210 字",
        dtodos: DetailTodo.sample,
        dayChip: "6/10",
        recentMeta: "6/10 · 7人 · 6 条待办",
        keyPoints: [
            "「会前追问」排在「会后纪要」之前，是因为数据显示用户最容易流失在“收到纪要却没人跟进”这一步——优先级押在闭环而非记录。",
            "灰度只开 3 个内部团队、6/20 前不扩量，本质是先把确认率/闭环率基线测准，再谈规模。",
            "周报是否做趋势图悬而未决，背后是“克制信息密度”与“让闭环可量化”的取舍，下次需拍板。",
        ],
        blocks: [],
        rawTranscript: "林涛：这次评审重点就一个，V2.3 先打哪个点。王凯：用户最容易流失在“收到纪要但没人跟”这一步，所以先做追问。陈默：追问卡公开转发要不要默认匿名？林涛：不默认匿名，但点不点名让用户自己拍板。高翔：负责人映射我担心派错，建议低置信度统一走待认领。"
    )
}
