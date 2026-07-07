import Foundation
import SQLite3

/// 本地存储底座 —— 单文件 SQLite（WAL，崩溃安全、按行写入）+ FTS5 全文索引。
/// 替代原来的 6 个 JSON 文件：每条会议一行（payload 仍是 JSON，沿用现有容错解码器），
/// 追加一场会 = 插一行，不再整文件重写；首启自动从旧 JSON 迁移，旧文件原地保留作备份。
final class DB {
    static let shared = DB()

    private var handle: OpaquePointer?
    private let q = DispatchQueue(label: "aftermeet.db")   // 串行队列，所有访问排队
    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AfterMeet")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("aftermeet.db")
    }

    private init() {
        q.sync {
            guard sqlite3_open(Self.fileURL.path, &handle) == SQLITE_OK else {
                handle = nil
                return
            }
            execLocked("PRAGMA journal_mode=WAL")
            execLocked("PRAGMA synchronous=NORMAL")
            execLocked("PRAGMA busy_timeout=3000")
            execLocked("""
                CREATE TABLE IF NOT EXISTS meetings(
                    id TEXT PRIMARY KEY,
                    kind TEXT NOT NULL,          -- 'live' | 'feishu'
                    sort_ts REAL NOT NULL DEFAULT 0,
                    payload TEXT NOT NULL
                )
                """)
            execLocked("""
                CREATE VIRTUAL TABLE IF NOT EXISTS meetings_fts
                USING fts5(id UNINDEXED, title, summary, transcript, tokenize='trigram')
                """)
            execLocked("CREATE TABLE IF NOT EXISTS daily(day TEXT PRIMARY KEY, blocks TEXT NOT NULL)")
            execLocked("CREATE TABLE IF NOT EXISTS qa(meeting_id TEXT PRIMARY KEY, turns TEXT NOT NULL)")
            execLocked("CREATE TABLE IF NOT EXISTS task_links(key TEXT PRIMARY KEY, guid TEXT NOT NULL)")
            execLocked("CREATE TABLE IF NOT EXISTS kv(key TEXT PRIMARY KEY, value TEXT NOT NULL)")
        }
        migrateFromJSONIfNeeded()
    }

    // MARK: - 底层（都在 q 上）

    @discardableResult
    private func execLocked(_ sql: String) -> Bool {
        guard let handle else { return false }
        return sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK
    }

    /// 预编译 + 绑定 + 执行（无结果集）。binds 支持 String / Double / Int / nil。
    private func runLocked(_ sql: String, _ binds: [Any?] = []) {
        guard let handle else { return }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, binds)
        sqlite3_step(stmt)
    }

    /// 查询：每行回调各列文本（NULL → nil）。
    private func queryLocked(_ sql: String, _ binds: [Any?] = [], row: ([String?]) -> Void) {
        guard let handle else { return }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, binds)
        let n = sqlite3_column_count(stmt)
        while sqlite3_step(stmt) == SQLITE_ROW {
            var cols: [String?] = []
            for i in 0..<n {
                if let c = sqlite3_column_text(stmt, i) { cols.append(String(cString: c)) }
                else { cols.append(nil) }
            }
            row(cols)
        }
    }

    private func bind(_ stmt: OpaquePointer?, _ binds: [Any?]) {
        for (i, v) in binds.enumerated() {
            let idx = Int32(i + 1)
            switch v {
            case let s as String: sqlite3_bind_text(stmt, idx, s, -1, SQLITE_TRANSIENT)
            case let d as Double: sqlite3_bind_double(stmt, idx, d)
            case let n as Int:    sqlite3_bind_int64(stmt, idx, Int64(n))
            default:              sqlite3_bind_null(stmt, idx)
            }
        }
    }

    // MARK: - 会议（payload = 原 JSON 结构，容错解码逻辑不变）

    struct FTSDoc { let title: String; let summary: String; let transcript: String }

    func upsertMeeting(id: String, kind: String, sortTs: Double, payload: String, fts: FTSDoc) {
        q.sync {
            execLocked("BEGIN")
            runLocked("INSERT OR REPLACE INTO meetings(id,kind,sort_ts,payload) VALUES(?,?,?,?)",
                      [id, kind, sortTs, payload])
            runLocked("DELETE FROM meetings_fts WHERE id=?", [id])
            runLocked("INSERT INTO meetings_fts(id,title,summary,transcript) VALUES(?,?,?,?)",
                      [id, fts.title, fts.summary, fts.transcript])
            execLocked("COMMIT")
        }
    }

    func meetingPayloads(kind: String) -> [(id: String, payload: String)] {
        var out: [(String, String)] = []
        q.sync {
            queryLocked("SELECT id,payload FROM meetings WHERE kind=? ORDER BY sort_ts DESC, rowid ASC", [kind]) {
                if let id = $0[0], let p = $0[1] { out.append((id, p)) }
            }
        }
        return out
    }

    /// 全量替换某一类会议（飞书同步用：语义 = 写整份 meetings.json）。
    func replaceMeetings(kind: String, rows: [(id: String, sortTs: Double, payload: String, fts: FTSDoc)]) {
        q.sync {
            execLocked("BEGIN")
            var oldIDs: [String] = []
            queryLocked("SELECT id FROM meetings WHERE kind=?", [kind]) { if let id = $0[0] { oldIDs.append(id) } }
            for id in oldIDs { runLocked("DELETE FROM meetings_fts WHERE id=?", [id]) }
            runLocked("DELETE FROM meetings WHERE kind=?", [kind])
            for r in rows {
                runLocked("INSERT INTO meetings(id,kind,sort_ts,payload) VALUES(?,?,?,?)",
                          [r.id, kind, r.sortTs, r.payload])
                runLocked("INSERT INTO meetings_fts(id,title,summary,transcript) VALUES(?,?,?,?)",
                          [r.id, r.fts.title, r.fts.summary, r.fts.transcript])
            }
            execLocked("COMMIT")
        }
    }

    /// 会议全文检索：全部关键词 ≥3 字时走 FTS5(trigram) 索引；否则 LIKE 扫描（当前量级毫秒）。
    /// 只返回命中 id；打分与摘录用内存里的原文做。
    func searchMeetings(tokens: [String], limit: Int = 30) -> [String] {
        guard !tokens.isEmpty else { return [] }
        var out: [String] = []
        q.sync {
            if tokens.allSatisfy({ $0.count >= 3 }) {
                let match = tokens.map { "\"\($0.replacingOccurrences(of: "\"", with: ""))\"" }
                    .joined(separator: " AND ")
                queryLocked("SELECT id FROM meetings_fts WHERE meetings_fts MATCH ? LIMIT ?",
                            [match, limit]) { if let id = $0[0] { out.append(id) } }
            } else {
                let conds = tokens.map { _ in "(title LIKE ? OR summary LIKE ? OR transcript LIKE ?)" }
                    .joined(separator: " AND ")
                var binds: [Any?] = []
                for t in tokens { let p = "%\(t)%"; binds += [p, p, p] }
                binds.append(limit)
                queryLocked("SELECT id FROM meetings_fts WHERE \(conds) LIMIT ?", binds) {
                    if let id = $0[0] { out.append(id) }
                }
            }
        }
        return out
    }

    // MARK: - 简单表（day/qa/task_links/kv）

    func dictAll(_ table: String, keyCol: String, valCol: String) -> [String: String] {
        var out: [String: String] = [:]
        q.sync {
            queryLocked("SELECT \(keyCol),\(valCol) FROM \(table)") {
                if let k = $0[0], let v = $0[1] { out[k] = v }
            }
        }
        return out
    }

    func setRow(_ table: String, keyCol: String, valCol: String, key: String, value: String) {
        q.sync { runLocked("INSERT OR REPLACE INTO \(table)(\(keyCol),\(valCol)) VALUES(?,?)", [key, value]) }
    }

    func kvGet(_ key: String) -> String? {
        var v: String?
        q.sync { queryLocked("SELECT value FROM kv WHERE key=?", [key]) { v = $0[0] } }
        return v
    }
    func kvSet(_ key: String, _ value: String) {
        q.sync { runLocked("INSERT OR REPLACE INTO kv(key,value) VALUES(?,?)", [key, value]) }
    }

    // MARK: - 首启迁移：旧 JSON → 表；旧文件原地保留（备份）

    private func migrateFromJSONIfNeeded() {
        guard kvGet("migrated_v1") == nil else { return }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AfterMeet")
        let dec = JSONDecoder(), enc = JSONEncoder()

        // live-meetings.json → kind='live'
        if let data = try? Data(contentsOf: base.appendingPathComponent("live-meetings.json")) {
            let items: [StoredLiveMeeting] = (try? dec.decode([StoredLiveMeeting].self, from: data))
                ?? ((try? JSONSerialization.jsonObject(with: data) as? [Any]) ?? []).compactMap { obj in
                    (try? JSONSerialization.data(withJSONObject: obj))
                        .flatMap { try? dec.decode(StoredLiveMeeting.self, from: $0) }
                }
            for m in items {
                guard let payload = try? enc.encode(m), let ps = String(data: payload, encoding: .utf8) else { continue }
                upsertMeeting(id: m.id, kind: "live", sortTs: m.timestamp, payload: ps,
                              fts: FTSDoc(title: m.title,
                                          summary: m.note.summary ?? m.note.blocks?.first(where: { $0.type == "summary" })?.text ?? "",
                                          transcript: m.transcript))
            }
        }
        // meetings.json → kind='feishu'（保持原数组顺序：sort_ts 用递减序号）
        if let data = try? Data(contentsOf: base.appendingPathComponent("meetings.json")),
           let store = try? dec.decode(RealStore.self, from: data) {
            for (i, m) in store.meetings.enumerated() {
                guard let payload = try? enc.encode(m), let ps = String(data: payload, encoding: .utf8) else { continue }
                upsertMeeting(id: m.meeting_id, kind: "feishu", sortTs: Double(1_000_000 - i), payload: ps,
                              fts: FTSDoc(title: m.title, summary: m.summary,
                                          transcript: m.excerpts.map { $0.text }.joined(separator: "\n")))
            }
        }
        // daily-digests.json
        if let data = try? Data(contentsOf: base.appendingPathComponent("daily-digests.json")),
           let m = try? dec.decode([String: [NoteBlock]].self, from: data) {
            for (day, blocks) in m {
                if let d = try? enc.encode(blocks), let s = String(data: d, encoding: .utf8) {
                    setRow("daily", keyCol: "day", valCol: "blocks", key: day, value: s)
                }
            }
        }
        // qa.json
        if let data = try? Data(contentsOf: base.appendingPathComponent("qa.json")),
           let m = try? dec.decode([String: [QATurn]].self, from: data) {
            for (id, turns) in m {
                if let d = try? enc.encode(turns), let s = String(data: d, encoding: .utf8) {
                    setRow("qa", keyCol: "meeting_id", valCol: "turns", key: id, value: s)
                }
            }
        }
        // task-links.json
        if let data = try? Data(contentsOf: base.appendingPathComponent("task-links.json")),
           let m = try? dec.decode([String: String].self, from: data) {
            for (k, v) in m { setRow("task_links", keyCol: "key", valCol: "guid", key: k, value: v) }
        }
        // calendar-cache.json
        if let data = try? Data(contentsOf: base.appendingPathComponent("calendar-cache.json")),
           let s = String(data: data, encoding: .utf8) {
            kvSet("cal_cache", s)
        }
        kvSet("migrated_v1", "1")
    }
}
