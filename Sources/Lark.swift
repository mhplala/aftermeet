import Foundation

/// 飞书侧的真实写入/查询 —— 全部经 lark-cli（用户身份），app 里不落任何凭证。
/// 所有调用都是 best-effort：CLI 不在、scope 不够都走 LarkError，由调用方给用户诚实反馈。
enum Lark {
    static let cli = "/opt/homebrew/bin/lark-cli"
    static var available: Bool { FileManager.default.isExecutableFile(atPath: cli) }

    struct LarkError: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: - 自己是谁（问候语 / 认领用），一次拉取全程缓存

    struct Me { let name: String; let openID: String }
    private static var cachedMe: Me?

    static func me() async -> Me? {
        if let m = cachedMe { return m }
        guard let json = await runJSON(["contact", "+get-user"]),
              let data = (json["data"] as? [String: Any])?["user"] as? [String: Any],
              let name = data["name"] as? String,
              let openID = data["open_id"] as? String else { return nil }
        let m = Me(name: name, openID: openID)
        cachedMe = m
        return m
    }

    // MARK: - 姓名 → open_id（只认精确同名，宁可不指派不可派错）

    private static var nameCache: [String: String?] = [:]

    static func resolveOpenID(name: String) async -> String? {
        if let hit = nameCache[name] { return hit }
        var openID: String? = nil
        if let json = await runJSON(["contact", "+search-user", "--query", name, "--page-size", "10"]),
           let users = (json["data"] as? [String: Any])?["users"] as? [[String: Any]] {
            let exact = users.filter { ($0["name"] as? String) == name }
            if exact.count == 1 { openID = exact[0]["open_id"] as? String }   // 多个同名 → 不敢指派
        }
        nameCache[name] = openID
        return openID
    }

    // MARK: - 建任务

    struct CreatedTask { let guid: String; let url: String }

    static func createTask(summary: String, description: String, due: String?,
                           assigneeOpenID: String?) async throws -> CreatedTask {
        var args = ["task", "+create", "--summary", summary, "--description", description]
        if let due, let iso = isoDate(fromMonthDay: due) { args += ["--due", iso] }
        if let assigneeOpenID { args += ["--assignee", assigneeOpenID] }
        guard let json = await runJSON(args) else { throw LarkError(message: "lark-cli 无响应") }
        if let ok = json["ok"] as? Bool, ok,
           let data = json["data"] as? [String: Any],
           let guid = data["guid"] as? String {
            return CreatedTask(guid: guid, url: data["url"] as? String ?? "")
        }
        throw LarkError(message: errorMessage(json))
    }

    // MARK: - 群搜索 + 发消息（转发到群）

    struct Chat: Identifiable { let id: String; let name: String }

    static func searchChats(query: String) async -> [Chat] {
        guard let json = await runJSON(["im", "+chat-search", "--query", query, "--page-size", "8"]),
              let items = (json["data"] as? [String: Any])?["items"] as? [[String: Any]] else { return [] }
        return items.compactMap { it in
            guard let id = it["chat_id"] as? String, let name = it["name"] as? String else { return nil }
            return Chat(id: id, name: name)
        }
    }

    static func sendMarkdown(chatID: String, markdown: String) async throws {
        let args = ["im", "+messages-send", "--chat-id", chatID, "--markdown", markdown]
        guard let json = await runJSON(args) else { throw LarkError(message: "lark-cli 无响应") }
        guard let ok = json["ok"] as? Bool, ok else { throw LarkError(message: errorMessage(json)) }
    }

    /// im 发消息需要 im:message.send_as_user scope；缺了就把授权 URL 打开让用户点一下。
    static func isMissingScope(_ error: Error) -> Bool {
        (error as? LarkError)?.message.contains("missing_scope") == true
        || (error as? LarkError)?.message.contains("im:message") == true
    }

    // MARK: - 底座

    private static func errorMessage(_ json: [String: Any]) -> String {
        guard let err = json["error"] as? [String: Any] else { return "未知错误" }
        let sub = err["subtype"] as? String ?? ""
        let msg = err["message"] as? String ?? "未知错误"
        return sub == "missing_scope" ? "missing_scope: \(msg)" : msg
    }

    /// "6/13"（也接受 6-13 / 06/13）→ 今年的 ISO 日期；跨年（12 月建 1 月的任务）自动进位。
    static func isoDate(fromMonthDay s: String) -> String? {
        let nums = s.components(separatedBy: CharacterSet(charactersIn: "/-月日 "))
            .compactMap { Int($0) }
        guard nums.count >= 2, (1...12).contains(nums[0]), (1...31).contains(nums[1]) else { return nil }
        let cal = Calendar.current
        var comp = cal.dateComponents([.year], from: Date())
        comp.month = nums[0]; comp.day = nums[1]
        guard let d0 = cal.date(from: comp) else { return nil }
        // 已经过去超过半年的“到期日”多半是明年的（如 12 月说“1/5 前”）
        let d = d0.timeIntervalSinceNow < -180 * 86400 ? cal.date(byAdding: .year, value: 1, to: d0)! : d0
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    static func runJSON(_ args: [String], timeout: TimeInterval = 30) async -> [String: Any]? {
        await Task.detached(priority: .userInitiated) { () -> [String: Any]? in
            guard available else { return nil }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: cli)
            p.arguments = args + ["--format", "json"]
            let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
            do { try p.run() } catch { return nil }
            let deadline = Date().addingTimeInterval(timeout)
            while p.isRunning && Date() < deadline { usleep(100_000) }
            if p.isRunning { p.terminate() }
            let d = out.fileHandleForReading.readDataToEndOfFile()
            return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
        }.value
    }
}

// MARK: - 已建任务的台账：meetingID|todoID → 任务 guid，防止重复建卡

enum TaskLinkStore {
    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("AfterMeet/task-links.json")
    }
    static func load() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
              let m = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return m
    }
    static func save(_ m: [String: String]) {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(m) { try? data.write(to: fileURL) }
    }
}
