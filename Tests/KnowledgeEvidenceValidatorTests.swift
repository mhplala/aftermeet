import XCTest
@testable import AfterMeet

final class KnowledgeEvidenceValidatorTests: XCTestCase {
    private func segment(id: String,
                         sourceID: String = "source-1",
                         ordinal: Int,
                         text: String) -> KnowledgeSourceSegment {
        KnowledgeSourceSegment(
            id: id, sourceID: sourceID, meetingID: "meeting-1", ordinal: ordinal,
            speaker: "甲", startMS: ordinal * 1_000, endMS: (ordinal + 1) * 1_000,
            charStart: 0, charEnd: text.count, text: text,
            contentHash: KnowledgeIdentity.contentHash(text), metadataJSON: "{}",
            createdAt: 1, updatedAt: 1)
    }

    private func candidate(id: String,
                           evidence: [KnowledgeExtractionEvidence]) -> KnowledgeExtractionCandidate {
        KnowledgeExtractionCandidate(
            clientID: id,
            kind: .decision,
            canonicalText: "继续试验",
            subject: nil,
            predicate: nil,
            objectText: nil,
            numericValue: nil,
            valueUnit: nil,
            owner: nil,
            dueText: nil,
            validFrom: nil,
            validTo: nil,
            evidenceLevel: .direct,
            evidence: evidence,
            projectHints: [],
            sensitivity: nil)
    }

    private func envelope(_ units: [KnowledgeExtractionCandidate]) -> KnowledgeExtractionEnvelope {
        KnowledgeExtractionEnvelope(
            schemaVersion: 1, sourceHash: "hash", chunkIndex: 0, units: units)
    }

    func testValidCoreSupportIsAcceptedAndInvalidExtraEvidenceIsDropped() {
        let core = segment(id: "core", ordinal: 0, text: "甲：先继续小流量试验。")
        let context = segment(id: "context", ordinal: 1, text: "乙：补充背景。")
        let chunk = KnowledgeExtractionChunk(
            index: 0,
            segments: [context, core],
            coreSegmentIDs: [core.id],
            contextSegmentIDs: [context.id],
            estimatedPayloadCharacters: 100)
        let unit = candidate(id: "candidate-1", evidence: [
            KnowledgeExtractionEvidence(segmentID: core.id, quote: "继续小流量试验", role: .support),
            KnowledgeExtractionEvidence(segmentID: "fabricated", quote: "不存在", role: .context)
        ])

        let result = KnowledgeEvidenceValidator.validate(
            envelope([unit]), chunk: chunk, expectedSourceID: "source-1")

        XCTAssertEqual(result.accepted.count, 1)
        XCTAssertEqual(result.accepted[0].evidence.count, 1)
        XCTAssertEqual(result.accepted[0].evidence[0].segmentID, core.id)
        XCTAssertEqual(result.issues, [KnowledgeEvidenceValidationIssue(
            clientID: "candidate-1", evidenceIndex: 1, reason: .unknownSegment)])
    }

    func testContextOnlySupportCannotCreateCandidate() {
        let context = segment(id: "context", ordinal: 0, text: "甲：只是一段边界上下文。")
        let core = segment(id: "core", ordinal: 1, text: "乙：本段没有相关结论。")
        let chunk = KnowledgeExtractionChunk(
            index: 0,
            segments: [context, core],
            coreSegmentIDs: [core.id],
            contextSegmentIDs: [context.id],
            estimatedPayloadCharacters: 100)
        let unit = candidate(id: "candidate-context", evidence: [
            KnowledgeExtractionEvidence(
                segmentID: context.id, quote: "只是一段边界上下文", role: .support)
        ])

        let result = KnowledgeEvidenceValidator.validate(
            envelope([unit]), chunk: chunk, expectedSourceID: "source-1")

        XCTAssertTrue(result.accepted.isEmpty)
        XCTAssertTrue(result.issues.contains { $0.reason == .missingCoreSupport })
    }

    func testUnknownWrongSourceAndParaphrasedQuotesAreRejected() {
        let core = segment(id: "core", ordinal: 0, text: "甲：原话是维持百分之十流量。")
        let otherSource = segment(
            id: "other-source", sourceID: "source-2", ordinal: 1,
            text: "乙：另一来源的内容。")
        let chunk = KnowledgeExtractionChunk(
            index: 0,
            segments: [core, otherSource],
            coreSegmentIDs: [core.id, otherSource.id],
            contextSegmentIDs: [],
            estimatedPayloadCharacters: 100)
        let units = [
            candidate(id: "unknown", evidence: [KnowledgeExtractionEvidence(
                segmentID: "made-up", quote: "伪造", role: .support)]),
            candidate(id: "wrong-source", evidence: [KnowledgeExtractionEvidence(
                segmentID: otherSource.id, quote: "另一来源的内容", role: .support)]),
            candidate(id: "paraphrase", evidence: [KnowledgeExtractionEvidence(
                segmentID: core.id, quote: "保持10%的实验流量", role: .support)])
        ]

        let result = KnowledgeEvidenceValidator.validate(
            envelope(units), chunk: chunk, expectedSourceID: "source-1")

        XCTAssertTrue(result.accepted.isEmpty)
        XCTAssertTrue(result.issues.contains { $0.clientID == "unknown" && $0.reason == .unknownSegment })
        XCTAssertTrue(result.issues.contains { $0.clientID == "wrong-source" && $0.reason == .wrongSource })
        XCTAssertTrue(result.issues.contains { $0.clientID == "paraphrase" && $0.reason == .quoteMismatch })
    }

    func testUnicodeAndLineEndingNormalizationStillRequiresContiguousQuote() {
        let core = segment(id: "core", ordinal: 0, text: "Café\r\n继续试验")
        let chunk = KnowledgeExtractionChunk(
            index: 0, segments: [core], coreSegmentIDs: [core.id],
            contextSegmentIDs: [], estimatedPayloadCharacters: 100)
        let valid = candidate(id: "normalized", evidence: [KnowledgeExtractionEvidence(
            segmentID: core.id, quote: "Cafe\u{301}\n继续", role: .support)])
        let duplicate = candidate(id: "normalized", evidence: [KnowledgeExtractionEvidence(
            segmentID: core.id, quote: "继续试验", role: .support)])

        let result = KnowledgeEvidenceValidator.validate(
            envelope([valid, duplicate]), chunk: chunk, expectedSourceID: "source-1")

        XCTAssertEqual(result.accepted.map { $0.candidate.clientID }, ["normalized"])
        XCTAssertTrue(result.issues.contains { $0.reason == .duplicateClientID })
    }
}
