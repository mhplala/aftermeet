import XCTest
@testable import AfterMeet

final class KnowledgeChunkCommitTests: XCTestCase {
    private func makeStore() -> (KnowledgeStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AfterMeet-ChunkCommit-" + UUID().uuidString)
        return (KnowledgeStore(database: DB(
            databaseURL: directory.appendingPathComponent("aftermeet.db"))), directory)
    }

    private func prepare(store: KnowledgeStore) -> (
        source: KnowledgeSourceDocument,
        segment: KnowledgeSourceSegment,
        project: KnowledgeProject,
        job: KnowledgeExtractionJob
    ) {
        let bundle = KnowledgeSegmenter.plainTextSourceBundle(
            content: "甲：继续小流量试验。",
            meetingID: "meeting-1",
            observedAt: 10)
        XCTAssertTrue(store.saveSource(
            bundle.document, segments: bundle.segments, meetingTitle: "松果计划评审"))
        let project = KnowledgeProject(
            id: "project-1", name: "松果计划", normalizedName: "松果计划",
            aliases: ["松果"], status: .active, createdAt: 10, updatedAt: 10)
        XCTAssertTrue(store.saveProject(project))
        guard case .enqueued(let pending) = KnowledgeJobPlanner.planExtraction(
            for: bundle.document, store: store, enabled: true, now: 10) else {
            fatalError("expected job")
        }
        let running = store.claimNextJob(now: 11, leaseDuration: 60)!
        XCTAssertEqual(running.id, pending.id)
        return (bundle.document, bundle.segments[0], project, running)
    }

    private func materialized(clientID: String,
                              canonicalText: String,
                              source: KnowledgeSourceDocument,
                              segment: KnowledgeSourceSegment,
                              projects: [KnowledgeProject],
                              existingUnits: [KnowledgeUnit] = [],
                              extractorVersion: String = KnowledgeExtractionPrompt.extractorVersion) -> KnowledgeUnitCommit {
        let evidence = KnowledgeExtractionEvidence(
            segmentID: segment.id,
            quote: "继续小流量试验",
            role: .support)
        let candidate = KnowledgeExtractionCandidate(
            clientID: clientID, kind: .decision, canonicalText: canonicalText,
            subject: "松果计划", predicate: "试验状态", objectText: "继续",
            numericValue: nil, valueUnit: nil, owner: nil, dueText: nil,
            validFrom: nil, validTo: nil, evidenceLevel: .direct,
            evidence: [evidence], projectHints: ["松果计划"], sensitivity: nil)
        let validated = ValidatedKnowledgeCandidate(candidate: candidate, evidence: [evidence])
        let normalized = KnowledgeCandidateNormalizer.normalize(
            validated,
            sourceSensitivity: source.sensitivity,
            observedAt: source.createdAt)
        return KnowledgeCandidateMaterializer.materialize(
            validated: validated,
            normalized: normalized,
            source: source,
            chunkIndex: 0,
            meetingTitle: "松果计划评审",
            existingProjects: projects,
            existingUnits: existingUnits,
            extractorVersion: extractorVersion,
            model: "fixture",
            now: 12)
    }

    private func reviewed(_ base: KnowledgeUnit,
                          status: KnowledgeReviewStatus,
                          canonicalText: String? = nil,
                          revision: Int = 2) -> KnowledgeUnit {
        KnowledgeUnit(
            id: base.id,
            kind: base.kind,
            canonicalText: canonicalText ?? base.canonicalText,
            subject: base.subject,
            predicate: base.predicate,
            objectText: base.objectText,
            numericValue: base.numericValue,
            valueUnit: base.valueUnit,
            owner: base.owner,
            dueText: base.dueText,
            validFrom: base.validFrom,
            validTo: base.validTo,
            observedAt: base.observedAt,
            reviewStatus: status,
            evidenceLevel: base.evidenceLevel,
            conflictStatus: base.conflictStatus,
            sensitivity: base.sensitivity,
            fingerprint: base.fingerprint,
            revision: revision,
            extractorVersion: base.extractorVersion,
            promptVersion: base.promptVersion,
            schemaVersion: base.schemaVersion,
            model: base.model,
            payloadJSON: base.payloadJSON,
            createdAt: base.createdAt,
            updatedAt: base.updatedAt + 1)
    }

    func testMaterializerProducesStableCandidateUnitEvidenceAndProjectHint() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let prepared = prepare(store: store)

        let first = materialized(
            clientID: "candidate-1", canonicalText: "决定继续小流量试验",
            source: prepared.source, segment: prepared.segment, projects: [prepared.project])
        let second = materialized(
            clientID: "candidate-1", canonicalText: "决定继续小流量试验",
            source: prepared.source, segment: prepared.segment, projects: [prepared.project])

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.unit.reviewStatus, .candidate)
        XCTAssertEqual(first.unit.model, "fixture")
        XCTAssertEqual(first.evidence.count, 1)
        XCTAssertFalse(first.evidence[0].verified)
        XCTAssertEqual(first.projectLinks.count, 1)
        XCTAssertEqual(first.projectLinks[0].reviewStatus, .candidate)
    }

    func testChunkCommitWritesUnitsEdgesFTSAndCursorInOneTransaction() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let prepared = prepare(store: store)
        let commit = materialized(
            clientID: "candidate-success", canonicalText: "决定继续小流量试验",
            source: prepared.source, segment: prepared.segment, projects: [prepared.project])

        XCTAssertTrue(store.commitChunk(
            [commit], jobID: prepared.job.id, nextCursor: 1, now: 13))

        XCTAssertEqual(store.units(), [commit.unit])
        XCTAssertEqual(store.evidence(unitID: commit.unit.id), commit.evidence)
        XCTAssertEqual(store.projectLinks(unitID: commit.unit.id), commit.projectLinks)
        XCTAssertEqual(store.search(tokens: ["决定继续"]), [
            DB.KnowledgeFTSHit(docType: "unit", docID: commit.unit.id)
        ])
        let job = try XCTUnwrap(store.jobs().first { $0.id == prepared.job.id })
        XCTAssertEqual(job.state, .running)
        XCTAssertEqual(job.cursor, 1)
    }

    func testSameVersionRerunCannotOverwriteReviewedUnit() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let prepared = prepare(store: store)
        let original = materialized(
            clientID: "candidate-reviewed", canonicalText: "决定继续小流量试验",
            source: prepared.source, segment: prepared.segment, projects: [prepared.project])
        XCTAssertTrue(store.commitChunk(
            [original], jobID: prepared.job.id, nextCursor: 1, now: 13))
        let confirmed = reviewed(original.unit, status: .confirmed)
        let verifiedEvidence = original.evidence.map {
            KnowledgeUnitSource(
                unitID: $0.unitID, segmentID: $0.segmentID, evidenceRole: $0.evidenceRole,
                quote: $0.quote, weight: $0.weight, verified: true)
        }
        XCTAssertTrue(store.saveUnit(
            confirmed,
            evidence: verifiedEvidence,
            projectLinks: original.projectLinks,
            meetingID: original.meetingID,
            meetingTitle: original.meetingTitle))
        let rerun = materialized(
            clientID: "candidate-reviewed", canonicalText: "决定 继续 小流量试验",
            source: prepared.source, segment: prepared.segment, projects: [prepared.project])
        XCTAssertEqual(rerun.unit.id, confirmed.id)

        XCTAssertTrue(store.commitChunk(
            [rerun], jobID: prepared.job.id, nextCursor: 2, now: 14))

        let preserved = try XCTUnwrap(store.units().first { $0.id == confirmed.id })
        XCTAssertEqual(preserved.reviewStatus, .confirmed)
        XCTAssertEqual(preserved.revision, 2)
        XCTAssertEqual(preserved.canonicalText, confirmed.canonicalText)
        XCTAssertEqual(store.evidence(unitID: confirmed.id), verifiedEvidence)
        XCTAssertEqual(store.jobs().first { $0.id == prepared.job.id }?.cursor, 2)
    }

    func testNewExtractorVersionCreatesCandidateAndSameAsSuggestionBesideConfirmedUnit() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let prepared = prepare(store: store)
        let original = materialized(
            clientID: "candidate-versioned", canonicalText: "决定继续小流量试验",
            source: prepared.source, segment: prepared.segment, projects: [prepared.project])
        XCTAssertTrue(store.commitChunk(
            [original], jobID: prepared.job.id, nextCursor: 1, now: 13))
        let confirmed = reviewed(original.unit, status: .confirmed)
        XCTAssertTrue(store.saveUnit(
            confirmed,
            evidence: original.evidence,
            projectLinks: original.projectLinks,
            meetingID: original.meetingID,
            meetingTitle: original.meetingTitle))
        XCTAssertTrue(store.transitionJob(
            id: prepared.job.id, state: .done, cursor: 1, now: 14))
        guard case .enqueued(let pendingV2) = KnowledgeJobPlanner.planExtraction(
            for: prepared.source,
            store: store,
            extractorVersion: "extractor-v2",
            enabled: true,
            now: 15) else { return XCTFail("expected v2 reextract") }
        let runningV2 = try XCTUnwrap(store.claimNextJob(now: 16, leaseDuration: 60))
        XCTAssertEqual(runningV2.id, pendingV2.id)
        let v2 = materialized(
            clientID: "candidate-versioned", canonicalText: "决定继续小流量试验",
            source: prepared.source, segment: prepared.segment, projects: [prepared.project],
            existingUnits: [confirmed], extractorVersion: "extractor-v2")

        XCTAssertNotEqual(v2.unit.id, confirmed.id)
        XCTAssertEqual(v2.unit.reviewStatus, .candidate)
        XCTAssertEqual(v2.suggestedRelations.count, 1)
        XCTAssertEqual(v2.suggestedRelations[0].relationKind, .sameAs)
        XCTAssertEqual(v2.suggestedRelations[0].toUnitID, confirmed.id)
        XCTAssertTrue(store.commitChunk(
            [v2], jobID: runningV2.id, nextCursor: 1, now: 17))

        XCTAssertEqual(store.units().count, 2)
        XCTAssertEqual(store.units().first { $0.id == confirmed.id }?.reviewStatus, .confirmed)
        XCTAssertEqual(store.units().first { $0.id == v2.unit.id }?.reviewStatus, .candidate)
        XCTAssertEqual(store.relations(unitID: v2.unit.id), v2.suggestedRelations)
    }

    func testAnyInvalidCommitRollsBackEarlierUnitsFTSAndCursor() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let prepared = prepare(store: store)
        let valid = materialized(
            clientID: "candidate-valid", canonicalText: "第一条候选",
            source: prepared.source, segment: prepared.segment, projects: [prepared.project])
        let second = materialized(
            clientID: "candidate-invalid", canonicalText: "第二条候选",
            source: prepared.source, segment: prepared.segment, projects: [])
        let invalid = KnowledgeUnitCommit(
            unit: second.unit,
            evidence: second.evidence,
            projectLinks: [KnowledgeUnitProject(
                unitID: second.unit.id,
                projectID: "missing-project",
                role: "related",
                relevance: 1,
                assignmentSource: .model,
                reviewStatus: .candidate)],
            meetingID: second.meetingID,
            meetingTitle: second.meetingTitle)
        let ftsCountBefore = store.diagnostics().tableCounts["knowledge_fts"]

        XCTAssertFalse(store.commitChunk(
            [valid, invalid], jobID: prepared.job.id, nextCursor: 1, now: 13))

        XCTAssertTrue(store.units().isEmpty)
        XCTAssertEqual(store.diagnostics().tableCounts["knowledge_fts"], ftsCountBefore)
        XCTAssertEqual(store.jobs().first { $0.id == prepared.job.id }?.cursor, 0)
    }

    func testMissingRunningJobRollsBackOtherwiseValidCommit() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let prepared = prepare(store: store)
        let commit = materialized(
            clientID: "candidate-no-job", canonicalText: "不应落库的候选",
            source: prepared.source, segment: prepared.segment, projects: [prepared.project])

        XCTAssertFalse(store.commitChunk(
            [commit], jobID: "missing-job", nextCursor: 1, now: 13))
        XCTAssertTrue(store.units().isEmpty)
    }
}
