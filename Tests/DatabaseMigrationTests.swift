import SQLite3
import XCTest
@testable import AfterMeet

final class DatabaseMigrationTests: XCTestCase {
    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("AfterMeet-Migration-" + UUID().uuidString)
            .appendingPathComponent("aftermeet.db")
    }

    private func execute(_ sql: String, at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &handle), SQLITE_OK)
        defer { sqlite3_close(handle) }
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
            throw NSError(
                domain: "DatabaseMigrationTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(handle))])
        }
    }

    private func scalar(_ sql: String, at url: URL) throws -> String {
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        defer { sqlite3_close(handle) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw NSError(domain: "DatabaseMigrationTests", code: 2)
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let text = sqlite3_column_text(statement, 0) else {
            throw NSError(domain: "DatabaseMigrationTests", code: 3)
        }
        return String(cString: text)
    }

    func testEmptyDatabaseMigratesToCurrentVersion() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let database = DB(databaseURL: url)

        XCTAssertTrue(database.healthy)
        XCTAssertTrue(database.knowledgeHealthy)
        XCTAssertTrue(database.foreignKeysEnabled)
        XCTAssertNil(database.schemaMigrationError)
        XCTAssertEqual(database.schemaVersion, DB.currentSchemaVersion)
    }

    func testMigrationIsIdempotentAcrossReopen() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        do {
            let first = DB(databaseURL: url)
            XCTAssertEqual(first.schemaVersion, DB.currentSchemaVersion)
        }
        do {
            let second = DB(databaseURL: url)
            XCTAssertTrue(second.knowledgeHealthy)
            XCTAssertEqual(second.schemaVersion, DB.currentSchemaVersion)
        }
    }

    func testVersionZeroMeetingSurvivesMigration() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try execute("""
            CREATE TABLE meetings(id TEXT PRIMARY KEY, kind TEXT NOT NULL, sort_ts REAL NOT NULL, payload TEXT NOT NULL);
            INSERT INTO meetings VALUES('legacy-meeting','live',123,'{}');
            PRAGMA user_version = 0;
            """, at: url)

        let database = DB(databaseURL: url)

        XCTAssertEqual(database.schemaVersion, DB.currentSchemaVersion)
        XCTAssertEqual(database.meetingPayloads(kind: "live").map(\.id), ["legacy-meeting"])
    }

    func testFailedMigrationRollsBackVersionAndCanRetry() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        do {
            let failed = DB(databaseURL: url, migrationFailureAtVersion: 1)
            XCTAssertTrue(failed.healthy)
            XCTAssertNil(failed.storageError)
            XCTAssertFalse(failed.knowledgeHealthy)
            XCTAssertEqual(failed.schemaVersion, 0)
            XCTAssertNotNil(failed.schemaMigrationError)
        }
        do {
            let recovered = DB(databaseURL: url)
            XCTAssertTrue(recovered.knowledgeHealthy)
            XCTAssertEqual(recovered.schemaVersion, DB.currentSchemaVersion)
        }
    }

    func testMigrationBackupContainsPreMigrationStateAndIsCreatedOnce() throws {
        let url = temporaryDatabaseURL()
        let directory = url.deletingLastPathComponent()
        let backups = directory.appendingPathComponent("Backups")
        defer { try? FileManager.default.removeItem(at: directory) }
        try execute("""
            CREATE TABLE meetings(id TEXT PRIMARY KEY, kind TEXT NOT NULL, sort_ts REAL NOT NULL, payload TEXT NOT NULL);
            INSERT INTO meetings VALUES('before-backup','live',321,'{}');
            PRAGMA user_version = 0;
            """, at: url)

        do {
            let database = DB(databaseURL: url, backupDirectory: backups)
            XCTAssertTrue(database.knowledgeHealthy)
            XCTAssertEqual(database.schemaVersion, DB.currentSchemaVersion)
        }
        let firstFiles = try FileManager.default.contentsOfDirectory(
            at: backups, includingPropertiesForKeys: nil)
        let backup = try XCTUnwrap(firstFiles.first { $0.pathExtension == "db" })
        XCTAssertEqual(firstFiles.filter { $0.pathExtension == "db" }.count, 1)
        XCTAssertEqual(try scalar("PRAGMA user_version", at: backup), "0")
        XCTAssertEqual(try scalar("PRAGMA integrity_check", at: backup), "ok")
        XCTAssertEqual(try scalar("SELECT COUNT(*) FROM meetings", at: backup), "1")

        do {
            let reopened = DB(databaseURL: url, backupDirectory: backups)
            XCTAssertTrue(reopened.knowledgeHealthy)
        }
        let secondFiles = try FileManager.default.contentsOfDirectory(
            at: backups, includingPropertiesForKeys: nil)
        XCTAssertEqual(secondFiles.filter { $0.pathExtension == "db" }.count, 1)
    }

    func testBackupFailureStopsMigrationButLeavesBaseDatabaseUsable() throws {
        let url = temporaryDatabaseURL()
        let directory = url.deletingLastPathComponent()
        let blockedPath = directory.appendingPathComponent("not-a-directory")
        defer { try? FileManager.default.removeItem(at: directory) }
        try execute("PRAGMA user_version = 0;", at: url)
        try Data("blocked".utf8).write(to: blockedPath)

        let database = DB(databaseURL: url, backupDirectory: blockedPath)

        XCTAssertTrue(database.healthy)
        XCTAssertFalse(database.knowledgeHealthy)
        XCTAssertEqual(database.schemaVersion, 0)
        XCTAssertNotNil(database.schemaMigrationError)
        XCTAssertEqual(database.meetingPayloads(kind: "live").count, 0)
    }

    func testSuccessfulBackupPrunesOlderKnowledgeMigrationBackupsToThree() throws {
        let url = temporaryDatabaseURL()
        let directory = url.deletingLastPathComponent()
        let backups = directory.appendingPathComponent("Backups")
        defer { try? FileManager.default.removeItem(at: directory) }
        try execute("PRAGMA user_version = 0;", at: url)
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        for offset in 1...4 {
            let version = DB.currentSchemaVersion + offset
            let old = backups.appendingPathComponent("aftermeet-pre-schema-v\(version)-old.db")
            try Data("old-\(version)".utf8).write(to: old)
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: TimeInterval(version))],
                ofItemAtPath: old.path)
        }

        let database = DB(databaseURL: url, backupDirectory: backups)
        XCTAssertTrue(database.knowledgeHealthy)
        let remaining = try FileManager.default.contentsOfDirectory(
            at: backups, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("aftermeet-pre-schema-v") }
        XCTAssertEqual(remaining.count, 3, remaining.map(\.lastPathComponent).joined(separator: ", "))
    }

    func testKnowledgeFTSUpsertSearchFallbackAndDeleteStayConsistent() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let database = DB(databaseURL: url)

        XCTAssertTrue(database.upsertKnowledgeFTSDoc(DB.KnowledgeFTSDoc(
            docType: "segment", docID: "segment-1", meetingID: "meeting-1", projectID: nil,
            title: "甲项目", body: "旧内容需要替换", context: "第一次会议")))
        XCTAssertEqual(database.searchKnowledgeFTS(tokens: ["旧内容"]), [
            DB.KnowledgeFTSHit(docType: "segment", docID: "segment-1")
        ])
        XCTAssertEqual(database.searchKnowledgeFTS(tokens: ["甲"]), [
            DB.KnowledgeFTSHit(docType: "segment", docID: "segment-1")
        ])

        XCTAssertTrue(database.upsertKnowledgeFTSDoc(DB.KnowledgeFTSDoc(
            docType: "segment", docID: "segment-1", meetingID: "meeting-1", projectID: "project-1",
            title: "甲项目", body: "关键指标增长到47%", context: "第二次会议")))
        XCTAssertTrue(database.upsertKnowledgeFTSDoc(DB.KnowledgeFTSDoc(
            docType: "unit", docID: "unit-1", meetingID: "meeting-1", projectID: "project-1",
            title: "指标更新", body: "关键指标已经确认", context: "甲项目")))

        XCTAssertTrue(database.searchKnowledgeFTS(tokens: ["旧内容"]).isEmpty)
        XCTAssertEqual(try scalar("SELECT COUNT(*) FROM knowledge_fts WHERE doc_id='segment-1'", at: url), "1")
        XCTAssertEqual(Set(database.searchKnowledgeFTS(tokens: ["关键指标"])), Set([
            DB.KnowledgeFTSHit(docType: "segment", docID: "segment-1"),
            DB.KnowledgeFTSHit(docType: "unit", docID: "unit-1")
        ]))
        XCTAssertEqual(database.searchKnowledgeFTS(tokens: ["关键指标", "47%"]), [
            DB.KnowledgeFTSHit(docType: "segment", docID: "segment-1")
        ])

        XCTAssertTrue(database.deleteKnowledgeFTSDoc(docType: "segment", docID: "segment-1"))
        XCTAssertTrue(database.searchKnowledgeFTS(tokens: ["47%"]).isEmpty)
        XCTAssertEqual(try scalar("SELECT COUNT(*) FROM knowledge_fts", at: url), "1")
    }

    func testExtractionJobsEnforceStateIdentityAndSourceCascade() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let database = DB(databaseURL: url)
        XCTAssertTrue(database.foreignKeysEnabled)
        try execute("""
            PRAGMA foreign_keys=ON;
            INSERT INTO source_documents(
                id,meeting_id,source_kind,full_text,content_hash,created_at,updated_at
            ) VALUES('source-jobs','meeting-1','archive','原文','input-a',1,1);
            INSERT INTO extraction_jobs(
                id,source_id,job_kind,state,input_hash,extractor_version,created_at,updated_at
            ) VALUES('job-1','source-jobs','extract','pending','input-a','extract-v1',1,1);
            INSERT OR IGNORE INTO extraction_jobs(
                id,source_id,job_kind,state,input_hash,extractor_version,created_at,updated_at
            ) VALUES('job-duplicate','source-jobs','extract','pending','input-a','extract-v1',1,1);
            INSERT INTO extraction_jobs(
                id,source_id,job_kind,state,input_hash,extractor_version,cursor,attempt,next_retry_at,created_at,updated_at
            ) VALUES('job-2','source-jobs','reextract','retry','input-a','extract-v2',3,2,100,2,2);
            """, at: url)

        XCTAssertEqual(try scalar("SELECT COUNT(*) FROM extraction_jobs", at: url), "2")
        XCTAssertEqual(try scalar("SELECT cursor FROM extraction_jobs WHERE id='job-2'", at: url), "3")
        XCTAssertThrowsError(try execute("""
            INSERT INTO extraction_jobs(
                id,source_id,job_kind,state,input_hash,extractor_version,created_at,updated_at
            ) VALUES('job-bad','source-jobs','extract','sleeping','input-b','v1',1,1);
            """, at: url))

        try execute("PRAGMA foreign_keys=ON; DELETE FROM source_documents WHERE id='source-jobs';", at: url)
        XCTAssertEqual(try scalar("SELECT COUNT(*) FROM extraction_jobs", at: url), "0")
    }

    func testExtractionDiagnosticsEnforceMetricsAndCascadeWithSourceDeletion() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let database = DB(databaseURL: url)
        XCTAssertTrue(database.foreignKeysEnabled)
        try execute("""
            PRAGMA foreign_keys=ON;
            INSERT INTO source_documents(
                id,meeting_id,source_kind,full_text,content_hash,created_at,updated_at
            ) VALUES('source-diagnostic','meeting-1','archive','原文','hash',1,1);
            INSERT INTO extraction_jobs(
                id,source_id,job_kind,state,input_hash,extractor_version,created_at,updated_at
            ) VALUES('job-diagnostic','source-diagnostic','extract','pending','hash','v1',1,1);
            INSERT INTO extraction_diagnostics(
                id,job_id,source_id,chunk_index,input_characters,output_characters,
                candidate_count,accepted_count,invalid_evidence_count,duration_ms,
                retry_count,outcome,created_at
            ) VALUES('diagnostic-1','job-diagnostic','source-diagnostic',0,100,50,3,2,1,20,0,'completed',2);
            """, at: url)

        XCTAssertThrowsError(try execute(
            "UPDATE extraction_diagnostics SET candidate_count=9 WHERE id='diagnostic-1';", at: url))
        XCTAssertThrowsError(try execute("""
            INSERT INTO extraction_diagnostics(
                id,job_id,source_id,chunk_index,input_characters,output_characters,
                candidate_count,accepted_count,invalid_evidence_count,duration_ms,
                retry_count,outcome,created_at
            ) VALUES('diagnostic-bad','job-diagnostic','source-diagnostic',0,-1,0,0,0,0,0,0,'completed',2);
            """, at: url))

        try execute("PRAGMA foreign_keys=ON; DELETE FROM source_documents WHERE id='source-diagnostic';", at: url)
        XCTAssertEqual(try scalar("SELECT COUNT(*) FROM extraction_jobs", at: url), "0")
        XCTAssertEqual(try scalar("SELECT COUNT(*) FROM extraction_diagnostics", at: url), "0")
    }

    func testFeedbackEventsAreAppendOnlyAtDatabaseLevel() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let database = DB(databaseURL: url)
        XCTAssertEqual(database.schemaVersion, DB.currentSchemaVersion)
        try execute("""
            INSERT INTO feedback_events(
                id,target_type,target_id,action,before_json,after_json,reason,actor,created_at
            ) VALUES('feedback-1','knowledge_unit','unit-1','edit','{}','{}','修正数字','user',1);
            """, at: url)

        XCTAssertEqual(try scalar("SELECT COUNT(*) FROM feedback_events", at: url), "1")
        XCTAssertThrowsError(try execute(
            "UPDATE feedback_events SET reason='覆盖' WHERE id='feedback-1';", at: url))
        XCTAssertThrowsError(try execute(
            "DELETE FROM feedback_events WHERE id='feedback-1';", at: url))
        XCTAssertThrowsError(try execute("""
            INSERT INTO feedback_events(id,target_type,target_id,action,created_at)
                VALUES('feedback-bad','knowledge_unit','unit-1','overwrite',2);
            """, at: url))
        XCTAssertEqual(try scalar("SELECT reason FROM feedback_events WHERE id='feedback-1'", at: url), "修正数字")
    }

    func testEvidenceProjectAndRelationTablesEnforceReferencesAndCascade() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let database = DB(databaseURL: url)
        XCTAssertTrue(database.foreignKeysEnabled)
        try execute("""
            PRAGMA foreign_keys=ON;
            INSERT INTO source_documents(
                id,meeting_id,source_kind,full_text,content_hash,created_at,updated_at
            ) VALUES('source-links','meeting-1','live_local','证据原文','source-links-hash',1,1);
            INSERT INTO source_segments(
                id,source_id,meeting_id,ordinal,char_start,char_end,text,content_hash,created_at,updated_at
            ) VALUES('segment-links','source-links','meeting-1',0,0,4,'证据原文','segment-links-hash',1,1);
            INSERT INTO knowledge_units(
                id,kind,canonical_text,observed_at,review_status,evidence_level,fingerprint,
                extractor_version,prompt_version,schema_version,model,created_at,updated_at
            ) VALUES('unit-1','decision','继续试验',1,'candidate','direct','unit-1-fp','v1','v1',1,'fixture',1,1);
            INSERT INTO knowledge_units(
                id,kind,canonical_text,observed_at,review_status,evidence_level,fingerprint,
                extractor_version,prompt_version,schema_version,model,created_at,updated_at
            ) VALUES('unit-2','decision','停止旧试验',2,'confirmed','direct','unit-2-fp','v1','v1',1,'fixture',2,2);
            INSERT INTO unit_sources VALUES('unit-1','segment-links','support','证据原文',1,0);
            INSERT INTO projects(id,name,normalized_name,created_at,updated_at)
                VALUES('project-1','松果计划','松果计划',1,1);
            INSERT INTO unit_projects VALUES('unit-1','project-1','decision',1,'model','candidate');
            INSERT INTO unit_relations(
                from_unit_id,to_unit_id,relation_kind,review_status,reason,created_at
            ) VALUES('unit-2','unit-1','supersedes','candidate','后续会议更新',2);
            """, at: url)

        XCTAssertEqual(try scalar("SELECT COUNT(*) FROM unit_sources", at: url), "1")
        XCTAssertEqual(try scalar("SELECT COUNT(*) FROM unit_projects", at: url), "1")
        XCTAssertEqual(try scalar("SELECT COUNT(*) FROM unit_relations", at: url), "1")
        XCTAssertThrowsError(try execute("""
            PRAGMA foreign_keys=ON;
            INSERT INTO unit_sources VALUES('unit-1','missing-segment','support','不存在',1,0);
            """, at: url))
        XCTAssertThrowsError(try execute("""
            INSERT INTO projects(id,name,normalized_name,created_at,updated_at)
                VALUES('project-duplicate','另一个名字','松果计划',1,1);
            """, at: url))
        XCTAssertThrowsError(try execute("""
            INSERT INTO unit_relations(from_unit_id,to_unit_id,relation_kind,review_status,created_at)
                VALUES('unit-1','unit-1','same_as','candidate',1);
            """, at: url))

        try execute("PRAGMA foreign_keys=ON; DELETE FROM knowledge_units WHERE id='unit-1';", at: url)
        XCTAssertEqual(try scalar("SELECT COUNT(*) FROM unit_sources", at: url), "0")
        XCTAssertEqual(try scalar("SELECT COUNT(*) FROM unit_projects", at: url), "0")
        XCTAssertEqual(try scalar("SELECT COUNT(*) FROM unit_relations", at: url), "0")
        XCTAssertEqual(try scalar("SELECT COUNT(*) FROM knowledge_units", at: url), "1")
        XCTAssertEqual(try scalar("SELECT COUNT(*) FROM source_segments", at: url), "1")
    }

    func testKnowledgeUnitsEnforceEnumsAndPreserveTemporalVersions() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let database = DB(databaseURL: url)
        XCTAssertEqual(database.schemaVersion, DB.currentSchemaVersion)
        try execute("""
            INSERT INTO knowledge_units(
                id,kind,canonical_text,numeric_value,value_unit,valid_from,valid_to,observed_at,
                review_status,evidence_level,fingerprint,extractor_version,prompt_version,schema_version,
                model,created_at,updated_at
            ) VALUES(
                'metric-old','metric','次日留存为42%',42,'%',1,10,2,
                'confirmed','direct','retention','extract-v1','prompt-v1',1,'fixture',2,2
            );
            INSERT INTO knowledge_units(
                id,kind,canonical_text,numeric_value,value_unit,valid_from,valid_to,observed_at,
                review_status,evidence_level,fingerprint,extractor_version,prompt_version,schema_version,
                model,created_at,updated_at
            ) VALUES(
                'metric-new','metric','次日留存为47%',47,'%',11,NULL,12,
                'candidate','direct','retention','extract-v1','prompt-v1',1,'fixture',12,12
            );
            """, at: url)

        XCTAssertEqual(try scalar("SELECT COUNT(*) FROM knowledge_units WHERE fingerprint='retention'", at: url), "2")
        XCTAssertEqual(try scalar("SELECT COUNT(*) FROM knowledge_units WHERE valid_to IS NULL", at: url), "1")
        XCTAssertThrowsError(try execute("""
            INSERT INTO knowledge_units(
                id,kind,canonical_text,observed_at,review_status,evidence_level,fingerprint,
                extractor_version,prompt_version,schema_version,model,created_at,updated_at
            ) VALUES('bad-kind','opinion','text',1,'candidate','direct','x','v','v',1,'fixture',1,1);
            """, at: url))
        XCTAssertThrowsError(try execute("""
            INSERT INTO knowledge_units(
                id,kind,canonical_text,valid_from,valid_to,observed_at,review_status,evidence_level,
                fingerprint,extractor_version,prompt_version,schema_version,model,created_at,updated_at
            ) VALUES('bad-time','fact','text',10,5,1,'candidate','direct','x','v','v',1,'fixture',1,1);
            """, at: url))
    }

    func testSourceSegmentsEnforceRangesIdentityAndCascade() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let database = DB(databaseURL: url)
        XCTAssertTrue(database.foreignKeysEnabled)
        try execute("""
            PRAGMA foreign_keys=ON;
            INSERT INTO source_documents(
                id,meeting_id,source_kind,full_text,content_hash,created_at,updated_at
            ) VALUES('source-for-segments','meeting-1','live_cloud','第一句。第二句。','source-hash',1,1);
            INSERT INTO source_segments(
                id,source_id,meeting_id,ordinal,start_ms,end_ms,char_start,char_end,text,content_hash,created_at,updated_at
            ) VALUES('segment-0','source-for-segments','meeting-1',0,100,800,0,4,'第一句。','segment-hash-0',1,1);
            """, at: url)

        XCTAssertThrowsError(try execute("""
            INSERT INTO source_segments(
                id,source_id,meeting_id,ordinal,char_start,char_end,text,content_hash,created_at,updated_at
            ) VALUES('segment-duplicate','source-for-segments','meeting-1',0,4,8,'第二句。','segment-hash-1',1,1);
            """, at: url))
        XCTAssertThrowsError(try execute("""
            PRAGMA foreign_keys=ON;
            INSERT INTO source_segments(
                id,source_id,meeting_id,ordinal,char_start,char_end,text,content_hash,created_at,updated_at
            ) VALUES('segment-orphan','missing-source','meeting-1',1,0,4,'孤儿句。','segment-hash-x',1,1);
            """, at: url))
        XCTAssertThrowsError(try execute("""
            INSERT INTO source_segments(
                id,source_id,meeting_id,ordinal,char_start,char_end,text,content_hash,created_at,updated_at
            ) VALUES('segment-bad-range','source-for-segments','meeting-1',2,8,3,'错误范围','segment-hash-y',1,1);
            """, at: url))

        try execute("PRAGMA foreign_keys=ON; DELETE FROM source_documents WHERE id='source-for-segments';", at: url)
        XCTAssertEqual(try scalar("SELECT COUNT(*) FROM source_segments", at: url), "0")
    }

    func testSourceDocumentsEnforceKindsAndIdempotentContentIdentity() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let database = DB(databaseURL: url)
        XCTAssertEqual(database.schemaVersion, DB.currentSchemaVersion)

        try execute("""
            INSERT INTO source_documents(
                id,meeting_id,source_kind,full_text,content_hash,source_revision,created_at,updated_at
            ) VALUES('source-1','meeting-1','live_cloud','第一版','hash-a',1,1,1);
            INSERT OR IGNORE INTO source_documents(
                id,meeting_id,source_kind,full_text,content_hash,source_revision,created_at,updated_at
            ) VALUES('source-duplicate','meeting-1','live_cloud','第一版','hash-a',1,1,1);
            INSERT INTO source_documents(
                id,meeting_id,source_kind,full_text,content_hash,source_revision,created_at,updated_at
            ) VALUES('source-2','meeting-1','live_cloud','第二版','hash-b',2,2,2);
            """, at: url)

        XCTAssertEqual(try scalar("SELECT COUNT(*) FROM source_documents", at: url), "2")
        XCTAssertEqual(try scalar("SELECT MAX(source_revision) FROM source_documents", at: url), "2")
        XCTAssertThrowsError(try execute("""
            INSERT INTO source_documents(
                id,meeting_id,source_kind,full_text,content_hash,created_at,updated_at
            ) VALUES('bad-source','meeting-1','unknown','text','hash-c',3,3);
            """, at: url))
    }

    func testMeetingUpsertPreservesChildrenAndKeepsSingleFTSRow() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let database = DB(databaseURL: url)
        XCTAssertTrue(database.upsertMeeting(
            id: "stable-meeting", kind: "live", sortTs: 1, payload: "old",
            fts: DB.FTSDoc(title: "旧标题", summary: "旧摘要", transcript: "旧转写")))
        try execute("""
            PRAGMA foreign_keys=ON;
            CREATE TABLE meeting_children(
                id TEXT PRIMARY KEY,
                meeting_id TEXT NOT NULL REFERENCES meetings(id) ON DELETE CASCADE
            );
            INSERT INTO meeting_children VALUES('child-1','stable-meeting');
            """, at: url)

        XCTAssertTrue(database.upsertMeeting(
            id: "stable-meeting", kind: "live", sortTs: 2, payload: "new",
            fts: DB.FTSDoc(title: "新标题", summary: "新摘要", transcript: "新转写")))

        XCTAssertEqual(try scalar("SELECT COUNT(*) FROM meeting_children", at: url), "1")
        XCTAssertEqual(try scalar("SELECT payload FROM meetings WHERE id='stable-meeting'", at: url), "new")
        XCTAssertEqual(try scalar("SELECT COUNT(*) FROM meetings_fts WHERE id='stable-meeting'", at: url), "1")
        XCTAssertEqual(database.searchMeetings(tokens: ["新转写"]), ["stable-meeting"])
    }

    func testBaseOpenFailureIsDistinctFromKnowledgeMigrationFailure() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AfterMeet-InvalidDatabase-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let database = DB(databaseURL: directory)

        XCTAssertFalse(database.healthy)
        XCTAssertFalse(database.knowledgeHealthy)
        XCTAssertNotNil(database.storageError)
        XCTAssertNil(database.schemaMigrationError)
    }

    func testFutureSchemaDisablesKnowledgeWithoutBreakingBaseDatabase() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try execute("PRAGMA user_version = 99;", at: url)

        let database = DB(databaseURL: url)

        XCTAssertTrue(database.healthy)
        XCTAssertFalse(database.knowledgeHealthy)
        XCTAssertEqual(database.schemaVersion, 99)
        XCTAssertNotNil(database.schemaMigrationError)
    }
}
