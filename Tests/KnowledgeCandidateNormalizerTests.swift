import XCTest
@testable import AfterMeet

private struct SemanticVerifierFixtureClient: KnowledgeExtractionClient {
    let verdict: String
    let includeReasons: Bool

    func complete(systemPrompt: String, userPrompt: String, maxTokens: Int) async throws -> String {
        var item: [String: Any] = ["client_id": "candidate-1", "verdict": verdict]
        if includeReasons { item["reasons"] = [] }
        let data = try JSONSerialization.data(withJSONObject: [
            "schema_version": 1,
            "units": [item]
        ])
        return String(data: data, encoding: .utf8)!
    }
}

private struct DuplicateSemanticVerifierClient: KnowledgeExtractionClient {
    func complete(systemPrompt: String, userPrompt: String, maxTokens: Int) async throws -> String {
        """
        {"schema_version":1,"units":[
          {"client_id":"candidate-1","verdict":"entailed","reasons":[]},
          {"client_id":"candidate-1","verdict":"entailed","reasons":[]}
        ]}
        """
    }
}

final class KnowledgeCandidateNormalizerTests: XCTestCase {
    private func candidate(
        kind: KnowledgeKind = .metric,
        claimType: KnowledgeClaimType = .observedFact,
        epistemicStatus: KnowledgeEpistemicStatus = .certain,
        attributedTo: String? = nil,
        evidenceLevel: KnowledgeEvidenceLevel = .direct,
        subject: String? = nil,
        predicate: String? = nil,
        objectText: String? = nil,
        numericValue: Double? = nil,
        valueUnit: String? = nil,
        owner: String? = nil,
        dueText: String? = nil,
        validFrom: String? = nil,
        validTo: String? = nil,
        projectHints: [String] = [],
        sensitivity: KnowledgeSensitivity? = nil,
        quote: String
    ) -> ValidatedKnowledgeCandidate {
        let evidence = KnowledgeExtractionEvidence(
            segmentID: "segment-1", quote: quote, role: .support)
        let candidate = KnowledgeExtractionCandidate(
            clientID: "candidate-1", kind: kind, claimType: claimType,
            epistemicStatus: epistemicStatus, attributedTo: attributedTo,
            canonicalText: "虚构指标更新", subject: subject, predicate: predicate,
            objectText: objectText, numericValue: numericValue, valueUnit: valueUnit,
            owner: owner, dueText: dueText, validFrom: validFrom, validTo: validTo,
            evidenceLevel: evidenceLevel, evidence: [evidence], projectHints: projectHints,
            sensitivity: sensitivity)
        return ValidatedKnowledgeCandidate(candidate: candidate, evidence: [evidence])
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func observedAt() -> TimeInterval {
        utcCalendar().date(from: DateComponents(year: 2026, month: 8, day: 20))!.timeIntervalSince1970
    }

    func testNullLikeValuesDisappearAndProjectHintsDeduplicate() {
        let value = candidate(
            subject: "null", predicate: "待定", objectText: "—",
            owner: "无", dueText: "tbd",
            projectHints: [" 松果计划 ", "松果计划", "none", ""],
            quote: "会议没有明确负责人或日期")

        let normalized = KnowledgeCandidateNormalizer.normalize(
            value, sourceSensitivity: .normal,
            observedAt: observedAt(), calendar: utcCalendar())

        XCTAssertNil(normalized.subject)
        XCTAssertNil(normalized.predicate)
        XCTAssertNil(normalized.objectText)
        XCTAssertNil(normalized.owner)
        XCTAssertNil(normalized.dueText)
        XCTAssertEqual(normalized.projectHints, ["松果计划"])
    }

    func testDirectOwnerDueNumberAndAbsoluteDateRequireLiteralEvidence() {
        let value = candidate(
            numericValue: 42, valueUnit: "%", owner: "小王", dueText: "9月15日",
            validFrom: "9月15日",
            quote: "小王负责在9月15日前复盘，当前指标是42%")

        let normalized = KnowledgeCandidateNormalizer.normalize(
            value, sourceSensitivity: .normal,
            observedAt: observedAt(), calendar: utcCalendar())
        let date = normalized.validFrom.map(Date.init(timeIntervalSince1970:))

        XCTAssertEqual(normalized.owner, "小王")
        XCTAssertEqual(normalized.dueText, "9月15日")
        XCTAssertEqual(normalized.numericValue, 42)
        XCTAssertEqual(normalized.valueUnit, "%")
        XCTAssertEqual(date.map { utcCalendar().component(.year, from: $0) }, 2026)
        XCTAssertEqual(date.map { utcCalendar().component(.month, from: $0) }, 9)
        XCTAssertEqual(date.map { utcCalendar().component(.day, from: $0) }, 15)
    }

    func testInferredOrUnsupportedFieldsRemainNil() {
        let inferred = candidate(
            evidenceLevel: .inferred,
            numericValue: 42, valueUnit: "%", owner: "乙", dueText: "9月15日",
            validFrom: "9月15日",
            quote: "乙负责在9月15日前复盘，当前指标是42%")
        let unsupported = candidate(
            numericValue: 42, valueUnit: "%", owner: "乙", dueText: "9月15日",
            validFrom: "9月15日",
            quote: "甲提到指标大约四十二，但没有指派或日期")

        for normalized in [inferred, unsupported].map({
            KnowledgeCandidateNormalizer.normalize(
                $0, sourceSensitivity: .normal,
                observedAt: observedAt(), calendar: utcCalendar())
        }) {
            XCTAssertNil(normalized.owner)
            XCTAssertNil(normalized.dueText)
            XCTAssertNil(normalized.numericValue)
            XCTAssertNil(normalized.valueUnit)
            XCTAssertNil(normalized.validFrom)
        }
    }

    func testImpossibleDateIsRejectedInsteadOfCalendarNormalized() {
        let value = candidate(
            validFrom: "2026-02-31",
            quote: "截止日期是 2026-02-31")

        let normalized = KnowledgeCandidateNormalizer.normalize(
            value, sourceSensitivity: .normal,
            observedAt: observedAt(), calendar: utcCalendar())

        XCTAssertNil(normalized.validFrom)
    }

    func testQuarterParsesToStartAndEndWithoutCollapsingHistory() {
        let value = candidate(
            validFrom: "2026 Q3", validTo: "2026 Q3",
            quote: "计划有效期是2026 Q3")

        let normalized = KnowledgeCandidateNormalizer.normalize(
            value, sourceSensitivity: .normal,
            observedAt: observedAt(), calendar: utcCalendar())
        let start = Date(timeIntervalSince1970: normalized.validFrom!)
        let end = Date(timeIntervalSince1970: normalized.validTo!)

        XCTAssertEqual(utcCalendar().component(.month, from: start), 7)
        XCTAssertEqual(utcCalendar().component(.day, from: start), 1)
        XCTAssertEqual(utcCalendar().component(.month, from: end), 9)
        XCTAssertEqual(utcCalendar().component(.day, from: end), 30)
        XCTAssertEqual(utcCalendar().component(.hour, from: end), 23)
    }

    func testRangeTextAndRawCandidateRemainInPayloadWithoutInventingScalar() {
        let value = candidate(
            objectText: "42%-47%", numericValue: nil, valueUnit: "%",
            quote: "指标范围是42%-47%")

        let normalized = KnowledgeCandidateNormalizer.normalize(
            value, sourceSensitivity: .normal,
            observedAt: observedAt(), calendar: utcCalendar())

        XCTAssertEqual(normalized.objectText, "42%-47%")
        XCTAssertNil(normalized.numericValue)
        XCTAssertNil(normalized.valueUnit)
        XCTAssertTrue(normalized.payloadJSON.contains("42%-47%"))
    }

    func testSensitivityCanOnlyEscalate() {
        let normalCandidate = candidate(sensitivity: .normal, quote: "普通内容")
        let restrictedCandidate = candidate(sensitivity: .restricted, quote: "敏感内容")

        XCTAssertEqual(KnowledgeCandidateNormalizer.normalize(
            normalCandidate, sourceSensitivity: .restricted,
            observedAt: observedAt(), calendar: utcCalendar()).sensitivity, .restricted)
        XCTAssertEqual(KnowledgeCandidateNormalizer.normalize(
            restrictedCandidate, sourceSensitivity: .normal,
            observedAt: observedAt(), calendar: utcCalendar()).sensitivity, .restricted)
    }

    func testQualificationKeepsProposalDistinctFromCommitmentWithinActionGroup() {
        let value = candidate(
            kind: .action,
            claimType: .proposal,
            quote: "要不要找音乐试试看")
        let normalized = KnowledgeCandidateNormalizer.normalize(
            value, sourceSensitivity: .normal,
            observedAt: observedAt(), calendar: utcCalendar())

        XCTAssertFalse(KnowledgeQualificationValidator.issues(for: normalized)
            .contains(.incompatibleClaimType))
        XCTAssertEqual(normalized.claimType, .proposal)
        XCTAssertNil(normalized.owner)
    }

    func testQualificationRequiresOwnerAndAttributionForCommitment() {
        let value = candidate(
            kind: .action,
            claimType: .commitment,
            quote: "后面把方案再过一遍")
        let normalized = KnowledgeCandidateNormalizer.normalize(
            value, sourceSensitivity: .normal,
            observedAt: observedAt(), calendar: utcCalendar())

        let issues = KnowledgeQualificationValidator.issues(for: normalized)
        XCTAssertTrue(issues.contains(.missingOwner))
        XCTAssertTrue(issues.contains(.missingAttribution))
    }

    func testAttributedOpinionPreservesSpeakerAndSoftModality() {
        let value = candidate(
            kind: .fact,
            claimType: .attributedOpinion,
            epistemicStatus: .soft,
            attributedTo: "小王",
            quote: "小王觉得这个方向可能更稳")
        let normalized = KnowledgeCandidateNormalizer.normalize(
            value, sourceSensitivity: .normal,
            observedAt: observedAt(), calendar: utcCalendar())

        XCTAssertEqual(normalized.attributedTo, "小王")
        XCTAssertEqual(normalized.epistemicStatus, .soft)
        XCTAssertFalse(KnowledgeQualificationValidator.issues(for: normalized)
            .contains(.missingAttribution))
    }

    func testQualificationBlocksQuestionPromotedToFact() {
        let value = candidate(
            kind: .fact,
            claimType: .observedFact,
            quote: "欧洲调查现在进展怎么样？")
        let normalized = KnowledgeCandidateNormalizer.normalize(
            value, sourceSensitivity: .normal,
            observedAt: observedAt(), calendar: utcCalendar())

        XCTAssertTrue(KnowledgeQualificationValidator.issues(for: normalized)
            .contains(.speechActMismatch))
    }

    func testQualificationBlocksHedgePromotedToCertainFact() {
        let value = candidate(
            kind: .fact,
            claimType: .observedFact,
            epistemicStatus: .certain,
            quote: "我觉得可能会有一些动荡")
        let normalized = KnowledgeCandidateNormalizer.normalize(
            value, sourceSensitivity: .normal,
            observedAt: observedAt(), calendar: utcCalendar())

        XCTAssertTrue(KnowledgeQualificationValidator.issues(for: normalized)
            .contains(.modalityStrengthened))
    }

    func testQualificationBlocksFirstPersonCommitmentTypedAsProposal() {
        let value = candidate(
            kind: .action,
            claimType: .proposal,
            quote: "我会跟 leadership 聊这个问题")
        let normalized = KnowledgeCandidateNormalizer.normalize(
            value, sourceSensitivity: .normal,
            observedAt: observedAt(), calendar: utcCalendar())

        XCTAssertTrue(KnowledgeQualificationValidator.issues(for: normalized)
            .contains(.speechActMismatch))
    }

    func testSpeakerBackedFirstPersonAttributionAndOwnerSurviveNormalization() {
        let value = candidate(
            kind: .action,
            claimType: .commitment,
            epistemicStatus: .certain,
            attributedTo: "Alice",
            owner: "Alice",
            quote: "我来跟进这个问题")
        let segment = KnowledgeSourceSegment(
            id: "segment-1", sourceID: "source-1", meetingID: "meeting-1", ordinal: 0,
            speaker: "Alice", startMS: 0, endMS: 1_000, charStart: 0, charEnd: 10,
            text: "我来跟进这个问题", contentHash: "hash", metadataJSON: "{}",
            createdAt: 1, updatedAt: 1)
        let normalized = KnowledgeCandidateNormalizer.normalize(
            value, sourceSensitivity: .normal, observedAt: observedAt(),
            segmentsByID: [segment.id: segment], calendar: utcCalendar())

        XCTAssertEqual(normalized.attributedTo, "Alice")
        XCTAssertEqual(normalized.owner, "Alice")
        XCTAssertFalse(KnowledgeQualificationValidator.issues(for: normalized)
            .contains(.missingAttribution))
        XCTAssertFalse(KnowledgeQualificationValidator.issues(for: normalized)
            .contains(.missingOwner))
    }

    func testDuplicateSemanticIDsReturnErrorInsteadOfCrashing() async throws {
        let value = candidate(quote: "虚构指标更新")
        let normalized = KnowledgeCandidateNormalizer.normalize(
            value, sourceSensitivity: .normal,
            observedAt: observedAt(), calendar: utcCalendar())
        let verifier = ModelKnowledgeCandidateVerifier(client: DuplicateSemanticVerifierClient())

        do {
            _ = try await verifier.verify(
                validated: [value], normalized: [normalized], segmentsByID: [:])
            XCTFail("expected duplicate ID rejection")
        } catch let error as KnowledgeExtractionError {
            XCTAssertEqual(error.localizedDescription, "知识语义验证包含重复候选 ID")
        }
    }

    func testSemanticVerifierAcceptsMissingOptionalReasons() async throws {
        let value = candidate(quote: "虚构指标更新")
        let normalized = KnowledgeCandidateNormalizer.normalize(
            value, sourceSensitivity: .normal,
            observedAt: observedAt(), calendar: utcCalendar())
        let verifier = ModelKnowledgeCandidateVerifier(client: SemanticVerifierFixtureClient(
            verdict: "entailed", includeReasons: false))

        let result = try await verifier.verify(
            validated: [value], normalized: [normalized], segmentsByID: [:])

        XCTAssertEqual(result["candidate-1"]?.verdict, .entailed)
        XCTAssertEqual(result["candidate-1"]?.reasons, [])
        XCTAssertEqual(KnowledgeVerificationAssessment.make(
            candidate: normalized,
            semantic: result["candidate-1"]).status, .passed)
    }

    func testSemanticUnsupportedCannotPassQualification() async throws {
        let value = candidate(quote: "虚构指标更新")
        let normalized = KnowledgeCandidateNormalizer.normalize(
            value, sourceSensitivity: .normal,
            observedAt: observedAt(), calendar: utcCalendar())
        let verifier = ModelKnowledgeCandidateVerifier(client: SemanticVerifierFixtureClient(
            verdict: "unsupported", includeReasons: false))
        let result = try await verifier.verify(
            validated: [value], normalized: [normalized], segmentsByID: [:])
        let assessment = KnowledgeVerificationAssessment.make(
            candidate: normalized,
            semantic: result["candidate-1"])

        XCTAssertEqual(assessment.status, .blocked)
        XCTAssertTrue(assessment.reasonsJSON.contains("semantic_unsupported"))
    }
}
