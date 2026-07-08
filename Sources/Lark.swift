import Foundation
import AppKit

/// 飞书侧的真实写入/查询 —— 全部经 lark-cli（用户身份），app 里不落任何凭证。
/// 所有调用都是 best-effort：CLI 不在、scope 不够都走 LarkError，由调用方给用户诚实反馈。
enum Lark {
    static var cli: String { ToolPath.resolve("lark-cli") ?? "/opt/homebrew/bin/lark-cli" }
    static var available: Bool { ToolPath.resolve("lark-cli") != nil }

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

    // MARK: - 日历：日程读取（会前追问 ground truth / 时间戳猜会议名）

    struct CalEvent: Codable { let summary: String; let start: Date; let end: Date }
    struct UpcomingEvent { let summary: String; let dateLabel: String; let start: Date }

    /// 一段时间内的日程（过滤 placeholder / cowork / 全天占位）。
    static func events(from: Date, to: Date) async -> [CalEvent] {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let json = await runJSON(["calendar", "+agenda",
                                        "--start", f.string(from: from),
                                        "--end", f.string(from: to)], timeout: 45),
              let items = json["data"] as? [[String: Any]] else { return [] }
        let iso = ISO8601DateFormatter()
        return items.compactMap { it in
            guard let summary = (it["summary"] as? String)?.trimmingCharacters(in: .whitespaces),
                  !summary.isEmpty else { return nil }
            let low = summary.lowercased()
            if low.contains("placeholder") || low.contains("cowork") || low.contains("co-work") { return nil }
            guard let st = ((it["start_time"] as? [String: Any])?["datetime"] as? String).flatMap({ iso.date(from: $0) }),
                  let et = ((it["end_time"] as? [String: Any])?["datetime"] as? String).flatMap({ iso.date(from: $0) })
            else { return nil }
            if et.timeIntervalSince(st) > 4 * 3600 { return nil }   // 超长占位块不算一场会
            return CalEvent(summary: summary, start: st, end: et)
        }
    }

    static func upcomingEvents(days: Int = 7) async -> [UpcomingEvent] {
        let out = DateFormatter(); out.locale = Locale(identifier: "zh_CN"); out.dateFormat = "M月d日 EEE HH:mm"
        var seen = Set<String>()
        var upcoming: [UpcomingEvent] = []
        for ev in await events(from: Date(), to: Date().addingTimeInterval(Double(days) * 86400)) {
            guard ev.start > Date(), !seen.contains(ev.summary) else { continue }
            seen.insert(ev.summary)
            upcoming.append(UpcomingEvent(summary: ev.summary, dateLabel: out.string(from: ev.start), start: ev.start))
        }
        return upcoming
    }

    /// 时间戳猜会议：录音区间 [start, start+dur] 和日历日程求重叠，
    /// 重叠 ≥5 分钟（或录音一半以上）才算，按重叠时长降序返回全部候选。
    static func eventsOverlapping(start recStart: Date, durationSec: Int) async -> [CalEvent] {
        let recEnd = recStart.addingTimeInterval(Double(max(durationSec, 60)))
        let dayEvents = await events(from: recStart.addingTimeInterval(-86400),
                                     to: recEnd.addingTimeInterval(86400))
        let minOverlap = min(300.0, Double(durationSec) * 0.5)
        return dayEvents
            .map { ($0, min($0.end, recEnd).timeIntervalSince(max($0.start, recStart))) }
            .filter { $0.1 >= minOverlap }
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
    }

    /// 打开飞书日历（applink 拉起客户端，落到指定日期的日视图）。
    static func openCalendar(at date: Date) {
        let ts = Int(date.timeIntervalSince1970)
        if let url = URL(string: "https://applink.feishu.cn/client/calendar/view?type=day&date=\(ts)") {
            NSWorkspace.shared.open(url)
        }
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
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice     // 没人读的 stderr 管道满了会憋死进程

            // 单一 reader 边跑边读（输出可达几百 KB，超 64KB 管道缓冲）；
            // EOF（availableData 为空）时发信号 —— 不再用 readToEnd 收尾，
            // 避免"terminate 后写端不关、readToEnd 永久阻塞"把调用方卡死。
            var buf = Data()
            let lock = NSLock()
            let eof = DispatchSemaphore(value: 0)
            out.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                if d.isEmpty {
                    h.readabilityHandler = nil
                    eof.signal()
                } else {
                    lock.lock(); buf.append(d); lock.unlock()
                }
            }

            do { try p.run() } catch {
                out.fileHandleForReading.readabilityHandler = nil
                return nil
            }
            let deadline = Date().addingTimeInterval(timeout)
            while p.isRunning && Date() < deadline { usleep(100_000) }
            if p.isRunning {
                p.terminate()
                let killAt = Date().addingTimeInterval(2)
                while p.isRunning && Date() < killAt { usleep(50_000) }
                if p.isRunning { kill(p.processIdentifier, SIGKILL) }   // 不理 SIGTERM 的直接杀
            }
            // 等 reader 收到 EOF（最多 2s，防止孤儿子进程占着写端不放）
            _ = eof.wait(timeout: .now() + 2)
            out.fileHandleForReading.readabilityHandler = nil
            lock.lock(); let data = buf; lock.unlock()
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }.value
    }
}

// MARK: - 已建任务的台账：meetingID|todoID → 任务 guid，防止重复建卡

enum TaskLinkStore {
    static func load() -> [String: String] {
        DB.shared.dictAll("task_links", keyCol: "key", valCol: "guid")
    }
    static func save(_ m: [String: String]) {
        for (k, v) in m { DB.shared.setRow("task_links", keyCol: "key", valCol: "guid", key: k, value: v) }
    }
}
