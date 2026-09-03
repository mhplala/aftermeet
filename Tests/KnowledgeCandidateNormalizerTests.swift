import XCTest
@testable import AfterMeet

final class KnowledgeCandidateNormalizerTests: XCTestCase {
    private func candidate(
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
            clientID: "candidate-1", kind: .metric,
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
}
