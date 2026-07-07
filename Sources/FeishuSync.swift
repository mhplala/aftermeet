import Foundation

/// 会后自动同步 —— sync.sh 的原生替身，跑在 app 里。
/// 轮询飞书（事件推送 vc.note.generated_v1 需要控制台订阅，未开通前用轮询兜底）：
/// vc +search → vc +notes（逐字稿 token）→ docs +fetch → 豆包提炼 → 并入 meetings.json。
@MainActor
final class FeishuSync: ObservableObject {
    @Published var syncing = false
    @Published var lastSyncLabel = ""

    private var timer: Timer?
    var onNewMeetings: (([RealMeeting]) -> Void)?

    static let syncSystem = """
    你是会议纪要提炼助手。基于会议逐字稿(含说话人 user-name 与时间戳)独立分析，输出严格 JSON(不要 markdown 代码块、不要多余文字)。Schema:
    {
     "title":"会议标题",
     "dateLabel":"如 6月12日 周五（从逐字稿头部会议时间提取）",
     "durationLabel":"如 17:30–18:24",
     "participants":整数(逐字稿里出现的不同说话人数量),
     "organizer":"组织者姓名或null",
     "summary":"一段话客观摘要，中文，不超过120字",
     "decisions":[{"no":"01","text":"明确达成的结论/决策"}],
     "todos":[{"text":"行动项","owner":"姓名或null","due":"M/D或Q3等或null","confidence":"high或low"}],
     "disputes":[{"title":"分歧/未决项","body":"说明"}],
     "nextAgenda":["建议下次议题"],
     "excerpts":[{"time":"HH:MM","who":"说话人","text":"代表性原话"}]
    }
    规则：负责人只有逐字稿明确指派时才填 owner，否则 owner=null 且 confidence=low(宁可多问不可派错)。decisions/disputes 没有就空数组。excerpts 选 4-6 条能体现讨论的关键原话。红线：基于逐字稿本身分析，不要照搬已有 AI 纪要。只输出 JSON。
    """

    /// 启动：先来一次，之后每 15 分钟扫一轮（会后纪要生成通常在会议结束后几分钟内）。
    func start() {
        guard Lark.available else { return }
        Task { await sync() }
        timer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.sync() }
        }
    }

    /// 扫最近 14 天里 app 还没见过的会，逐个提炼后逐条入库（重活全在后台线程）。
    func sync() async {
        guard !syncing, Lark.available else { return }
        syncing = true
        defer {
            syncing = false
            let f = DateFormatter(); f.dateFormat = "HH:mm"
            lastSyncLabel = "上次同步 \(f.string(from: Date()))"
        }

        let fresh = await Task.detached(priority: .utility) { () -> [RealMeeting] in
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            let start = f.string(from: Date().addingTimeInterval(-14 * 86400))
            let end = f.string(from: Date().addingTimeInterval(86400))

            guard let search = await Lark.runJSON(["vc", "+search", "--start", start, "--end", end], timeout: 60),
                  let items = (search["data"] as? [String: Any])?["items"] as? [[String: Any]] else { return [] }

            let known = Set(RealData.load().map { $0.meeting_id })
            var out: [RealMeeting] = []
            for it in items {
                guard let mid = it["id"] as? String, !known.contains(mid) else { continue }
                guard let notes = await Lark.runJSON(["vc", "+notes", "--meeting-ids", mid], timeout: 60),
                      let list = (notes["data"] as? [String: Any])?["notes"] as? [[String: Any]],
                      let token = list.first?["verbatim_doc_token"] as? String, !token.isEmpty else { continue }
                guard let doc = await Lark.runJSON(["docs", "+fetch", "--api-version", "v2",
                                                    "--doc", token, "--doc-format", "markdown"], timeout: 120),
                      let content = ((doc["data"] as? [String: Any])?["document"] as? [String: Any])?["content"] as? String,
                      content.count >= 400 else { continue }
                guard let raw = try? await Refine.rawJSON(system: FeishuSync.syncSystem,
                                                          user: "会议逐字稿如下：\n\n" + content),
                      let data = raw.data(using: .utf8),
                      var obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
                obj["meeting_id"] = mid
                guard let merged = try? JSONSerialization.data(withJSONObject: obj),
                      let m = try? JSONDecoder().decode(RealMeeting.self, from: merged) else { continue }
                if RealData.upsert(m) { out.append(m) }        // 逐条入库；失败的不进列表
            }
            return out
        }.value

        guard !fresh.isEmpty else { return }
        onNewMeetings?(fresh)
    }

}
