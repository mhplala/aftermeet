import Foundation
import SQLite3

/// 本地存储底座 —— 单文件 SQLite（WAL，崩溃安全、按行写入）+ FTS5 全文索引。
/// 替代原来的 6 个 JSON 文件：每条会议一行（payload 仍是 JSON，沿用现有容错解码器），
/// 追加一场会 = 插一行，不再整文件重写；首启自动从旧 JSON 迁移，旧文件原地保留作备份。
final class DB {
    static let shared = DB()
    static let currentSchemaVersion = 9

    /// Base storage can remain usable even when an additive knowledge migration is unavailable.
    private(set) var healthy = true
    private(set) var storageError: String?
    private(set) var knowledgeHealthy = true
    private(set) var schemaMigrationError: String?
    private(set) var legacyMigrationError: String?
    let databaseURL: URL
    private let legacyBaseURL: URL?
    private let backupDirectory: URL?
    private let databaseExistedBeforeOpen: Bool
    private let migrationFailureAtVersion: Int?
    private var handle: OpaquePointer?
    private let q = DispatchQueue(label: "aftermeet.db")   // 串行队列，所有访问排队
    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    static var fileURL: URL {
        let env = ProcessInfo.processInfo.environment
        if let override = env["AFTERMEET_DATABASE_PATH"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        if env["XCTestConfigurationFilePath"] != nil || UserDefaults.standard.bool(forKey: "demo") {
            let base = FileManager.default.temporaryDirectory
                .appendingPathComponent("AfterMeet-Isolated-" + String(ProcessInfo.processInfo.processIdentifier))
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            return base.appendingPathComponent("aftermeet.db")
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AfterMeet")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("aftermeet.db")
    }

    private convenience init() {
        let url = Self.fileURL
        let base = url.deletingLastPathComponent()
        self.init(databaseURL: url, migrateLegacyJSON: true,
                  legacyBaseURL: base, backupDirectory: base.appendingPathComponent("Backups"))
    }

    /// Internal initializer for isolated stores and tests. Callers must explicitly opt into the
    /// legacy JSON import and migration backups so temporary databases stay self-contained.
    init(databaseURL: URL, migrateLegacyJSON: Bool = false, legacyBaseURL: URL? = nil,
         backupDirectory: URL? = nil, migrationFailureAtVersion: Int? = nil) {
        self.databaseURL = databaseURL
        self.legacyBaseURL = migrateLegacyJSON ? legacyBaseURL : nil
        self.backupDirectory = backupDirectory
        self.databaseExistedBeforeOpen = FileManager.default.fileExists(atPath: databaseURL.path)
        self.migrationFailureAtVersion = migrationFailureAtVersion
        try? FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        q.sync {
            guard sqlite3_open(databaseURL.path, &handle) == SQLITE_OK else {
                if let h = handle { sqlite3_close(h) }
                handle = nil
                healthy = false
                knowledgeHealthy = false
                storageError = "无法打开数据库：\(databaseURL.lastPathComponent)"
                return
            }
            let ready = execLocked("PRAGMA journal_mode=WAL")
                && execLocked("PRAGMA synchronous=NORMAL")
                && execLocked("PRAGMA busy_timeout=3000")
                && execLocked("PRAGMA foreign_keys=ON")
                && execLocked("""
                    CREATE TABLE IF NOT EXISTS meetings(
                        id TEXT PRIMARY KEY,
                        kind TEXT NOT NULL,          -- 'live' | 'feishu'
                        sort_ts REAL NOT NULL DEFAULT 0,
                        payload TEXT NOT NULL
                    )
                    """)
                && execLocked("""
                    CREATE VIRTUAL TABLE IF NOT EXISTS meetings_fts
                    USING fts5(id UNINDEXED, title, summary, transcript, tokenize='trigram')
                    """)
                && execLocked("CREATE TABLE IF NOT EXISTS daily(day TEXT PRIMARY KEY, blocks TEXT NOT NULL)")
                && execLocked("CREATE TABLE IF NOT EXISTS qa(meeting_id TEXT PRIMARY KEY, turns TEXT NOT NULL)")
                && execLocked("CREATE TABLE IF NOT EXISTS md_summary(meeting_id TEXT PRIMARY KEY, markdown TEXT NOT NULL)")
                && execLocked("CREATE TABLE IF NOT EXISTS task_links(key TEXT PRIMARY KEY, guid TEXT NOT NULL)")
                && execLocked("CREATE TABLE IF NOT EXISTS kv(key TEXT PRIMARY KEY, value TEXT NOT NULL)")
            if !ready {
                healthy = false
                knowledgeHealthy = false
                storageError = "数据库基础结构初始化失败"
            }
        }
        if healthy, prepareMigrationBackupIfNeeded() {
            migrateSchemaIfNeeded()
        }
        if healthy, migrateLegacyJSON { migrateFromJSONIfNeeded() }
    }

    deinit {
        if let handle { sqlite3_close(handle) }
    }

    // MARK: - 底层（都在 q 上）

    @discardableResult
    private func execLocked(_ sql: String) -> Bool {
        guard let handle else { return false }
        return sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK
    }

    /// 预编译 + 绑定 + 执行（无结果集）。binds 支持 String / Double / Int / nil。失败返回 false。
    @discardableResult
    private func runLocked(_ sql: String, _ binds: [Any?] = []) -> Bool {
        guard let handle else { return false }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, binds)
        let rc = sqlite3_step(stmt)
        return rc == SQLITE_DONE || rc == SQLITE_ROW
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

    private func scalarIntLocked(_ sql: String, _ binds: [Any?] = []) -> Int {
        var value = 0
        queryLocked(sql, binds) { value = Int($0[0] ?? "0") ?? 0 }
        return value
    }

    private func transactionLocked(_ body: () -> Bool) -> Bool {
        guard execLocked("BEGIN IMMEDIATE") else { return false }
        guard body() else {
            execLocked("ROLLBACK")
            return false
        }
        guard execLocked("COMMIT") else {
            execLocked("ROLLBACK")
            return false
        }
        return true
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

    // MARK: - Versioned schema migrations

    var schemaVersion: Int { q.sync { userVersionLocked() } }
    var foreignKeysEnabled: Bool {
        q.sync {
            var enabled = false
            queryLocked("PRAGMA foreign_keys") { enabled = $0[0] == "1" }
            return enabled
        }
    }

    private func userVersionLocked() -> Int {
        var version = 0
        queryLocked("PRAGMA user_version") { version = Int($0[0] ?? "0") ?? 0 }
        return version
    }

    private func prepareMigrationBackupIfNeeded() -> Bool {
        guard databaseExistedBeforeOpen, let backupDirectory else { return true }
        return q.sync {
            let fromVersion = userVersionLocked()
            guard fromVersion < Self.currentSchemaVersion else { return true }

            let prefix = "aftermeet-pre-schema-v\(Self.currentSchemaVersion)-"
            let existing = (try? FileManager.default.contentsOfDirectory(
                at: backupDirectory, includingPropertiesForKeys: nil)) ?? []
            if existing.contains(where: { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "db" }) {
                return true
            }

            do {
                try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
            } catch {
                knowledgeHealthy = false
                schemaMigrationError = "无法创建数据库备份目录：\(error.localizedDescription)"
                return false
            }
            guard execLocked("PRAGMA wal_checkpoint(TRUNCATE)") else {
                knowledgeHealthy = false
                schemaMigrationError = "数据库迁移前 WAL checkpoint 失败"
                return false
            }

            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let destinationURL = backupDirectory
                .appendingPathComponent(prefix + formatter.string(from: Date()) + ".db")
            var destination: OpaquePointer?
            guard sqlite3_open_v2(destinationURL.path, &destination,
                                  SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
                                  nil) == SQLITE_OK,
                  let destination else {
                if let destination { sqlite3_close(destination) }
                knowledgeHealthy = false
                schemaMigrationError = "无法创建数据库迁移备份"
                return false
            }

            guard let backup = sqlite3_backup_init(destination, "main", handle, "main") else {
                sqlite3_close(destination)
                try? FileManager.default.removeItem(at: destinationURL)
                knowledgeHealthy = false
                schemaMigrationError = "无法初始化数据库迁移备份"
                return false
            }

            var rc = SQLITE_OK
            var busyRetries = 0
            repeat {
                rc = sqlite3_backup_step(backup, 256)
                if rc == SQLITE_BUSY || rc == SQLITE_LOCKED {
                    busyRetries += 1
                    sqlite3_sleep(50)
                }
            } while rc == SQLITE_OK || ((rc == SQLITE_BUSY || rc == SQLITE_LOCKED) && busyRetries < 100)
            let finishRC = sqlite3_backup_finish(backup)
            let journalRC = sqlite3_exec(destination,
                                         "PRAGMA wal_checkpoint(TRUNCATE); PRAGMA journal_mode=DELETE;",
                                         nil, nil, nil)
            let valid = rc == SQLITE_DONE && finishRC == SQLITE_OK
                && journalRC == SQLITE_OK && Self.integrityOK(destination)
            sqlite3_close(destination)
            try? FileManager.default.removeItem(atPath: destinationURL.path + "-wal")
            try? FileManager.default.removeItem(atPath: destinationURL.path + "-shm")

            guard valid else {
                try? FileManager.default.removeItem(at: destinationURL)
                knowledgeHealthy = false
                schemaMigrationError = "数据库迁移备份未通过完整性检查"
                return false
            }
            guard let pruneError = pruneMigrationBackups(in: backupDirectory) else { return true }
            knowledgeHealthy = false
            schemaMigrationError = "数据库备份已完成，但旧备份清理失败：\(pruneError)"
            return false
        }
    }

    private static func integrityOK(_ database: OpaquePointer?) -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA integrity_check", -1, &statement, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let text = sqlite3_column_text(statement, 0) else { return false }
        return String(cString: text) == "ok"
    }

    private func pruneMigrationBackups(in directory: URL) -> String? {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        let urls = ((try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: Array(keys))) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("aftermeet-pre-schema-v") && $0.pathExtension == "db" }
            .sorted {
                let left = (try? $0.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast
                let right = (try? $1.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast
                return left > right
            }
        guard urls.count > 3 else { return nil }
        for index in 3..<urls.count {
            do { try FileManager.default.removeItem(at: urls[index]) }
            catch { return error.localizedDescription }
        }
        return nil
    }

    private func migrateSchemaIfNeeded() {
        q.sync {
            guard handle != nil else {
                knowledgeHealthy = false
                schemaMigrationError = "数据库未打开，无法检查知识库结构"
                return
            }
            var version = userVersionLocked()
            guard version <= Self.currentSchemaVersion else {
                knowledgeHealthy = false
                schemaMigrationError = "数据库版本 \(version) 高于当前支持的 \(Self.currentSchemaVersion)"
                return
            }

            while version < Self.currentSchemaVersion {
                let next = version + 1
                guard execLocked("BEGIN IMMEDIATE") else {
                    knowledgeHealthy = false
                    schemaMigrationError = "无法开始数据库迁移 v\(next)"
                    return
                }
                let applied = applyMigrationLocked(next)
                    && execLocked("PRAGMA user_version = \(next)")
                guard applied, execLocked("COMMIT") else {
                    execLocked("ROLLBACK")
                    knowledgeHealthy = false
                    schemaMigrationError = "数据库迁移 v\(next) 失败，已回滚"
                    return
                }
                version = next
            }
        }
    }

    private func applyMigrationLocked(_ version: Int) -> Bool {
        if migrationFailureAtVersion == version { return false }
        switch version {
        case 1:
            return execLocked("CREATE INDEX IF NOT EXISTS idx_meetings_kind_sort_ts ON meetings(kind, sort_ts DESC)")
        case 2:
            return execLocked("""
                CREATE TABLE source_documents(
                    id TEXT PRIMARY KEY,
                    meeting_id TEXT NOT NULL,
                    source_kind TEXT NOT NULL CHECK(source_kind IN ('live_cloud','live_local','feishu','archive')),
                    locator TEXT,
                    full_text TEXT NOT NULL,
                    content_hash TEXT NOT NULL,
                    source_revision INTEGER NOT NULL DEFAULT 1 CHECK(source_revision >= 1),
                    started_at REAL,
                    ended_at REAL,
                    language TEXT,
                    sensitivity TEXT NOT NULL DEFAULT 'normal' CHECK(sensitivity IN ('normal','restricted')),
                    metadata_json TEXT NOT NULL DEFAULT '{}',
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    UNIQUE(meeting_id, source_kind, content_hash)
                );
                CREATE INDEX idx_source_documents_meeting ON source_documents(meeting_id);
                CREATE INDEX idx_source_documents_hash ON source_documents(content_hash);
                """)
        case 3:
            return execLocked("""
                CREATE TABLE source_segments(
                    id TEXT PRIMARY KEY,
                    source_id TEXT NOT NULL,
                    meeting_id TEXT NOT NULL,
                    ordinal INTEGER NOT NULL CHECK(ordinal >= 0),
                    speaker TEXT,
                    start_ms INTEGER CHECK(start_ms IS NULL OR start_ms >= 0),
                    end_ms INTEGER CHECK(end_ms IS NULL OR end_ms >= 0),
                    char_start INTEGER NOT NULL CHECK(char_start >= 0),
                    char_end INTEGER NOT NULL CHECK(char_end >= char_start),
                    text TEXT NOT NULL,
                    content_hash TEXT NOT NULL,
                    metadata_json TEXT NOT NULL DEFAULT '{}',
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    UNIQUE(source_id, ordinal),
                    FOREIGN KEY(source_id) REFERENCES source_documents(id) ON DELETE CASCADE,
                    CHECK(start_ms IS NULL OR end_ms IS NULL OR end_ms >= start_ms)
                );
                CREATE INDEX idx_source_segments_meeting_ordinal ON source_segments(meeting_id, ordinal);
                CREATE INDEX idx_source_segments_hash ON source_segments(content_hash);
                """)
        case 4:
            return execLocked("""
                CREATE TABLE knowledge_units(
                    id TEXT PRIMARY KEY,
                    kind TEXT NOT NULL CHECK(kind IN ('fact','decision','action','open_question','metric','risk','dispute')),
                    canonical_text TEXT NOT NULL CHECK(length(canonical_text) > 0),
                    subject TEXT,
                    predicate TEXT,
                    object_text TEXT,
                    numeric_value REAL,
                    value_unit TEXT,
                    owner TEXT,
                    due_text TEXT,
                    valid_from REAL,
                    valid_to REAL,
                    observed_at REAL NOT NULL,
                    review_status TEXT NOT NULL CHECK(review_status IN ('candidate','confirmed','edited','rejected')),
                    evidence_level TEXT NOT NULL CHECK(evidence_level IN ('direct','inferred')),
                    conflict_status TEXT NOT NULL DEFAULT 'none' CHECK(conflict_status IN ('none','pending','resolved')),
                    sensitivity TEXT NOT NULL DEFAULT 'normal' CHECK(sensitivity IN ('normal','restricted')),
                    fingerprint TEXT NOT NULL,
                    revision INTEGER NOT NULL DEFAULT 1 CHECK(revision >= 1),
                    extractor_version TEXT NOT NULL,
                    prompt_version TEXT NOT NULL,
                    schema_version INTEGER NOT NULL CHECK(schema_version >= 1),
                    model TEXT NOT NULL,
                    payload_json TEXT NOT NULL DEFAULT '{}',
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    CHECK(valid_from IS NULL OR valid_to IS NULL OR valid_to >= valid_from)
                );
                CREATE INDEX idx_knowledge_units_review_updated ON knowledge_units(review_status, updated_at DESC);
                CREATE INDEX idx_knowledge_units_kind_observed ON knowledge_units(kind, observed_at DESC);
                CREATE INDEX idx_knowledge_units_fingerprint ON knowledge_units(fingerprint);
                CREATE INDEX idx_knowledge_units_sensitivity ON knowledge_units(sensitivity);
                """)
        case 5:
            return execLocked("""
                CREATE TABLE unit_sources(
                    unit_id TEXT NOT NULL,
                    segment_id TEXT NOT NULL,
                    evidence_role TEXT NOT NULL CHECK(evidence_role IN ('support','counter','context')),
                    quote TEXT NOT NULL,
                    weight REAL NOT NULL DEFAULT 1 CHECK(weight >= 0),
                    verified INTEGER NOT NULL DEFAULT 0 CHECK(verified IN (0,1)),
                    PRIMARY KEY(unit_id, segment_id, evidence_role),
                    FOREIGN KEY(unit_id) REFERENCES knowledge_units(id) ON DELETE CASCADE,
                    FOREIGN KEY(segment_id) REFERENCES source_segments(id) ON DELETE CASCADE
                );
                CREATE INDEX idx_unit_sources_segment ON unit_sources(segment_id);

                CREATE TABLE projects(
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL CHECK(length(name) > 0),
                    normalized_name TEXT NOT NULL UNIQUE CHECK(length(normalized_name) > 0),
                    aliases_json TEXT NOT NULL DEFAULT '[]',
                    status TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('active','paused','completed','archived')),
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL
                );

                CREATE TABLE unit_projects(
                    unit_id TEXT NOT NULL,
                    project_id TEXT NOT NULL,
                    role TEXT NOT NULL DEFAULT 'related',
                    relevance REAL NOT NULL DEFAULT 1 CHECK(relevance >= 0),
                    assignment_source TEXT NOT NULL CHECK(assignment_source IN ('model','rule','user')),
                    review_status TEXT NOT NULL CHECK(review_status IN ('candidate','confirmed','rejected')),
                    PRIMARY KEY(unit_id, project_id),
                    FOREIGN KEY(unit_id) REFERENCES knowledge_units(id) ON DELETE CASCADE,
                    FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE CASCADE
                );
                CREATE INDEX idx_unit_projects_project_review ON unit_projects(project_id, review_status);

                CREATE TABLE unit_relations(
                    from_unit_id TEXT NOT NULL,
                    to_unit_id TEXT NOT NULL,
                    relation_kind TEXT NOT NULL CHECK(relation_kind IN ('supersedes','contradicts','depends_on','same_as','updates')),
                    review_status TEXT NOT NULL CHECK(review_status IN ('candidate','confirmed','rejected')),
                    reason TEXT,
                    payload_json TEXT NOT NULL DEFAULT '{}',
                    created_at REAL NOT NULL,
                    PRIMARY KEY(from_unit_id, to_unit_id, relation_kind),
                    FOREIGN KEY(from_unit_id) REFERENCES knowledge_units(id) ON DELETE CASCADE,
                    FOREIGN KEY(to_unit_id) REFERENCES knowledge_units(id) ON DELETE CASCADE,
                    CHECK(from_unit_id <> to_unit_id)
                );
                CREATE INDEX idx_unit_relations_to ON unit_relations(to_unit_id);
                """)
        case 6:
            return execLocked("""
                CREATE TABLE feedback_events(
                    id TEXT PRIMARY KEY,
                    target_type TEXT NOT NULL,
                    target_id TEXT NOT NULL,
                    action TEXT NOT NULL CHECK(action IN ('confirm','edit','reject','merge','split','relate','unrelate','restore')),
                    before_json TEXT,
                    after_json TEXT,
                    reason TEXT,
                    actor TEXT NOT NULL DEFAULT 'user',
                    created_at REAL NOT NULL
                );
                CREATE INDEX idx_feedback_events_target_created
                    ON feedback_events(target_type, target_id, created_at);
                CREATE TRIGGER feedback_events_no_update
                    BEFORE UPDATE ON feedback_events
                    BEGIN SELECT RAISE(ABORT, 'feedback_events is append-only'); END;
                CREATE TRIGGER feedback_events_no_delete
                    BEFORE DELETE ON feedback_events
                    BEGIN SELECT RAISE(ABORT, 'feedback_events is append-only'); END;
                """)
        case 7:
            return execLocked("""
                CREATE TABLE extraction_jobs(
                    id TEXT PRIMARY KEY,
                    source_id TEXT NOT NULL,
                    job_kind TEXT NOT NULL CHECK(job_kind IN ('segment','extract','index','reextract')),
                    state TEXT NOT NULL CHECK(state IN ('pending','running','retry','failed','done','cancelled')),
                    input_hash TEXT NOT NULL,
                    extractor_version TEXT NOT NULL,
                    cursor INTEGER NOT NULL DEFAULT 0 CHECK(cursor >= 0),
                    attempt INTEGER NOT NULL DEFAULT 0 CHECK(attempt >= 0),
                    next_retry_at REAL,
                    lease_until REAL,
                    last_error TEXT,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    UNIQUE(source_id, job_kind, input_hash, extractor_version),
                    FOREIGN KEY(source_id) REFERENCES source_documents(id) ON DELETE CASCADE
                );
                CREATE INDEX idx_extraction_jobs_state_retry
                    ON extraction_jobs(state, next_retry_at);
                """)
        case 8:
            return execLocked("""
                CREATE VIRTUAL TABLE knowledge_fts USING fts5(
                    doc_type UNINDEXED,
                    doc_id UNINDEXED,
                    meeting_id UNINDEXED,
                    project_id UNINDEXED,
                    title,
                    body,
                    context,
                    tokenize='trigram'
                );
                """)
        case 9:
            return execLocked("""
                CREATE TABLE extraction_diagnostics(
                    id TEXT PRIMARY KEY,
                    job_id TEXT NOT NULL,
                    source_id TEXT NOT NULL,
                    chunk_index INTEGER NOT NULL CHECK(chunk_index >= 0),
                    input_characters INTEGER NOT NULL CHECK(input_characters >= 0),
                    output_characters INTEGER NOT NULL CHECK(output_characters >= 0),
                    candidate_count INTEGER NOT NULL CHECK(candidate_count >= 0),
                    accepted_count INTEGER NOT NULL CHECK(accepted_count >= 0),
                    invalid_evidence_count INTEGER NOT NULL CHECK(invalid_evidence_count >= 0),
                    duration_ms INTEGER NOT NULL CHECK(duration_ms >= 0),
                    retry_count INTEGER NOT NULL CHECK(retry_count >= 0),
                    outcome TEXT NOT NULL CHECK(outcome IN ('completed','rejected','retry','failed')),
                    error_code TEXT,
                    created_at REAL NOT NULL,
                    FOREIGN KEY(job_id) REFERENCES extraction_jobs(id) ON DELETE CASCADE,
                    FOREIGN KEY(source_id) REFERENCES source_documents(id) ON DELETE CASCADE
                );
                CREATE INDEX idx_extraction_diagnostics_job_chunk
                    ON extraction_diagnostics(job_id,chunk_index,created_at);
                CREATE INDEX idx_extraction_diagnostics_source
                    ON extraction_diagnostics(source_id,created_at);
                CREATE TRIGGER extraction_diagnostics_no_update
                    BEFORE UPDATE ON extraction_diagnostics
                    BEGIN SELECT RAISE(ABORT, 'extraction_diagnostics is append-only'); END;
                """)
        default:
            return false
        }
    }

    // MARK: - 会议（payload = 原 JSON 结构，容错解码逻辑不变）

    struct FTSDoc { let title: String; let summary: String; let transcript: String }

    /// 事务化 upsert：任一步失败 → ROLLBACK 并返回 false（磁盘满/句柄坏都不留半事务）。
    @discardableResult
    func upsertMeeting(id: String, kind: String, sortTs: Double, payload: String, fts: FTSDoc) -> Bool {
        var ok = false
        q.sync {
            guard execLocked("BEGIN") else { return }
            ok = runLocked("""
                INSERT INTO meetings(id,kind,sort_ts,payload) VALUES(?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET
                    kind=excluded.kind,
                    sort_ts=excluded.sort_ts,
                    payload=excluded.payload
                """, [id, kind, sortTs, payload])
                && runLocked("DELETE FROM meetings_fts WHERE id=?", [id])
                && runLocked("INSERT INTO meetings_fts(id,title,summary,transcript) VALUES(?,?,?,?)",
                             [id, fts.title, fts.summary, fts.transcript])
            if ok { ok = execLocked("COMMIT"); if !ok { execLocked("ROLLBACK") } }
            else { execLocked("ROLLBACK") }
        }
        return ok
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

    // MARK: - Typed knowledge source persistence

    @discardableResult
    func saveKnowledgeSource(_ document: KnowledgeSourceDocument,
                             segments: [KnowledgeSourceSegment],
                             meetingTitle: String) -> Bool {
        guard knowledgeHealthy, segments.allSatisfy({ $0.sourceID == document.id }) else { return false }
        var ok = false
        q.sync {
            ok = transactionLocked {
                guard runLocked("""
                    INSERT INTO source_documents(
                        id,meeting_id,source_kind,locator,full_text,content_hash,source_revision,
                        started_at,ended_at,language,sensitivity,metadata_json,created_at,updated_at
                    ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                    ON CONFLICT(id) DO UPDATE SET
                        meeting_id=excluded.meeting_id,
                        source_kind=excluded.source_kind,
                        locator=excluded.locator,
                        full_text=excluded.full_text,
                        content_hash=excluded.content_hash,
                        source_revision=excluded.source_revision,
                        started_at=excluded.started_at,
                        ended_at=excluded.ended_at,
                        language=excluded.language,
                        sensitivity=excluded.sensitivity,
                        metadata_json=excluded.metadata_json,
                        updated_at=excluded.updated_at
                    """, [document.id, document.meetingID, document.sourceKind.rawValue,
                            document.locator, document.fullText, document.contentHash,
                            document.sourceRevision, document.startedAt, document.endedAt,
                            document.language, document.sensitivity.rawValue, document.metadataJSON,
                            document.createdAt, document.updatedAt]) else { return false }

                for segment in segments {
                    guard runLocked("""
                        INSERT INTO source_segments(
                            id,source_id,meeting_id,ordinal,speaker,start_ms,end_ms,char_start,char_end,
                            text,content_hash,metadata_json,created_at,updated_at
                        ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                        ON CONFLICT(id) DO UPDATE SET
                            source_id=excluded.source_id,
                            meeting_id=excluded.meeting_id,
                            ordinal=excluded.ordinal,
                            speaker=excluded.speaker,
                            start_ms=excluded.start_ms,
                            end_ms=excluded.end_ms,
                            char_start=excluded.char_start,
                            char_end=excluded.char_end,
                            text=excluded.text,
                            content_hash=excluded.content_hash,
                            metadata_json=excluded.metadata_json,
                            updated_at=excluded.updated_at
                        """, [segment.id, segment.sourceID, segment.meetingID, segment.ordinal,
                                segment.speaker, segment.startMS, segment.endMS, segment.charStart,
                                segment.charEnd, segment.text, segment.contentHash,
                                segment.metadataJSON, segment.createdAt, segment.updatedAt]),
                          runLocked("DELETE FROM knowledge_fts WHERE doc_type='segment' AND doc_id=?",
                                    [segment.id]),
                          runLocked("""
                              INSERT INTO knowledge_fts(
                                  doc_type,doc_id,meeting_id,project_id,title,body,context
                              ) VALUES('segment',?,?,NULL,?,?,?)
                              """, [segment.id, segment.meetingID, meetingTitle, segment.text,
                                      segment.speaker ?? ""])
                    else { return false }
                }
                return true
            }
        }
        return ok
    }

    func knowledgeSources(meetingID: String? = nil) -> [KnowledgeSourceDocument] {
        guard knowledgeHealthy else { return [] }
        var output: [KnowledgeSourceDocument] = []
        q.sync {
            let sql = """
                SELECT id,meeting_id,source_kind,locator,full_text,content_hash,source_revision,
                       started_at,ended_at,language,sensitivity,metadata_json,created_at,updated_at
                FROM source_documents
                """ + (meetingID == nil ? " ORDER BY updated_at DESC" : " WHERE meeting_id=? ORDER BY source_revision DESC")
            queryLocked(sql, meetingID.map { [$0] } ?? []) { row in
                guard let id = row[0], let meeting = row[1],
                      let kindRaw = row[2], let kind = KnowledgeSourceKind(rawValue: kindRaw),
                      let fullText = row[4], let hash = row[5],
                      let revision = Int(row[6] ?? ""),
                      let sensitivityRaw = row[10], let sensitivity = KnowledgeSensitivity(rawValue: sensitivityRaw),
                      let metadata = row[11], let created = Double(row[12] ?? ""),
                      let updated = Double(row[13] ?? "") else { return }
                output.append(KnowledgeSourceDocument(
                    id: id, meetingID: meeting, sourceKind: kind, locator: row[3],
                    fullText: fullText, contentHash: hash, sourceRevision: revision,
                    startedAt: row[7].flatMap(Double.init), endedAt: row[8].flatMap(Double.init),
                    language: row[9], sensitivity: sensitivity, metadataJSON: metadata,
                    createdAt: created, updatedAt: updated))
            }
        }
        return output
    }

    @discardableResult
    func updateKnowledgeSourceSensitivity(id: String,
                                          sensitivity: KnowledgeSensitivity,
                                          updatedAt: TimeInterval,
                                          feedback: KnowledgeFeedbackEvent) -> Bool {
        guard knowledgeHealthy,
              feedback.targetType == "source_document",
              feedback.targetID == id,
              feedback.action == .edit else { return false }
        var ok = false
        q.sync {
            ok = transactionLocked {
                runLocked("UPDATE source_documents SET sensitivity=?,updated_at=? WHERE id=?",
                          [sensitivity.rawValue, updatedAt, id])
                    && runLocked("""
                        INSERT INTO feedback_events(
                            id,target_type,target_id,action,before_json,after_json,reason,actor,created_at
                        ) VALUES(?,?,?,?,?,?,?,?,?)
                        """, [feedback.id, feedback.targetType, feedback.targetID,
                                feedback.action.rawValue, feedback.beforeJSON, feedback.afterJSON,
                                feedback.reason, feedback.actor, feedback.createdAt])
            }
        }
        return ok
    }

    func knowledgeSegments(sourceID: String? = nil) -> [KnowledgeSourceSegment] {
        guard knowledgeHealthy else { return [] }
        var output: [KnowledgeSourceSegment] = []
        q.sync {
            let sql = """
                SELECT id,source_id,meeting_id,ordinal,speaker,start_ms,end_ms,char_start,char_end,
                       text,content_hash,metadata_json,created_at,updated_at
                FROM source_segments
                """ + (sourceID == nil ? " ORDER BY meeting_id,source_id,ordinal" : " WHERE source_id=? ORDER BY ordinal")
            let binds: [Any?] = sourceID.map { [$0] } ?? []
            queryLocked(sql, binds) { row in
                guard let id = row[0], let source = row[1], let meeting = row[2],
                      let ordinal = Int(row[3] ?? ""), let charStart = Int(row[7] ?? ""),
                      let charEnd = Int(row[8] ?? ""), let text = row[9], let hash = row[10],
                      let metadata = row[11], let created = Double(row[12] ?? ""),
                      let updated = Double(row[13] ?? "") else { return }
                output.append(KnowledgeSourceSegment(
                    id: id, sourceID: source, meetingID: meeting, ordinal: ordinal,
                    speaker: row[4], startMS: row[5].flatMap(Int.init), endMS: row[6].flatMap(Int.init),
                    charStart: charStart, charEnd: charEnd, text: text, contentHash: hash,
                    metadataJSON: metadata, createdAt: created, updatedAt: updated))
            }
        }
        return output
    }

    @discardableResult
    func deleteKnowledgeSource(id: String) -> Bool {
        guard knowledgeHealthy else { return false }
        var ok = false
        q.sync {
            ok = transactionLocked {
                var segmentIDs: [String] = []
                queryLocked("SELECT id FROM source_segments WHERE source_id=?", [id]) {
                    if let segmentID = $0[0] { segmentIDs.append(segmentID) }
                }
                for segmentID in segmentIDs {
                    guard runLocked("DELETE FROM knowledge_fts WHERE doc_type='segment' AND doc_id=?",
                                    [segmentID]) else { return false }
                }
                return runLocked("DELETE FROM source_documents WHERE id=?", [id])
            }
        }
        return ok
    }

    @discardableResult
    func saveKnowledgeUnit(_ unit: KnowledgeUnit,
                           evidence: [KnowledgeUnitSource],
                           projectLinks: [KnowledgeUnitProject],
                           meetingID: String,
                           meetingTitle: String) -> Bool {
        guard knowledgeHealthy,
              evidence.allSatisfy({ $0.unitID == unit.id }),
              projectLinks.allSatisfy({ $0.unitID == unit.id }) else { return false }
        var ok = false
        q.sync {
            ok = transactionLocked {
                guard runLocked("""
                    INSERT INTO knowledge_units(
                        id,kind,canonical_text,subject,predicate,object_text,numeric_value,value_unit,
                        owner,due_text,valid_from,valid_to,observed_at,review_status,evidence_level,
                        conflict_status,sensitivity,fingerprint,revision,extractor_version,prompt_version,
                        schema_version,model,payload_json,created_at,updated_at
                    ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                    ON CONFLICT(id) DO UPDATE SET
                        kind=excluded.kind,
                        canonical_text=excluded.canonical_text,
                        subject=excluded.subject,
                        predicate=excluded.predicate,
                        object_text=excluded.object_text,
                        numeric_value=excluded.numeric_value,
                        value_unit=excluded.value_unit,
                        owner=excluded.owner,
                        due_text=excluded.due_text,
                        valid_from=excluded.valid_from,
                        valid_to=excluded.valid_to,
                        observed_at=excluded.observed_at,
                        review_status=excluded.review_status,
                        evidence_level=excluded.evidence_level,
                        conflict_status=excluded.conflict_status,
                        sensitivity=excluded.sensitivity,
                        fingerprint=excluded.fingerprint,
                        revision=excluded.revision,
                        extractor_version=excluded.extractor_version,
                        prompt_version=excluded.prompt_version,
                        schema_version=excluded.schema_version,
                        model=excluded.model,
                        payload_json=excluded.payload_json,
                        updated_at=excluded.updated_at
                    """, [unit.id, unit.kind.rawValue, unit.canonicalText, unit.subject,
                            unit.predicate, unit.objectText, unit.numericValue, unit.valueUnit,
                            unit.owner, unit.dueText, unit.validFrom, unit.validTo, unit.observedAt,
                            unit.reviewStatus.rawValue, unit.evidenceLevel.rawValue,
                            unit.conflictStatus.rawValue, unit.sensitivity.rawValue, unit.fingerprint,
                            unit.revision, unit.extractorVersion, unit.promptVersion, unit.schemaVersion,
                            unit.model, unit.payloadJSON, unit.createdAt, unit.updatedAt]),
                      runLocked("DELETE FROM unit_sources WHERE unit_id=?", [unit.id]),
                      runLocked("DELETE FROM unit_projects WHERE unit_id=?", [unit.id])
                else { return false }

                for source in evidence {
                    guard runLocked("""
                        INSERT INTO unit_sources(
                            unit_id,segment_id,evidence_role,quote,weight,verified
                        ) VALUES(?,?,?,?,?,?)
                        """, [source.unitID, source.segmentID, source.evidenceRole.rawValue,
                                source.quote, source.weight, source.verified ? 1 : 0]) else { return false }
                }
                for link in projectLinks {
                    guard runLocked("""
                        INSERT INTO unit_projects(
                            unit_id,project_id,role,relevance,assignment_source,review_status
                        ) VALUES(?,?,?,?,?,?)
                        """, [link.unitID, link.projectID, link.role, link.relevance,
                                link.assignmentSource.rawValue, link.reviewStatus.rawValue]) else { return false }
                }

                guard runLocked("DELETE FROM knowledge_fts WHERE doc_type='unit' AND doc_id=?", [unit.id]) else {
                    return false
                }
                if unit.reviewStatus != .rejected {
                    let projectID = projectLinks.first(where: { $0.reviewStatus == .confirmed })?.projectID
                        ?? projectLinks.first?.projectID
                    let context = [unit.subject, unit.predicate, unit.objectText]
                        .compactMap { $0 }.joined(separator: " ")
                    guard runLocked("""
                        INSERT INTO knowledge_fts(
                            doc_type,doc_id,meeting_id,project_id,title,body,context
                        ) VALUES('unit',?,?,?,?,?,?)
                        """, [unit.id, meetingID, projectID, meetingTitle,
                                unit.canonicalText, context]) else { return false }
                }
                return true
            }
        }
        return ok
    }

    @discardableResult
    func confirmKnowledgeUnit(id: String,
                              feedback: KnowledgeFeedbackEvent,
                              now: TimeInterval) -> Bool {
        guard knowledgeHealthy,
              feedback.targetType == "knowledge_unit",
              feedback.targetID == id,
              feedback.action == .confirm else { return false }
        var ok = false
        q.sync {
            var currentStatus: KnowledgeReviewStatus?
            queryLocked("SELECT review_status FROM knowledge_units WHERE id=?", [id]) {
                currentStatus = $0[0].flatMap(KnowledgeReviewStatus.init(rawValue:))
            }
            if currentStatus == .confirmed || currentStatus == .edited {
                ok = true
                return
            }
            guard currentStatus == .candidate,
                  scalarIntLocked("""
                      SELECT COUNT(*) FROM unit_sources
                      WHERE unit_id=? AND evidence_role='support'
                      """, [id]) > 0 else { return }
            ok = transactionLocked {
                runLocked("""
                    UPDATE knowledge_units SET review_status='confirmed',updated_at=?
                    WHERE id=? AND review_status='candidate'
                    """, [now, id])
                    && sqlite3_changes(handle) == 1
                    && runLocked("UPDATE unit_sources SET verified=1 WHERE unit_id=?", [id])
                    && runLocked("""
                        INSERT INTO feedback_events(
                            id,target_type,target_id,action,before_json,after_json,reason,actor,created_at
                        ) VALUES(?,?,?,?,?,?,?,?,?)
                        """, [feedback.id, feedback.targetType, feedback.targetID,
                                feedback.action.rawValue, feedback.beforeJSON, feedback.afterJSON,
                                feedback.reason, feedback.actor, feedback.createdAt])
            }
        }
        return ok
    }

    @discardableResult
    func editKnowledgeUnit(_ unit: KnowledgeUnit,
                           feedback: KnowledgeFeedbackEvent,
                           meetingID: String,
                           meetingTitle: String) -> Bool {
        guard knowledgeHealthy,
              unit.reviewStatus == .edited,
              feedback.targetType == "knowledge_unit",
              feedback.targetID == unit.id,
              feedback.action == .edit,
              scalarKnowledgeSupportCount(unitID: unit.id) > 0 else { return false }
        var ok = false
        q.sync {
            ok = transactionLocked {
                guard runLocked("""
                    UPDATE knowledge_units SET
                        kind=?,canonical_text=?,subject=?,predicate=?,object_text=?,numeric_value=?,
                        value_unit=?,owner=?,due_text=?,valid_from=?,valid_to=?,review_status='edited',
                        conflict_status=?,sensitivity=?,fingerprint=?,revision=?,updated_at=?
                    WHERE id=? AND review_status IN ('candidate','confirmed','edited')
                    """, [unit.kind.rawValue, unit.canonicalText, unit.subject, unit.predicate,
                            unit.objectText, unit.numericValue, unit.valueUnit, unit.owner, unit.dueText,
                            unit.validFrom, unit.validTo, unit.conflictStatus.rawValue,
                            unit.sensitivity.rawValue, unit.fingerprint, unit.revision,
                            unit.updatedAt, unit.id]),
                      sqlite3_changes(handle) == 1,
                      runLocked("UPDATE unit_sources SET verified=1 WHERE unit_id=?", [unit.id]),
                      runLocked("""
                          INSERT INTO feedback_events(
                              id,target_type,target_id,action,before_json,after_json,reason,actor,created_at
                          ) VALUES(?,?,?,?,?,?,?,?,?)
                          """, [feedback.id, feedback.targetType, feedback.targetID,
                                  feedback.action.rawValue, feedback.beforeJSON, feedback.afterJSON,
                                  feedback.reason, feedback.actor, feedback.createdAt]),
                      runLocked("DELETE FROM knowledge_fts WHERE doc_type='unit' AND doc_id=?", [unit.id])
                else { return false }
                var projectID: String?
                queryLocked("""
                    SELECT project_id FROM unit_projects WHERE unit_id=?
                    ORDER BY review_status='confirmed' DESC,relevance DESC LIMIT 1
                    """, [unit.id]) { projectID = $0[0] }
                let context = [unit.subject, unit.predicate, unit.objectText]
                    .compactMap { $0 }.joined(separator: " ")
                return runLocked("""
                    INSERT INTO knowledge_fts(
                        doc_type,doc_id,meeting_id,project_id,title,body,context
                    ) VALUES('unit',?,?,?,?,?,?)
                    """, [unit.id, meetingID, projectID, meetingTitle,
                            unit.canonicalText, context])
            }
        }
        return ok
    }

    private func scalarKnowledgeSupportCount(unitID: String) -> Int {
        q.sync {
            scalarIntLocked("""
                SELECT COUNT(*) FROM unit_sources
                WHERE unit_id=? AND evidence_role='support'
                """, [unitID])
        }
    }

    @discardableResult
    func rejectKnowledgeUnit(id: String,
                             feedback: KnowledgeFeedbackEvent,
                             now: TimeInterval) -> Bool {
        guard knowledgeHealthy,
              feedback.targetType == "knowledge_unit",
              feedback.targetID == id,
              feedback.action == .reject else { return false }
        var ok = false
        q.sync {
            var status: KnowledgeReviewStatus?
            queryLocked("SELECT review_status FROM knowledge_units WHERE id=?", [id]) {
                status = $0[0].flatMap(KnowledgeReviewStatus.init(rawValue:))
            }
            if status == .rejected { ok = true; return }
            guard status != nil else { return }
            ok = transactionLocked {
                runLocked("UPDATE knowledge_units SET review_status='rejected',updated_at=? WHERE id=?",
                          [now, id])
                    && sqlite3_changes(handle) == 1
                    && runLocked("DELETE FROM knowledge_fts WHERE doc_type='unit' AND doc_id=?", [id])
                    && runLocked("""
                        INSERT INTO feedback_events(
                            id,target_type,target_id,action,before_json,after_json,reason,actor,created_at
                        ) VALUES(?,?,?,?,?,?,?,?,?)
                        """, [feedback.id, feedback.targetType, feedback.targetID,
                                feedback.action.rawValue, feedback.beforeJSON, feedback.afterJSON,
                                feedback.reason, feedback.actor, feedback.createdAt])
            }
        }
        return ok
    }

    @discardableResult
    func restoreKnowledgeUnit(id: String,
                              feedback: KnowledgeFeedbackEvent,
                              meetingID: String,
                              meetingTitle: String,
                              now: TimeInterval) -> Bool {
        guard knowledgeHealthy,
              feedback.targetType == "knowledge_unit",
              feedback.targetID == id,
              feedback.action == .restore,
              scalarKnowledgeSupportCount(unitID: id) > 0 else { return false }
        var ok = false
        q.sync {
            var body: String?
            var context = ""
            queryLocked("""
                SELECT canonical_text,subject,predicate,object_text,review_status
                FROM knowledge_units WHERE id=?
                """, [id]) { row in
                guard row[4] == KnowledgeReviewStatus.rejected.rawValue else { return }
                body = row[0]
                context = [row[1], row[2], row[3]].compactMap { $0 }.joined(separator: " ")
            }
            guard let body else { return }
            var projectID: String?
            queryLocked("""
                SELECT project_id FROM unit_projects WHERE unit_id=?
                ORDER BY review_status='confirmed' DESC,relevance DESC LIMIT 1
                """, [id]) { projectID = $0[0] }
            ok = transactionLocked {
                runLocked("UPDATE knowledge_units SET review_status='candidate',updated_at=? WHERE id=? AND review_status='rejected'",
                          [now, id])
                    && sqlite3_changes(handle) == 1
                    && runLocked("UPDATE unit_sources SET verified=0 WHERE unit_id=?", [id])
                    && runLocked("""
                        INSERT INTO feedback_events(
                            id,target_type,target_id,action,before_json,after_json,reason,actor,created_at
                        ) VALUES(?,?,?,?,?,?,?,?,?)
                        """, [feedback.id, feedback.targetType, feedback.targetID,
                                feedback.action.rawValue, feedback.beforeJSON, feedback.afterJSON,
                                feedback.reason, feedback.actor, feedback.createdAt])
                    && runLocked("""
                        INSERT INTO knowledge_fts(
                            doc_type,doc_id,meeting_id,project_id,title,body,context
                        ) VALUES('unit',?,?,?,?,?,?)
                        """, [id, meetingID, projectID, meetingTitle, body, context])
            }
        }
        return ok
    }

    @discardableResult
    func resolveKnowledgeConflict(primaryID: String,
                                  otherID: String,
                                  resolution: KnowledgeConflictResolution,
                                  feedback: KnowledgeFeedbackEvent,
                                  now: TimeInterval) -> Bool {
        guard knowledgeHealthy,
              primaryID != otherID,
              feedback.targetType == "knowledge_unit",
              feedback.targetID == primaryID,
              feedback.action == .relate else { return false }
        var ok = false
        q.sync {
            let existing = scalarIntLocked(
                "SELECT COUNT(*) FROM knowledge_units WHERE id IN (?,?) AND review_status<>'rejected'",
                [primaryID, otherID])
            guard existing == 2 else { return }
            ok = transactionLocked {
                guard runLocked("""
                    UPDATE knowledge_units SET conflict_status='resolved',updated_at=?
                    WHERE id IN (?,?)
                    """, [now, primaryID, otherID]) else { return false }
                if resolution == .supersedes {
                    guard runLocked("""
                        UPDATE knowledge_units SET valid_to=COALESCE(valid_to,?),updated_at=?
                        WHERE id=?
                        """, [now, now, otherID]) else { return false }
                }
                if resolution != .keepBoth {
                    let relationKind: KnowledgeRelationKind = resolution == .supersedes
                        ? .supersedes : .contradicts
                    guard runLocked("""
                        INSERT INTO unit_relations(
                            from_unit_id,to_unit_id,relation_kind,review_status,reason,payload_json,created_at
                        ) VALUES(?,?,?,'confirmed',?,'{}',?)
                        ON CONFLICT(from_unit_id,to_unit_id,relation_kind) DO UPDATE SET
                            review_status='confirmed',reason=excluded.reason
                        """, [primaryID, otherID, relationKind.rawValue,
                                feedback.reason ?? "用户处理知识冲突", now]) else { return false }
                }
                return runLocked("""
                    INSERT INTO feedback_events(
                        id,target_type,target_id,action,before_json,after_json,reason,actor,created_at
                    ) VALUES(?,?,?,?,?,?,?,?,?)
                    """, [feedback.id, feedback.targetType, feedback.targetID,
                            feedback.action.rawValue, feedback.beforeJSON, feedback.afterJSON,
                            feedback.reason, feedback.actor, feedback.createdAt])
            }
        }
        return ok
    }

    @discardableResult
    func mergeKnowledgeUnits(primaryID: String,
                             duplicateID: String,
                             feedback: KnowledgeFeedbackEvent,
                             now: TimeInterval) -> Bool {
        guard knowledgeHealthy,
              primaryID != duplicateID,
              feedback.targetType == "knowledge_unit",
              feedback.targetID == duplicateID,
              feedback.action == .merge else { return false }
        var ok = false
        q.sync {
            var primaryStatus: KnowledgeReviewStatus?
            var duplicateStatus: KnowledgeReviewStatus?
            var primaryFingerprint: String?
            var duplicateFingerprint: String?
            queryLocked("SELECT review_status,fingerprint FROM knowledge_units WHERE id=?", [primaryID]) {
                primaryStatus = $0[0].flatMap(KnowledgeReviewStatus.init(rawValue:))
                primaryFingerprint = $0[1]
            }
            queryLocked("SELECT review_status,fingerprint FROM knowledge_units WHERE id=?", [duplicateID]) {
                duplicateStatus = $0[0].flatMap(KnowledgeReviewStatus.init(rawValue:))
                duplicateFingerprint = $0[1]
            }
            guard let primaryStatus, let duplicateStatus,
                  primaryStatus != .rejected, duplicateStatus != .rejected,
                  primaryFingerprint == duplicateFingerprint else { return }
            let mergedStatus: KnowledgeReviewStatus
            if primaryStatus == .edited || duplicateStatus == .edited { mergedStatus = .edited }
            else if primaryStatus == .confirmed || duplicateStatus == .confirmed { mergedStatus = .confirmed }
            else { mergedStatus = .candidate }

            ok = transactionLocked {
                guard runLocked("""
                    INSERT INTO unit_sources(unit_id,segment_id,evidence_role,quote,weight,verified)
                    SELECT ?,segment_id,evidence_role,quote,weight,verified
                    FROM unit_sources WHERE unit_id=?
                    ON CONFLICT(unit_id,segment_id,evidence_role) DO UPDATE SET
                        quote=excluded.quote,
                        weight=MAX(unit_sources.weight,excluded.weight),
                        verified=MAX(unit_sources.verified,excluded.verified)
                    """, [primaryID, duplicateID]),
                      runLocked("""
                    INSERT INTO unit_projects(
                        unit_id,project_id,role,relevance,assignment_source,review_status
                    )
                    SELECT ?,project_id,role,relevance,assignment_source,review_status
                    FROM unit_projects WHERE unit_id=?
                    ON CONFLICT(unit_id,project_id) DO UPDATE SET
                        relevance=MAX(unit_projects.relevance,excluded.relevance),
                        assignment_source=CASE
                            WHEN unit_projects.assignment_source='user' OR excluded.assignment_source='user'
                            THEN 'user' ELSE unit_projects.assignment_source END,
                        review_status=CASE
                            WHEN unit_projects.review_status='confirmed' OR excluded.review_status='confirmed'
                            THEN 'confirmed'
                            WHEN unit_projects.review_status='candidate' OR excluded.review_status='candidate'
                            THEN 'candidate' ELSE 'rejected' END
                    """, [primaryID, duplicateID]),
                      runLocked("UPDATE knowledge_units SET review_status=?,updated_at=? WHERE id=?",
                                [mergedStatus.rawValue, now, primaryID]),
                      runLocked("UPDATE knowledge_units SET review_status='rejected',updated_at=? WHERE id=?",
                                [now, duplicateID]),
                      runLocked("DELETE FROM knowledge_fts WHERE doc_type='unit' AND doc_id=?", [duplicateID]),
                      runLocked("""
                    INSERT INTO unit_relations(
                        from_unit_id,to_unit_id,relation_kind,review_status,reason,payload_json,created_at
                    ) VALUES(?,?,'same_as','confirmed',?,'{}',?)
                    ON CONFLICT(from_unit_id,to_unit_id,relation_kind) DO UPDATE SET
                        review_status='confirmed',reason=excluded.reason
                    """, [duplicateID, primaryID, feedback.reason ?? "用户合并重复知识", now]),
                      runLocked("""
                    INSERT INTO feedback_events(
                        id,target_type,target_id,action,before_json,after_json,reason,actor,created_at
                    ) VALUES(?,?,?,?,?,?,?,?,?)
                    """, [feedback.id, feedback.targetType, feedback.targetID,
                            feedback.action.rawValue, feedback.beforeJSON, feedback.afterJSON,
                            feedback.reason, feedback.actor, feedback.createdAt])
                else { return false }
                if mergedStatus == .confirmed || mergedStatus == .edited {
                    return runLocked("UPDATE unit_sources SET verified=1 WHERE unit_id=?", [primaryID])
                }
                return true
            }
        }
        return ok
    }

    @discardableResult
    func commitKnowledgeChunk(_ commits: [KnowledgeUnitCommit],
                              jobID: String,
                              nextCursor: Int,
                              now: TimeInterval) -> Bool {
        guard knowledgeHealthy,
              commits.allSatisfy({ commit in
                  commit.evidence.allSatisfy { $0.unitID == commit.unit.id }
                      && commit.projectLinks.allSatisfy { $0.unitID == commit.unit.id }
                      && commit.suggestedRelations.allSatisfy { $0.fromUnitID == commit.unit.id }
              }) else { return false }
        var ok = false
        q.sync {
            ok = transactionLocked {
                for commit in commits where !saveKnowledgeCommitLocked(commit) { return false }
                return runLocked("""
                    UPDATE extraction_jobs SET cursor=?,updated_at=?
                    WHERE id=? AND state='running'
                    """, [max(0, nextCursor), now, jobID])
                    && sqlite3_changes(handle) == 1
            }
        }
        return ok
    }

    private func saveKnowledgeCommitLocked(_ commit: KnowledgeUnitCommit) -> Bool {
        let unit = commit.unit
        var existingStatus: KnowledgeReviewStatus?
        queryLocked("SELECT review_status FROM knowledge_units WHERE id=?", [unit.id]) { row in
            existingStatus = row[0].flatMap(KnowledgeReviewStatus.init(rawValue:))
        }
        if let existingStatus, existingStatus != .candidate { return true }
        guard runLocked("""
            INSERT INTO knowledge_units(
                id,kind,canonical_text,subject,predicate,object_text,numeric_value,value_unit,
                owner,due_text,valid_from,valid_to,observed_at,review_status,evidence_level,
                conflict_status,sensitivity,fingerprint,revision,extractor_version,prompt_version,
                schema_version,model,payload_json,created_at,updated_at
            ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            ON CONFLICT(id) DO UPDATE SET
                kind=excluded.kind,
                canonical_text=excluded.canonical_text,
                subject=excluded.subject,
                predicate=excluded.predicate,
                object_text=excluded.object_text,
                numeric_value=excluded.numeric_value,
                value_unit=excluded.value_unit,
                owner=excluded.owner,
                due_text=excluded.due_text,
                valid_from=excluded.valid_from,
                valid_to=excluded.valid_to,
                observed_at=excluded.observed_at,
                review_status=excluded.review_status,
                evidence_level=excluded.evidence_level,
                conflict_status=excluded.conflict_status,
                sensitivity=excluded.sensitivity,
                fingerprint=excluded.fingerprint,
                revision=excluded.revision,
                extractor_version=excluded.extractor_version,
                prompt_version=excluded.prompt_version,
                schema_version=excluded.schema_version,
                model=excluded.model,
                payload_json=excluded.payload_json,
                updated_at=excluded.updated_at
            """, [unit.id, unit.kind.rawValue, unit.canonicalText, unit.subject,
                    unit.predicate, unit.objectText, unit.numericValue, unit.valueUnit,
                    unit.owner, unit.dueText, unit.validFrom, unit.validTo, unit.observedAt,
                    unit.reviewStatus.rawValue, unit.evidenceLevel.rawValue,
                    unit.conflictStatus.rawValue, unit.sensitivity.rawValue, unit.fingerprint,
                    unit.revision, unit.extractorVersion, unit.promptVersion, unit.schemaVersion,
                    unit.model, unit.payloadJSON, unit.createdAt, unit.updatedAt]),
              runLocked("DELETE FROM unit_sources WHERE unit_id=?", [unit.id]),
              runLocked("DELETE FROM unit_projects WHERE unit_id=?", [unit.id])
        else { return false }

        for source in commit.evidence {
            guard runLocked("""
                INSERT INTO unit_sources(
                    unit_id,segment_id,evidence_role,quote,weight,verified
                ) VALUES(?,?,?,?,?,?)
                """, [source.unitID, source.segmentID, source.evidenceRole.rawValue,
                        source.quote, source.weight, source.verified ? 1 : 0]) else { return false }
        }
        for link in commit.projectLinks {
            guard runLocked("""
                INSERT INTO unit_projects(
                    unit_id,project_id,role,relevance,assignment_source,review_status
                ) VALUES(?,?,?,?,?,?)
                """, [link.unitID, link.projectID, link.role, link.relevance,
                        link.assignmentSource.rawValue, link.reviewStatus.rawValue]) else { return false }
        }
        guard runLocked("DELETE FROM unit_relations WHERE from_unit_id=? AND review_status='candidate'", [unit.id]) else {
            return false
        }
        for relation in commit.suggestedRelations {
            guard runLocked("""
                INSERT INTO unit_relations(
                    from_unit_id,to_unit_id,relation_kind,review_status,reason,payload_json,created_at
                ) VALUES(?,?,?,?,?,?,?)
                ON CONFLICT(from_unit_id,to_unit_id,relation_kind) DO UPDATE SET
                    review_status=excluded.review_status,
                    reason=excluded.reason,
                    payload_json=excluded.payload_json
                """, [relation.fromUnitID, relation.toUnitID, relation.relationKind.rawValue,
                        relation.reviewStatus.rawValue, relation.reason, relation.payloadJSON,
                        relation.createdAt]) else { return false }
        }
        guard runLocked("DELETE FROM knowledge_fts WHERE doc_type='unit' AND doc_id=?", [unit.id]) else {
            return false
        }
        if unit.reviewStatus != .rejected {
            let projectID = commit.projectLinks.first(where: { $0.reviewStatus == .confirmed })?.projectID
                ?? commit.projectLinks.first?.projectID
            let context = [unit.subject, unit.predicate, unit.objectText]
                .compactMap { $0 }.joined(separator: " ")
            guard runLocked("""
                INSERT INTO knowledge_fts(
                    doc_type,doc_id,meeting_id,project_id,title,body,context
                ) VALUES('unit',?,?,?,?,?,?)
                """, [unit.id, commit.meetingID, projectID, commit.meetingTitle,
                        unit.canonicalText, context]) else { return false }
        }
        return true
    }

    func knowledgeUnits() -> [KnowledgeUnit] {
        guard knowledgeHealthy else { return [] }
        var output: [KnowledgeUnit] = []
        q.sync {
            queryLocked("""
                SELECT id,kind,canonical_text,subject,predicate,object_text,numeric_value,value_unit,
                       owner,due_text,valid_from,valid_to,observed_at,review_status,evidence_level,
                       conflict_status,sensitivity,fingerprint,revision,extractor_version,prompt_version,
                       schema_version,model,payload_json,created_at,updated_at
                FROM knowledge_units ORDER BY observed_at DESC, created_at DESC
                """) { row in
                guard let id = row[0], let kindRaw = row[1], let kind = KnowledgeKind(rawValue: kindRaw),
                      let text = row[2], let observed = Double(row[12] ?? ""),
                      let reviewRaw = row[13], let review = KnowledgeReviewStatus(rawValue: reviewRaw),
                      let evidenceRaw = row[14], let evidence = KnowledgeEvidenceLevel(rawValue: evidenceRaw),
                      let conflictRaw = row[15], let conflict = KnowledgeConflictStatus(rawValue: conflictRaw),
                      let sensitivityRaw = row[16], let sensitivity = KnowledgeSensitivity(rawValue: sensitivityRaw),
                      let fingerprint = row[17], let revision = Int(row[18] ?? ""),
                      let extractor = row[19], let prompt = row[20], let schema = Int(row[21] ?? ""),
                      let model = row[22], let payload = row[23], let created = Double(row[24] ?? ""),
                      let updated = Double(row[25] ?? "") else { return }
                output.append(KnowledgeUnit(
                    id: id, kind: kind, canonicalText: text, subject: row[3], predicate: row[4],
                    objectText: row[5], numericValue: row[6].flatMap(Double.init), valueUnit: row[7],
                    owner: row[8], dueText: row[9], validFrom: row[10].flatMap(Double.init),
                    validTo: row[11].flatMap(Double.init), observedAt: observed,
                    reviewStatus: review, evidenceLevel: evidence, conflictStatus: conflict,
                    sensitivity: sensitivity, fingerprint: fingerprint, revision: revision,
                    extractorVersion: extractor, promptVersion: prompt, schemaVersion: schema,
                    model: model, payloadJSON: payload, createdAt: created, updatedAt: updated))
            }
        }
        return output
    }

    func knowledgeEvidence(unitID: String? = nil) -> [KnowledgeUnitSource] {
        guard knowledgeHealthy else { return [] }
        var output: [KnowledgeUnitSource] = []
        q.sync {
            let sql = """
                SELECT unit_id,segment_id,evidence_role,quote,weight,verified
                FROM unit_sources
                """ + (unitID == nil ? " ORDER BY unit_id,weight DESC,segment_id" : " WHERE unit_id=? ORDER BY weight DESC,segment_id")
            let binds: [Any?] = unitID.map { [$0] } ?? []
            queryLocked(sql, binds) { row in
                guard let unit = row[0], let segment = row[1], let roleRaw = row[2],
                      let role = KnowledgeEvidenceRole(rawValue: roleRaw), let quote = row[3],
                      let weight = Double(row[4] ?? ""), let verified = Int(row[5] ?? "") else { return }
                output.append(KnowledgeUnitSource(
                    unitID: unit, segmentID: segment, evidenceRole: role,
                    quote: quote, weight: weight, verified: verified == 1))
            }
        }
        return output
    }

    func knowledgeProjectLinks(unitID: String? = nil) -> [KnowledgeUnitProject] {
        guard knowledgeHealthy else { return [] }
        var output: [KnowledgeUnitProject] = []
        q.sync {
            let sql = """
                SELECT unit_id,project_id,role,relevance,assignment_source,review_status
                FROM unit_projects
                """ + (unitID == nil ? " ORDER BY unit_id,relevance DESC,project_id" : " WHERE unit_id=? ORDER BY relevance DESC,project_id")
            let binds: [Any?] = unitID.map { [$0] } ?? []
            queryLocked(sql, binds) { row in
                guard let unit = row[0], let project = row[1], let role = row[2],
                      let relevance = Double(row[3] ?? ""), let sourceRaw = row[4],
                      let source = KnowledgeAssignmentSource(rawValue: sourceRaw),
                      let reviewRaw = row[5], let review = KnowledgeLinkReviewStatus(rawValue: reviewRaw)
                else { return }
                output.append(KnowledgeUnitProject(
                    unitID: unit, projectID: project, role: role, relevance: relevance,
                    assignmentSource: source, reviewStatus: review))
            }
        }
        return output
    }

    @discardableResult
    func saveKnowledgeProject(_ project: KnowledgeProject) -> Bool {
        guard knowledgeHealthy,
              let aliasesData = try? JSONEncoder().encode(project.aliases),
              let aliasesJSON = String(data: aliasesData, encoding: .utf8) else { return false }
        var ok = false
        q.sync {
            ok = runLocked("""
                INSERT INTO projects(id,name,normalized_name,aliases_json,status,created_at,updated_at)
                VALUES(?,?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET
                    name=excluded.name,
                    normalized_name=excluded.normalized_name,
                    aliases_json=excluded.aliases_json,
                    status=excluded.status,
                    updated_at=excluded.updated_at
                """, [project.id, project.name, project.normalizedName, aliasesJSON,
                        project.status.rawValue, project.createdAt, project.updatedAt])
        }
        return ok
    }

    func knowledgeProjects() -> [KnowledgeProject] {
        guard knowledgeHealthy else { return [] }
        var output: [KnowledgeProject] = []
        q.sync {
            queryLocked("""
                SELECT id,name,normalized_name,aliases_json,status,created_at,updated_at
                FROM projects ORDER BY status='archived', updated_at DESC
                """) { row in
                guard let id = row[0], let name = row[1], let normalized = row[2],
                      let aliasesJSON = row[3], let aliasesData = aliasesJSON.data(using: .utf8),
                      let aliases = try? JSONDecoder().decode([String].self, from: aliasesData),
                      let statusRaw = row[4], let status = KnowledgeProjectStatus(rawValue: statusRaw),
                      let created = Double(row[5] ?? ""), let updated = Double(row[6] ?? "") else { return }
                output.append(KnowledgeProject(
                    id: id, name: name, normalizedName: normalized, aliases: aliases,
                    status: status, createdAt: created, updatedAt: updated))
            }
        }
        return output
    }

    @discardableResult
    func saveKnowledgeRelation(_ relation: KnowledgeUnitRelation) -> Bool {
        guard knowledgeHealthy else { return false }
        var ok = false
        q.sync {
            ok = runLocked("""
                INSERT INTO unit_relations(
                    from_unit_id,to_unit_id,relation_kind,review_status,reason,payload_json,created_at
                ) VALUES(?,?,?,?,?,?,?)
                ON CONFLICT(from_unit_id,to_unit_id,relation_kind) DO UPDATE SET
                    review_status=excluded.review_status,
                    reason=excluded.reason,
                    payload_json=excluded.payload_json
                """, [relation.fromUnitID, relation.toUnitID, relation.relationKind.rawValue,
                        relation.reviewStatus.rawValue, relation.reason, relation.payloadJSON,
                        relation.createdAt])
        }
        return ok
    }

    func knowledgeRelations(unitID: String) -> [KnowledgeUnitRelation] {
        guard knowledgeHealthy else { return [] }
        var output: [KnowledgeUnitRelation] = []
        q.sync {
            queryLocked("""
                SELECT from_unit_id,to_unit_id,relation_kind,review_status,reason,payload_json,created_at
                FROM unit_relations WHERE from_unit_id=? OR to_unit_id=? ORDER BY created_at
                """, [unitID, unitID]) { row in
                guard let from = row[0], let to = row[1], let kindRaw = row[2],
                      let kind = KnowledgeRelationKind(rawValue: kindRaw), let reviewRaw = row[3],
                      let review = KnowledgeLinkReviewStatus(rawValue: reviewRaw),
                      let payload = row[5], let created = Double(row[6] ?? "") else { return }
                output.append(KnowledgeUnitRelation(
                    fromUnitID: from, toUnitID: to, relationKind: kind, reviewStatus: review,
                    reason: row[4], payloadJSON: payload, createdAt: created))
            }
        }
        return output
    }

    @discardableResult
    func appendKnowledgeFeedback(_ event: KnowledgeFeedbackEvent) -> Bool {
        guard knowledgeHealthy else { return false }
        var ok = false
        q.sync {
            ok = runLocked("""
                INSERT INTO feedback_events(
                    id,target_type,target_id,action,before_json,after_json,reason,actor,created_at
                ) VALUES(?,?,?,?,?,?,?,?,?)
                """, [event.id, event.targetType, event.targetID, event.action.rawValue,
                        event.beforeJSON, event.afterJSON, event.reason, event.actor, event.createdAt])
        }
        return ok
    }

    func knowledgeFeedback(targetType: String, targetID: String) -> [KnowledgeFeedbackEvent] {
        guard knowledgeHealthy else { return [] }
        var output: [KnowledgeFeedbackEvent] = []
        q.sync {
            queryLocked("""
                SELECT id,target_type,target_id,action,before_json,after_json,reason,actor,created_at
                FROM feedback_events WHERE target_type=? AND target_id=? ORDER BY created_at
                """, [targetType, targetID]) { row in
                guard let id = row[0], let type = row[1], let target = row[2],
                      let actionRaw = row[3], let action = KnowledgeFeedbackAction(rawValue: actionRaw),
                      let actor = row[7], let created = Double(row[8] ?? "") else { return }
                output.append(KnowledgeFeedbackEvent(
                    id: id, targetType: type, targetID: target, action: action,
                    beforeJSON: row[4], afterJSON: row[5], reason: row[6], actor: actor,
                    createdAt: created))
            }
        }
        return output
    }

    @discardableResult
    func saveKnowledgeJob(_ job: KnowledgeExtractionJob) -> Bool {
        guard knowledgeHealthy else { return false }
        var ok = false
        q.sync {
            ok = runLocked("""
                INSERT INTO extraction_jobs(
                    id,source_id,job_kind,state,input_hash,extractor_version,cursor,attempt,
                    next_retry_at,lease_until,last_error,created_at,updated_at
                ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET
                    source_id=excluded.source_id,
                    job_kind=excluded.job_kind,
                    state=excluded.state,
                    input_hash=excluded.input_hash,
                    extractor_version=excluded.extractor_version,
                    cursor=excluded.cursor,
                    attempt=excluded.attempt,
                    next_retry_at=excluded.next_retry_at,
                    lease_until=excluded.lease_until,
                    last_error=excluded.last_error,
                    updated_at=excluded.updated_at
                """, [job.id, job.sourceID, job.jobKind.rawValue, job.state.rawValue,
                        job.inputHash, job.extractorVersion, job.cursor, job.attempt,
                        job.nextRetryAt, job.leaseUntil, job.lastError, job.createdAt, job.updatedAt])
        }
        return ok
    }

    private func decodeKnowledgeJob(_ row: [String?]) -> KnowledgeExtractionJob? {
        guard row.count >= 13,
              let id = row[0], let source = row[1], let kindRaw = row[2],
              let kind = KnowledgeExtractionJobKind(rawValue: kindRaw), let stateRaw = row[3],
              let state = KnowledgeExtractionJobState(rawValue: stateRaw), let hash = row[4],
              let extractor = row[5], let cursor = Int(row[6] ?? ""),
              let attempt = Int(row[7] ?? ""), let created = Double(row[11] ?? ""),
              let updated = Double(row[12] ?? "") else { return nil }
        return KnowledgeExtractionJob(
            id: id, sourceID: source, jobKind: kind, state: state, inputHash: hash,
            extractorVersion: extractor, cursor: cursor, attempt: attempt,
            nextRetryAt: row[8].flatMap(Double.init), leaseUntil: row[9].flatMap(Double.init),
            lastError: row[10], createdAt: created, updatedAt: updated)
    }

    func knowledgeJobs() -> [KnowledgeExtractionJob] {
        guard knowledgeHealthy else { return [] }
        var output: [KnowledgeExtractionJob] = []
        q.sync {
            queryLocked("""
                SELECT id,source_id,job_kind,state,input_hash,extractor_version,cursor,attempt,
                       next_retry_at,lease_until,last_error,created_at,updated_at
                FROM extraction_jobs ORDER BY updated_at, created_at
                """) { row in
                if let job = decodeKnowledgeJob(row) { output.append(job) }
            }
        }
        return output
    }

    func claimNextKnowledgeJob(now: TimeInterval,
                               leaseDuration: TimeInterval,
                               allowedJobIDs: Set<String>? = nil) -> KnowledgeExtractionJob? {
        guard knowledgeHealthy, allowedJobIDs?.isEmpty != true else { return nil }
        var claimed: KnowledgeExtractionJob?
        q.sync {
            let success = transactionLocked {
                guard runLocked("""
                    UPDATE extraction_jobs
                    SET state='retry',lease_until=NULL,next_retry_at=NULL,
                        last_error=COALESCE(last_error,'lease expired'),updated_at=?
                    WHERE state='running' AND lease_until IS NOT NULL AND lease_until<=?
                    """, [now, now]) else { return false }
                var jobID: String?
                let allowed = allowedJobIDs?.sorted()
                let allowedClause = allowed.map {
                    " AND id IN (" + Array(repeating: "?", count: $0.count).joined(separator: ",") + ")"
                } ?? ""
                var claimBinds: [Any?] = [now]
                claimBinds.append(contentsOf: (allowed ?? []).map { $0 as Any? })
                queryLocked("""
                    SELECT id FROM extraction_jobs
                    WHERE (state='pending'
                       OR (state='retry' AND (next_retry_at IS NULL OR next_retry_at<=?)))
                       \(allowedClause)
                    ORDER BY CASE state WHEN 'pending' THEN 0 ELSE 1 END, created_at, id
                    LIMIT 1
                    """, claimBinds) { jobID = $0[0] }
                guard let jobID else { return true }
                guard runLocked("""
                    UPDATE extraction_jobs
                    SET state='running',attempt=attempt+1,next_retry_at=NULL,
                        lease_until=?,last_error=NULL,updated_at=?
                    WHERE id=? AND (state='pending' OR state='retry')
                    """, [now + max(1, leaseDuration), now, jobID]) else { return false }
                queryLocked("""
                    SELECT id,source_id,job_kind,state,input_hash,extractor_version,cursor,attempt,
                           next_retry_at,lease_until,last_error,created_at,updated_at
                    FROM extraction_jobs WHERE id=?
                    """, [jobID]) { row in claimed = decodeKnowledgeJob(row) }
                return claimed != nil
            }
            if !success { claimed = nil }
        }
        return claimed
    }

    @discardableResult
    func renewKnowledgeJobLease(id: String,
                                now: TimeInterval,
                                leaseDuration: TimeInterval) -> Bool {
        guard knowledgeHealthy else { return false }
        var ok = false
        q.sync {
            ok = runLocked("""
                UPDATE extraction_jobs SET lease_until=?,updated_at=?
                WHERE id=? AND state='running'
                """, [now + max(1, leaseDuration), now, id])
                && sqlite3_changes(handle) == 1
        }
        return ok
    }

    @discardableResult
    func transitionKnowledgeJob(id: String,
                                state: KnowledgeExtractionJobState,
                                cursor: Int,
                                nextRetryAt: TimeInterval?,
                                lastError: String?,
                                now: TimeInterval) -> Bool {
        guard knowledgeHealthy else { return false }
        var ok = false
        q.sync {
            ok = runLocked("""
                UPDATE extraction_jobs
                SET state=?,cursor=?,next_retry_at=?,lease_until=NULL,last_error=?,updated_at=?
                WHERE id=?
                """, [state.rawValue, max(0, cursor), nextRetryAt, lastError, now, id])
                && sqlite3_changes(handle) == 1
        }
        return ok
    }

    @discardableResult
    func resetKnowledgeJobForRetry(id: String, now: TimeInterval) -> Bool {
        guard knowledgeHealthy else { return false }
        var ok = false
        q.sync {
            ok = runLocked("""
                UPDATE extraction_jobs
                SET state='pending',attempt=0,next_retry_at=NULL,lease_until=NULL,last_error=NULL,updated_at=?
                WHERE id=? AND state IN ('failed','cancelled')
                """, [now, id]) && sqlite3_changes(handle) == 1
        }
        return ok
    }

    @discardableResult
    func appendKnowledgeExtractionDiagnostic(_ diagnostic: KnowledgeExtractionDiagnostic) -> Bool {
        guard knowledgeHealthy else { return false }
        var ok = false
        q.sync {
            ok = runLocked("""
                INSERT INTO extraction_diagnostics(
                    id,job_id,source_id,chunk_index,input_characters,output_characters,
                    candidate_count,accepted_count,invalid_evidence_count,duration_ms,
                    retry_count,outcome,error_code,created_at
                ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                """, [diagnostic.id, diagnostic.jobID, diagnostic.sourceID,
                        diagnostic.chunkIndex, diagnostic.inputCharacters,
                        diagnostic.outputCharacters, diagnostic.candidateCount,
                        diagnostic.acceptedCount, diagnostic.invalidEvidenceCount,
                        diagnostic.durationMS, diagnostic.retryCount,
                        diagnostic.outcome.rawValue, diagnostic.errorCode,
                        diagnostic.createdAt])
        }
        return ok
    }

    func knowledgeExtractionDiagnostics(jobID: String? = nil) -> [KnowledgeExtractionDiagnostic] {
        guard knowledgeHealthy else { return [] }
        var output: [KnowledgeExtractionDiagnostic] = []
        q.sync {
            let sql = """
                SELECT id,job_id,source_id,chunk_index,input_characters,output_characters,
                       candidate_count,accepted_count,invalid_evidence_count,duration_ms,
                       retry_count,outcome,error_code,created_at
                FROM extraction_diagnostics
                """ + (jobID == nil ? " ORDER BY created_at" : " WHERE job_id=? ORDER BY chunk_index,created_at")
            let binds: [Any?] = jobID.map { [$0] } ?? []
            queryLocked(sql, binds) { row in
                guard let id = row[0], let job = row[1], let source = row[2],
                      let chunk = Int(row[3] ?? ""), let input = Int(row[4] ?? ""),
                      let outputCount = Int(row[5] ?? ""), let candidates = Int(row[6] ?? ""),
                      let accepted = Int(row[7] ?? ""), let invalid = Int(row[8] ?? ""),
                      let duration = Int(row[9] ?? ""), let retries = Int(row[10] ?? ""),
                      let outcomeRaw = row[11],
                      let outcome = KnowledgeExtractionDiagnosticOutcome(rawValue: outcomeRaw),
                      let created = Double(row[13] ?? "") else { return }
                output.append(KnowledgeExtractionDiagnostic(
                    id: id, jobID: job, sourceID: source, chunkIndex: chunk,
                    inputCharacters: input, outputCharacters: outputCount,
                    candidateCount: candidates, acceptedCount: accepted,
                    invalidEvidenceCount: invalid, durationMS: duration,
                    retryCount: retries, outcome: outcome, errorCode: row[12],
                    createdAt: created))
            }
        }
        return output
    }

    func knowledgeDiagnostics() -> KnowledgeDatabaseDiagnostics {
        var counts: [String: Int] = [:]
        var jobs: [String: Int] = [:]
        var foreignKeyViolations = 0
        var orphanReferences = 0
        var missingFTSRows = 0
        var orphanFTSRows = 0
        var duplicateFTSRows = 0
        q.sync {
            for table in [
                "meetings", "meetings_fts", "source_documents", "source_segments",
                "knowledge_units", "unit_sources", "projects", "unit_projects",
                "unit_relations", "feedback_events", "extraction_jobs", "extraction_diagnostics",
                "knowledge_fts"
            ] {
                counts[table] = scalarIntLocked("SELECT COUNT(*) FROM \(table)")
            }
            queryLocked("SELECT state,COUNT(*) FROM extraction_jobs GROUP BY state") { row in
                if let state = row[0] { jobs[state] = Int(row[1] ?? "0") ?? 0 }
            }
            queryLocked("PRAGMA foreign_key_check") { _ in foreignKeyViolations += 1 }
            orphanReferences = scalarIntLocked("""
                SELECT
                    (SELECT COUNT(*) FROM source_segments s
                        LEFT JOIN source_documents d ON d.id=s.source_id WHERE d.id IS NULL) +
                    (SELECT COUNT(*) FROM unit_sources us
                        LEFT JOIN knowledge_units u ON u.id=us.unit_id
                        LEFT JOIN source_segments s ON s.id=us.segment_id
                        WHERE u.id IS NULL OR s.id IS NULL) +
                    (SELECT COUNT(*) FROM unit_projects up
                        LEFT JOIN knowledge_units u ON u.id=up.unit_id
                        LEFT JOIN projects p ON p.id=up.project_id
                        WHERE u.id IS NULL OR p.id IS NULL) +
                    (SELECT COUNT(*) FROM unit_relations r
                        LEFT JOIN knowledge_units f ON f.id=r.from_unit_id
                        LEFT JOIN knowledge_units t ON t.id=r.to_unit_id
                        WHERE f.id IS NULL OR t.id IS NULL) +
                    (SELECT COUNT(*) FROM extraction_jobs j
                        LEFT JOIN source_documents d ON d.id=j.source_id WHERE d.id IS NULL) +
                    (SELECT COUNT(*) FROM extraction_diagnostics x
                        LEFT JOIN extraction_jobs j ON j.id=x.job_id
                        LEFT JOIN source_documents d ON d.id=x.source_id
                        WHERE j.id IS NULL OR d.id IS NULL)
                """)
            missingFTSRows = scalarIntLocked("""
                SELECT
                    (SELECT COUNT(*) FROM source_segments s
                        WHERE NOT EXISTS(
                            SELECT 1 FROM knowledge_fts f
                            WHERE f.doc_type='segment' AND f.doc_id=s.id
                        )) +
                    (SELECT COUNT(*) FROM knowledge_units u
                        WHERE u.review_status <> 'rejected' AND NOT EXISTS(
                            SELECT 1 FROM knowledge_fts f
                            WHERE f.doc_type='unit' AND f.doc_id=u.id
                        ))
                """)
            orphanFTSRows = scalarIntLocked("""
                SELECT COUNT(*) FROM knowledge_fts f
                WHERE (f.doc_type='segment' AND NOT EXISTS(
                           SELECT 1 FROM source_segments s WHERE s.id=f.doc_id
                       ))
                   OR (f.doc_type='unit' AND NOT EXISTS(
                           SELECT 1 FROM knowledge_units u WHERE u.id=f.doc_id AND u.review_status <> 'rejected'
                       ))
                   OR f.doc_type NOT IN ('segment','unit')
                """)
            duplicateFTSRows = scalarIntLocked("""
                SELECT COALESCE(SUM(n - 1), 0) FROM (
                    SELECT COUNT(*) AS n FROM knowledge_fts
                    GROUP BY doc_type,doc_id HAVING COUNT(*) > 1
                )
                """)
        }
        return KnowledgeDatabaseDiagnostics(
            schemaVersion: schemaVersion,
            baseHealthy: healthy,
            knowledgeHealthy: knowledgeHealthy,
            tableCounts: counts,
            jobCounts: jobs,
            foreignKeyViolations: foreignKeyViolations,
            orphanReferences: orphanReferences,
            missingFTSRows: missingFTSRows,
            orphanFTSRows: orphanFTSRows,
            duplicateFTSRows: duplicateFTSRows,
            error: storageError ?? schemaMigrationError ?? legacyMigrationError)
    }

    // MARK: - Knowledge full-text index

    struct KnowledgeFTSDoc {
        let docType: String
        let docID: String
        let meetingID: String
        let projectID: String?
        let title: String
        let body: String
        let context: String
    }

    struct KnowledgeFTSHit: Hashable {
        let docType: String
        let docID: String
    }

    @discardableResult
    func upsertKnowledgeFTSDoc(_ document: KnowledgeFTSDoc) -> Bool {
        guard knowledgeHealthy else { return false }
        var ok = false
        q.sync {
            guard execLocked("BEGIN") else { return }
            ok = runLocked("DELETE FROM knowledge_fts WHERE doc_type=? AND doc_id=?",
                           [document.docType, document.docID])
                && runLocked("""
                    INSERT INTO knowledge_fts(
                        doc_type,doc_id,meeting_id,project_id,title,body,context
                    ) VALUES(?,?,?,?,?,?,?)
                    """, [document.docType, document.docID, document.meetingID,
                            document.projectID, document.title, document.body, document.context])
            if ok { ok = execLocked("COMMIT"); if !ok { execLocked("ROLLBACK") } }
            else { execLocked("ROLLBACK") }
        }
        return ok
    }

    @discardableResult
    func deleteKnowledgeFTSDoc(docType: String, docID: String) -> Bool {
        guard knowledgeHealthy else { return false }
        var ok = false
        q.sync { ok = runLocked("DELETE FROM knowledge_fts WHERE doc_type=? AND doc_id=?", [docType, docID]) }
        return ok
    }

    func searchKnowledgeFTS(tokens: [String], limit: Int = 30) -> [KnowledgeFTSHit] {
        let cleaned = tokens.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard knowledgeHealthy, !cleaned.isEmpty else { return [] }
        var output: [KnowledgeFTSHit] = []
        q.sync {
            if cleaned.allSatisfy({ $0.count >= 3 }) {
                let match = cleaned.map { "\"\($0.replacingOccurrences(of: "\"", with: ""))\"" }
                    .joined(separator: " AND ")
                queryLocked("""
                    SELECT doc_type,doc_id FROM knowledge_fts
                    WHERE knowledge_fts MATCH ? LIMIT ?
                    """, [match, limit]) { row in
                    if let type = row[0], let id = row[1] {
                        output.append(KnowledgeFTSHit(docType: type, docID: id))
                    }
                }
            } else {
                let conditions = cleaned.map { _ in "(title LIKE ? OR body LIKE ? OR context LIKE ?)" }
                    .joined(separator: " AND ")
                var binds: [Any?] = []
                for token in cleaned {
                    let pattern = "%\(token)%"
                    binds += [pattern, pattern, pattern]
                }
                binds.append(limit)
                queryLocked("""
                    SELECT doc_type,doc_id FROM knowledge_fts
                    WHERE \(conditions) LIMIT ?
                    """, binds) { row in
                    if let type = row[0], let id = row[1] {
                        output.append(KnowledgeFTSHit(docType: type, docID: id))
                    }
                }
            }
        }
        return output
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

    @discardableResult
    func setRow(_ table: String, keyCol: String, valCol: String, key: String, value: String) -> Bool {
        q.sync { runLocked("INSERT OR REPLACE INTO \(table)(\(keyCol),\(valCol)) VALUES(?,?)", [key, value]) }
    }

    func kvGet(_ key: String) -> String? {
        var v: String?
        q.sync { queryLocked("SELECT value FROM kv WHERE key=?", [key]) { v = $0[0] } }
        return v
    }
    @discardableResult
    func kvSet(_ key: String, _ value: String) -> Bool {
        q.sync { runLocked("INSERT OR REPLACE INTO kv(key,value) VALUES(?,?)", [key, value]) }
    }

    // MARK: - 首启迁移：旧 JSON → 表；旧文件原地保留（备份）

    private func migrateFromJSONIfNeeded() {
        guard kvGet("migrated_v1") == nil, let base = legacyBaseURL else { return }
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        var failures = Set<String>()

        func dataIfPresent(_ name: String) -> Data? {
            let url = base.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            do { return try Data(contentsOf: url) }
            catch { failures.insert(name); return nil }
        }

        if let data = dataIfPresent("live-meetings.json") {
            var items: [StoredLiveMeeting] = []
            if let decoded = try? decoder.decode([StoredLiveMeeting].self, from: data) {
                items = decoded
            } else if let rawItems = try? JSONSerialization.jsonObject(with: data) as? [Any] {
                items = rawItems.compactMap { object in
                    (try? JSONSerialization.data(withJSONObject: object))
                        .flatMap { try? decoder.decode(StoredLiveMeeting.self, from: $0) }
                }
                if items.count != rawItems.count { failures.insert("live-meetings.json") }
            } else {
                failures.insert("live-meetings.json")
            }
            for meeting in items {
                guard let payload = try? encoder.encode(meeting),
                      let payloadString = String(data: payload, encoding: .utf8),
                      upsertMeeting(
                        id: meeting.id, kind: "live", sortTs: meeting.timestamp,
                        payload: payloadString,
                        fts: FTSDoc(
                            title: meeting.title,
                            summary: meeting.note.summary
                                ?? meeting.note.blocks?.first(where: { $0.type == "summary" })?.text ?? "",
                            transcript: meeting.transcript))
                else { failures.insert("live-meetings.json"); continue }
            }
        }

        if let data = dataIfPresent("meetings.json") {
            if let store = try? decoder.decode(RealStore.self, from: data) {
                for (index, meeting) in store.meetings.enumerated() {
                    guard let payload = try? encoder.encode(meeting),
                          let payloadString = String(data: payload, encoding: .utf8),
                          upsertMeeting(
                            id: meeting.meeting_id, kind: "feishu",
                            sortTs: Double(1_000_000 - index), payload: payloadString,
                            fts: FTSDoc(
                                title: meeting.title, summary: meeting.summary,
                                transcript: meeting.excerpts.map { $0.text }.joined(separator: "\n")))
                    else { failures.insert("meetings.json"); continue }
                }
            } else {
                failures.insert("meetings.json")
            }
        }

        if let data = dataIfPresent("daily-digests.json") {
            if let values = try? decoder.decode([String: [NoteBlock]].self, from: data) {
                for (day, blocks) in values {
                    guard let encoded = try? encoder.encode(blocks),
                          let string = String(data: encoded, encoding: .utf8),
                          setRow("daily", keyCol: "day", valCol: "blocks", key: day, value: string)
                    else { failures.insert("daily-digests.json"); continue }
                }
            } else { failures.insert("daily-digests.json") }
        }

        if let data = dataIfPresent("qa.json") {
            if let values = try? decoder.decode([String: [QATurn]].self, from: data) {
                for (meetingID, turns) in values {
                    guard let encoded = try? encoder.encode(turns),
                          let string = String(data: encoded, encoding: .utf8),
                          setRow("qa", keyCol: "meeting_id", valCol: "turns",
                                 key: meetingID, value: string)
                    else { failures.insert("qa.json"); continue }
                }
            } else { failures.insert("qa.json") }
        }

        if let data = dataIfPresent("task-links.json") {
            if let values = try? decoder.decode([String: String].self, from: data) {
                for (key, guid) in values where
                    !setRow("task_links", keyCol: "key", valCol: "guid", key: key, value: guid) {
                    failures.insert("task-links.json")
                }
            } else { failures.insert("task-links.json") }
        }

        if let data = dataIfPresent("calendar-cache.json") {
            if let string = String(data: data, encoding: .utf8) {
                if !kvSet("cal_cache", string) { failures.insert("calendar-cache.json") }
            } else { failures.insert("calendar-cache.json") }
        }

        finishLegacyMigration(failures)
    }

    private func finishLegacyMigration(_ failures: Set<String>) {
        guard failures.isEmpty else {
            legacyMigrationError = "旧数据迁移未完成：" + failures.sorted().joined(separator: "、")
            return
        }
        if kvSet("migrated_v1", "1") {
            legacyMigrationError = nil
        } else {
            legacyMigrationError = "旧数据已读取，但迁移完成标记写入失败"
        }
    }
}
