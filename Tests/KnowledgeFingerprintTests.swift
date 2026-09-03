import XCTest
@testable import AfterMeet

final class KnowledgeFingerprintTests: XCTestCase {
    private func value(canonical: String,
                       numeric: Double? = nil,
                       validFrom: TimeInterval? = nil,
                       subject: String? = "松果计划") -> NormalizedKnowledgeCandidate {
        NormalizedKnowledgeCandidate(
            kind: .fact,
            canonicalText: canonical,
            subject: subject,
            predicate: "状态",
            objectText: canonical,
            numericValue: numeric,
            valueUnit: numeric == nil ? nil : "%",
            owner: nil,
            dueText: nil,
            validFrom: validFrom,
            validTo: nil,
            evidenceLevel: .direct,
            evidence: [],
            projectHints: [],
            sensitivity: .normal,
            payloadJSON: "{}")
    }

    func testFormattingDifferencesNormalizeButMeaningChangesDoNot() {
        let first = value(canonical: "继续试验。")
        let formattingOnly = value(canonical: " 继续 试验 ")
        let negated = value(canonical: "不继续试验")

        XCTAssertEqual(KnowledgeFingerprint.make(for: first), KnowledgeFingerprint.make(for: formattingOnly))
        XCTAssertNotEqual(KnowledgeFingerprint.make(for: first), KnowledgeFingerprint.make(for: negated))
    }

    func testNumbersAndDatesAlwaysChangeFingerprint() {
        let value42 = value(canonical: "留存更新", numeric: 42, validFrom: 100)
        let value47 = value(canonical: "留存更新", numeric: 47, validFrom: 100)
        let later42 = value(canonical: "留存更新", numeric: 42, validFrom: 200)

        XCTAssertNotEqual(KnowledgeFingerprint.make(for: value42), KnowledgeFingerprint.make(for: value47))
        XCTAssertNotEqual(KnowledgeFingerprint.make(for: value42), KnowledgeFingerprint.make(for: later42))
    }

    func testDuplicateGroupsOnlyIncludeExactConservativeFingerprints() {
        let first = value(canonical: "继续试验。")
        let duplicate = value(canonical: "继续 试验")
        let distinct = value(canonical: "停止试验")

        let groups = KnowledgeFingerprint.duplicateGroups([first, duplicate, distinct])

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].candidateIndexes, [0, 1])
        XCTAssertEqual(groups[0].fingerprint, KnowledgeFingerprint.make(for: first))
    }

    func testUnitIDIsStableForSameExtractionSiteButNotAcrossSources() {
        let fingerprint = KnowledgeFingerprint.make(for: value(canonical: "继续试验"))
        let first = KnowledgeFingerprint.unitID(
            sourceID: "source-1", chunkIndex: 2, clientID: "candidate-1",
            fingerprint: fingerprint, extractorVersion: "v1")
        let repeated = KnowledgeFingerprint.unitID(
            sourceID: "source-1", chunkIndex: 2, clientID: "candidate-1",
            fingerprint: fingerprint, extractorVersion: "v1")
        let anotherSource = KnowledgeFingerprint.unitID(
            sourceID: "source-2", chunkIndex: 2, clientID: "candidate-1",
            fingerprint: fingerprint, extractorVersion: "v1")
        let anotherVersion = KnowledgeFingerprint.unitID(
            sourceID: "source-1", chunkIndex: 2, clientID: "candidate-1",
            fingerprint: fingerprint, extractorVersion: "v2")

        XCTAssertEqual(first, repeated)
        XCTAssertNotEqual(first, anotherSource)
        XCTAssertNotEqual(first, anotherVersion)
    }
}
