import Foundation

/// The豆包 refine output — same schema sync.sh writes, reusing RDecision/RTodo/RDispute.
struct RefinedNote: Codable {
    let title: String
    let todos: [RTodo]
    let blocks: [NoteBlock]?
    // Legacy / fallback fields — old stored notes & the sync.sh path still carry these; new
    // generative notes put everything in `blocks` and leave these nil.
    let summary: String?
    let keyPoints: [String]?
    let decisions: [RDecision]?
    let disputes: [RDispute]?
    let nextAgenda: [String]?

    enum CodingKeys: String, CodingKey { case title, todos, blocks, summary, keyPoints, decisions, disputes, nextAgenda }

    // 自定义 init(from:) 会压掉 memberwise init，工厂方法要用得补一个显式的
    init(title: String, todos: [RTodo], blocks: [NoteBlock]?,
         summary: String? = nil, keyPoints: [String]? = nil, decisions: [RDecision]? = nil,
         disputes: [RDispute]? = nil, nextAgenda: [String]? = nil) {
        self.title = title; self.todos = todos; self.blocks = blocks
        self.summary = summary; self.keyPoints = keyPoints; self.decisions = decisions
        self.disputes = disputes; self.nextAgenda = nextAgenda
    }

    /// 提炼失败时的兜底：录音必须入库（绝不整场丢弃），块里带 refineFailed 标记，
    /// 详情页据此给「重新生成」入口。标题保持"未命名会议"，打开详情时日历交叉比对会自动改名。
    static func processing() -> RefinedNote {
        RefinedNote(title: "未命名会议", todos: [],
                    blocks: [NoteBlock(type: "refinePending")])
    }

    static func failed(reason: String) -> RefinedNote {
        RefinedNote(title: "未命名会议", todos: [],
                    blocks: [NoteBlock(type: "refineFailed", text: reason)])
    }

    // Tolerant decode: the mini model sometimes emits a legacy field in the wrong shape (e.g.
    // nextAgenda as an object instead of [String]). Decode each defensively so one stray field
    // can't fail the whole note — these are only fallbacks; the real content lives in `blocks`.
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        title      = (try? c.decode(String.self, forKey: .title)) ?? "会中纪要"
        todos      = (try? c.decode([RTodo].self, forKey: .todos)) ?? []
        blocks     = try? c.decode([NoteBlock].self, forKey: .blocks)
        summary    = try? c.decode(String.self, forKey: .summary)
        keyPoints  = try? c.decode([String].self, forKey: .keyPoints)
        decisions  = try? c.decode([RDecision].self, forKey: .decisions)
        disputes   = try? c.decode([RDispute].self, forKey: .disputes)
        nextAgenda = try? c.decode([String].self, forKey: .nextAgenda)
    }
}

/// Siku 云的设备额度流：首启生成 siku-dev-<uuid>，带 X-Siku-App 头由 proxy 自动登记，
/// 默认每天 500 万 token 免费额度 —— 用户零配置，也不再内置 owner token。
enum SikuCloud {
    static let appSecret = "siku-app-ea047a048adabb1108df95b63757370a"
    static var deviceToken: String {
        let key = "sikuDeviceToken"
        if let t = UserDefaults.standard.string(forKey: key) { return t }
        let t = "siku-dev-\(UUID().uuidString.lowercased())"
        UserDefaults.standard.set(t, forKey: key)
        return t
    }
}

/// Calls siku-proxy (doubao) to refine a raw transcript into structured notes.
/// Goes through /usr/bin/curl with the IP+Host SNI workaround (zhiwenai.cc's TLS
/// gets reset domestically); curl is on the GUI app's default PATH, lark-cli is not.
enum Refine {
    static let ip = "14.103.38.223"
    static let host = "zhiwenai.cc"
    static let model = "doubao-seed-2-0-mini-260428"

    static let system = """
    你是给业务负责人做"生成式会议纪要"的资深参谋。读完逐字稿，按这场会的内容自己决定用哪些"积木"、怎么排，只输出严格 JSON(无 markdown、无多余文字)。目标：详尽、有深度、为这场会量身排版。

    **先在心里把逐字稿切成几个主题段，确保每段都在纪要里有体现，尤其别遗漏后半段——长会最容易漏掉后面的议题。纪要的详尽程度要匹配会议的信息量：内容多的长会，keyPoints/decisions 就充分展开(可到 6-12 条)；内容少的短会，就如实精简，别为凑数注水。**

    顶层:{"title":"具体到能一眼分辨是哪场会","todos":[{"text":"行动项","owner":"姓名或null","due":"M/D或null","confidence":"high或low"}],"blocks":[…有序积木…]}
    每个积木 = {"type":"X", …对应字段}。**积木里的 items 永远是“字符串数组”，多个子字段用 | 分隔，绝不写成对象数组**:
    - {"type":"summary","text":"通览全会的takeaway，覆盖每个主要议题，带关键数字；长会4-8句，短会1-2句"}（必放且在最前）
    - {"type":"stats","items":["指标名|5亿美金","…|…"]}（关键数字，有几个给几个）
    - {"type":"beforeAfter","before":"原方向|说明","after":"新方向|说明"}（方向转变/取舍，可多个）
    - {"type":"keyPoints","items":["深度要点1","要点2"]}（背景、数字背后的含义、风险、跨业务关联；要洞察别复述 summary；按会议信息量给足，长会覆盖全程各主题）
    - {"type":"decisions","items":["01|决策+为什么/代价/数字","02|…"]}（会上拍的板全列，别只挑头两个）
    - {"type":"disputes","items":["争议标题|立场A vs 立场B + 卡点 + 谁拍何时"]}
    - {"type":"timeline","items":["Q3|标签|详情"]}（落地节奏/路线图）
    - {"type":"quote","text":"一句关键原话","who":"谁"}
    - {"type":"nextAgenda","items":["下次议题"]}（仅逐字稿真提到）
    红线：积木的 items 一律字符串数组、用 | 分隔子字段，绝不写成 [{...}]。逐字稿是口语ASR转写，有识别错误和闲聊，抓真实业务信号、忽略噪音。todos 只在逐字稿明确指派才填 owner，否则 owner=null 且 confidence=low。数字/专名优先保留，拿不准别编。只输出 JSON。
    """

    static let dailySystem = """
    你是给业务负责人做"每日会议综述"的参谋。下面是他某一天开的所有会的纪要要点，把当天所有会综合成一份 digest，只输出严格 JSON(无 markdown)。
    顶层:{"title":"X月X日 · N场会综述","todos":[],"blocks":[…有序积木…]}
    积木(items 永远是字符串数组、| 分隔，绝不对象数组):
    - {"type":"summary","text":"这一天整体在推什么、最重要的 2-4 件事，带数字"}（必放最前）
    - {"type":"stats","items":["指标|数值"]}（当天关键数字，可选）
    - {"type":"keyPoints","items":["跨会洞察/共性/值得注意的1","2"]}（3-5条，要综合提炼，不要把各会摘要罗列堆叠）
    - {"type":"decisions","items":["01|当天关键决策","02|…"]}（跨会汇总去重）
    - {"type":"disputes","items":["待拍板的|说明"]}
    - {"type":"timeline","items":["时间|事项|详情"]}（如有明显安排）
    红线:items 一律字符串数组、用 | 分隔，绝不写 [{...}]。要"综合"成一天的全局视角。只输出 JSON。
    """

    static let mdSummarySystem = """
    你是给业务负责人写"完整版会议纪要"的资深参谋。读完逐字稿，直接输出一篇 Markdown 格式的纪要正文——不要输出 JSON，不要用代码块包裹，不要加"好的""以下是"这类开场白。

    篇幅 1000~5000 字（中文），按会议信息量决定——内容单薄的会议如实精简（不低于1000字），议题多、信息量大的长会可以写到4000~5000字。核心要求是**详实但不遗漏**：逐字稿里提到的每个议题、每个决策、每个数字都要在纪要里有体现，尤其是长会容易漏掉的后半段；写之前先在心里把逐字稿按主题切几段，逐段确认没有漏。同时要"抽象"——不是逐句转录或流水账，而是把每段内容提炼、综合成有信息密度的叙述，别为了显得详实而堆砌口语原话或无意义的过程细节。

    用 Markdown 二级标题（##）分段，段内以自然语言叙述为主，要点用 - 或数字列表组织，关键结论/数字可以**加粗**。参考结构（按会议实际内容取舍，不必每节都写）：## 概览、## 关键讨论、## 决策、## 待办与分工、## 风险与分歧、## 下一步。

    只依据逐字稿内容，数字/人名/结论优先原样保留；逐字稿是口语 ASR 转写，识别错误和语气词可以顺一下，但不能编造没发生的事。
    """

    /// 长逐字稿的第一阶段只做事实摘录：每段都保留议题、数字、决策、分歧和待办，供最终归并。
    /// 限制篇幅，避免分段结果本身再次撑爆最终上下文。
    private static let mdChunkSystem = """
    你在为一篇完整版会议纪要做分段事实摘录。只依据给出的这一段逐字稿，用 Markdown 要点完整记录：
    议题与背景、关键观点及理由、所有数字/专名、明确决策、分歧、风险、待办与负责人。不要写开场白，
    不要臆测其他片段内容；尽量控制在 1800 个中文字以内，但不能为了短而丢掉硬信息。
    """

    private static let mdMergeSystem = """
    把下面多段会议事实摘录合并成一份更紧凑的事实底稿。去掉重复，保留每个议题、数字、决策、分歧、
    风险和待办；不要写泛泛总结，不要添加原文没有的信息。输出 Markdown，控制在 5000 个中文字以内。
    """

    /// 完整版 Markdown 纪要 —— 独立于结构化积木的另一种呈现，供直接转发/存档。
    static func markdownSummary(from transcript: String) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let raw = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { throw err("逐字稿为空") }

            // 短会直接使用全文；长会先逐段提取事实，再按上下文容量做层级归并，绝不只截前缀。
            if raw.count <= 24_000 {
                return try retryText(system: mdSummarySystem,
                                     user: "会议逐字稿如下：\n\n" + raw,
                                     maxTokens: 10_000)
            }

            let sourceChunks = splitByCharacterCount(raw, limit: 12_000)
            var materials: [String] = []
            for (i, chunk) in sourceChunks.enumerated() {
                let note = try retryText(
                    system: mdChunkSystem,
                    user: "这是第 \(i + 1)/\(sourceChunks.count) 段逐字稿：\n\n\(chunk)",
                    maxTokens: 3_000)
                materials.append(note)
            }

            // 极长会议可能产生很多段摘录；分组压缩到最终调用能完整接收的规模。
            while materials.joined(separator: "\n\n").count > 24_000, materials.count > 1 {
                let groups = groupByCharacterCount(materials, limit: 20_000)
                var merged: [String] = []
                for (i, group) in groups.enumerated() {
                    let body = group.enumerated().map { "### 子段 \($0.offset + 1)\n\($0.element)" }
                        .joined(separator: "\n\n")
                    merged.append(try retryText(
                        system: mdMergeSystem,
                        user: "这是第 \(i + 1)/\(groups.count) 组事实摘录：\n\n\(body)",
                        maxTokens: 5_000))
                }
                materials = merged
            }

            let evidence = materials.enumerated().map { "### 逐字稿分段 \($0.offset + 1)\n\($0.element)" }
                .joined(separator: "\n\n")
            return try retryText(
                system: mdSummarySystem,
                user: "下面是覆盖整场会议、按原始顺序整理的逐段事实摘录。请据此写完整版纪要：\n\n" + evidence,
                maxTokens: 10_000)
        }.value
    }

    private static func retryText(system: String, user: String, maxTokens: Int) throws -> String {
        var lastError = "生成失败"
        for _ in 1...2 {
            do {
                let text = try chatOnce(system: system, user: user, maxTokens: maxTokens)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { return text }
                lastError = "生成结果为空"
            } catch { lastError = (error as NSError).localizedDescription }
        }
        throw err(lastError)
    }

    private static func splitByCharacterCount(_ text: String, limit: Int) -> [String] {
        guard text.count > limit else { return [text] }
        var chunks: [String] = []
        var start = text.startIndex
        while start < text.endIndex {
            let end = text.index(start, offsetBy: limit, limitedBy: text.endIndex) ?? text.endIndex
            chunks.append(String(text[start..<end]))
            start = end
        }
        return chunks
    }

    private static func groupByCharacterCount(_ items: [String], limit: Int) -> [[String]] {
        var groups: [[String]] = [], current: [String] = []
        var count = 0
        for item in items {
            if !current.isEmpty, count + item.count > limit {
                groups.append(current); current = []; count = 0
            }
            current.append(item); count += item.count
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }

    static func note(from transcript: String) async throws -> RefinedNote {
        try await Task.detached(priority: .userInitiated) {
            try runSync(system: system, user: "会议逐字稿如下:\n\n" + transcript)
        }.value
    }

    /// Synthesize one day's meetings into a single digest — same generative-block schema, same renderer.
    static func digest(from dayInput: String) async throws -> RefinedNote {
        try await Task.detached(priority: .userInitiated) {
            try runSync(system: dailySystem, user: dayInput)
        }.value
    }

    static let qaSystem = """
    你是这场会议的分析伙伴，和用户（会议负责人）基于逐字稿深入讨论这场会。分两种情况：

    - 事实类问题（谁说了什么、数字、结论、有没有提到某事）：只用逐字稿里的信息，能引原话/数字就引；确实没有就直说没提到，并补一句逐字稿里最接近的相关内容，别只甩一句"没提到"。
    - 分析/评价/建议/洞见类问题（这会开得怎么样、谁的观点更站得住、哪里没聊透、下一步怎么办、有什么insights）：不必逐句落回逐字稿证据，可以基于逐字稿内容自由联想、延伸、给判断，也可以带一点你自己的行业经验和猜测；想引用逐字稿依据就引，没有依据也可以直接说这是你的联想，不用为了自证而每句话都找补一个"证据"。

    这是多轮对话，追问时结合上文理解所指（"你自己判断呢"="对上一个问题给出你的判断"）。中文，直接有观点，别客套，别写"作为AI"式免责。回答里不要用markdown格式（不要标题、加粗、列表符号、代码块），就用自然的口语段落，像聊天一样说话。
    """

    /// Free-text Q&A grounded in one meeting's transcript — returns the answer text (not JSON).
    /// history = 此前的完整问答轮（多轮追问全靠它），只带最近几轮控 token。
    static func ask(transcript: String, history: [(q: String, a: String)] = [],
                    question: String) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            var user = "【会议逐字稿】\n\(String(transcript.prefix(24000)))\n\n"
            if !history.isEmpty {
                user += "【此前对话】\n"
                for t in history.suffix(6) {
                    user += "问：\(t.q)\n答：\(String(t.a.prefix(1200)))\n"
                }
                user += "\n"
            }
            user += "【本轮问题】\(question)"
            var lastError = "回答失败"
            for _ in 1...2 {
                do {
                    let a = try callDoubao(system: qaSystem, user: user).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !a.isEmpty { return a }
                } catch { lastError = (error as NSError).localizedDescription }
            }
            throw err(lastError)
        }.value
    }

    /// 原始 JSON 文本出口（FeishuSync 用它按自己的 schema 解码），带解析重试。
    static func rawJSON(system: String, user: String) async throws -> String {
        try await Task.detached(priority: .utility) {
            var lastError = "提炼服务无响应"
            for _ in 1...3 {
                do {
                    let content = try callDoubao(system: system, user: user)
                    if let d = content.data(using: .utf8),
                       (try? JSONSerialization.jsonObject(with: d)) != nil { return content }
                    let repaired = repairJSON(content)
                    if let d = repaired.data(using: .utf8),
                       (try? JSONSerialization.jsonObject(with: d)) != nil { return repaired }
                    lastError = "提炼结果不是合法 JSON"
                } catch { lastError = (error as NSError).localizedDescription }
            }
            throw err(lastError)
        }.value
    }

    private static func runSync(system: String, user: String) throws -> RefinedNote {
        var lastError = "提炼结果解析失败"
        for attempt in 1...3 {
            let content: String
            do { content = try callDoubao(system: system, user: user) }
            catch { lastError = (error as NSError).localizedDescription; continue }  // no response → retry
            if let note = decodeNote(content) { return note }
            lastError = "提炼结果解析失败（已重试 \(attempt)/3）"                          // bad JSON → retry the call
        }
        throw err(lastError)
    }

    /// One HTTP round-trip → the model's cleaned text (markdown fences stripped). Throws on no response.
    private static func callDoubao(system: String, user: String) throws -> String {
        try chatOnce(system: system, user: user, maxTokens: 4000)
    }

    /// 唯一 LLM 出口：内置服务（设备额度）或 BYOK（用户自己的 OpenAI 兼容端点）。
    static func chatOnce(system: String, user: String, maxTokens: Int) throws -> String {
        let byok = AIBackend.isBYOK
        let payload: [String: Any] = [
            "model": byok ? AIBackend.model : model,
            "temperature": 0.2,
            "max_tokens": maxTokens,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        if byok {
            // 标准 TLS，不做证书豁免；Key 来自钥匙串
            proc.arguments = [
                "-s", "--max-time", "180",
                AIBackend.chatURL,
                "-H", "Authorization: Bearer \(AIBackend.apiKey ?? "")",
                "-H", "Content-Type: application/json",
                "--data-binary", "@-",
            ]
        } else {
            proc.arguments = [
                "-sk", "--max-time", "180",
                "https://\(ip)/v1/chat/completions",
                "-H", "Host: \(host)",
                "-H", "Authorization: Bearer \(SikuCloud.deviceToken)",
                "-H", "X-Siku-App: \(SikuCloud.appSecret)",
                "-H", "Content-Type: application/json",
                "--data-binary", "@-",
            ]
        }
        let stdin = Pipe(), stdout = Pipe()
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = FileHandle.nullDevice
        try proc.run()
        // curl 早退时管道读端关闭：write 会触发 SIGPIPE/NSFileHandle 异常直接崩 app ——
        // 用 throwing API 接住，写失败按"无响应"走重试。
        do { try stdin.fileHandleForWriting.write(contentsOf: body) } catch {}
        try? stdin.fileHandleForWriting.close()
        let out = stdout.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()

        guard let resp = try? JSONSerialization.jsonObject(with: out) as? [String: Any] else {
            throw err(AIBackend.isBYOK ? "API 无响应（检查 Base URL 与网络）" : "提炼服务无响应（检查网络）")
        }
        if let apiErr = resp["error"] as? [String: Any], let m = apiErr["message"] as? String {
            throw err("API 错误：\(String(m.prefix(120)))")
        }
        guard let choices = resp["choices"] as? [[String: Any]],
              let msg = choices.first?["message"] as? [String: Any],
              let content = msg["content"] as? String
        else { throw err("响应格式异常") }

        return content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Decode the note, repairing the model's most common JSON sin (unescaped quotes / raw
    /// control chars inside string values) on a second pass.
    private static func decodeNote(_ content: String) -> RefinedNote? {
        let dec = JSONDecoder()
        if let d = content.data(using: .utf8), let n = try? dec.decode(RefinedNote.self, from: d) { return n }
        let repaired = repairJSON(content)
        if let d = repaired.data(using: .utf8), let n = try? dec.decode(RefinedNote.self, from: d) { return n }
        return nil
    }

    /// Best-effort (not a full parser): escape a stray ASCII `"` that sits *inside* a string value
    /// — detected when the next non-space char isn't a JSON delimiter — plus raw newlines/tabs.
    private static func repairJSON(_ s: String) -> String {
        var out = ""
        var inString = false, escaped = false
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if escaped { out.append(c); escaped = false; i += 1; continue }
            if c == "\\" { out.append(c); escaped = true; i += 1; continue }
            if inString, c == "\n" { out.append("\\n"); i += 1; continue }
            if inString, c == "\r" { out.append("\\r"); i += 1; continue }
            if inString, c == "\t" { out.append("\\t"); i += 1; continue }
            if c == "\"" {
                if !inString { inString = true; out.append(c); i += 1; continue }
                var j = i + 1
                while j < chars.count, chars[j] == " " || chars[j] == "\n" || chars[j] == "\r" || chars[j] == "\t" { j += 1 }
                let next: Character = j < chars.count ? chars[j] : " "
                if next == "," || next == "}" || next == "]" || next == ":" {
                    inString = false; out.append(c)              // genuine closing quote
                } else {
                    out.append("\\\"")                            // stray inner quote → escape it
                }
                i += 1; continue
            }
            out.append(c); i += 1
        }
        return out
    }

    private static func err(_ m: String) -> NSError {
        NSError(domain: "Refine", code: 1, userInfo: [NSLocalizedDescriptionKey: m])
    }
}
