import XCTest
@testable import AfterMeet

final class KnowledgeExtractionChunkerTests: XCTestCase {
    private func segment(_ ordinal: Int, textLength: Int = 100) -> KnowledgeSourceSegment {
        KnowledgeSourceSegment(
            id: "segment-\(ordinal)", sourceID: "source-1", meetingID: "meeting-1",
            ordinal: ordinal, speaker: ordinal.isMultiple(of: 2) ? "甲" : "乙",
            startMS: ordinal * 1_000, endMS: (ordinal + 1) * 1_000,
            charStart: ordinal * textLength, charEnd: (ordinal + 1) * textLength,
            text: String(repeating: Character(String(ordinal % 10)), count: textLength),
            contentHash: "hash-\(ordinal)", metadataJSON: "{}", createdAt: 1, updatedAt: 1)
    }

    func testEverySegmentIsCoreExactlyOnceAndAdjacentChunksCarryContextOnlyOverlap() {
        let input = (0..<14).map { segment($0) }.reversed()
        let chunks = KnowledgeExtractionChunker.chunks(
            from: Array(input), maximumCharacters: 1_800, overlapCount: 2)
        let allCore = chunks.flatMap { chunk in
            chunk.segments.filter { chunk.coreSegmentIDs.contains($0.id) }.map(\.id)
        }

        XCTAssertEqual(allCore, (0..<14).map { "segment-\($0)" })
        XCTAssertEqual(Set(allCore).count, 14)
        XCTAssertEqual(chunks.map(\.index), Array(chunks.indices))
        XCTAssertTrue(chunks.first?.contextSegmentIDs.isEmpty == true)
        for index in chunks.indices.dropFirst() {
            let priorCore = chunks[index - 1].segments
                .filter { chunks[index - 1].coreSegmentIDs.contains($0.id) }
                .map(\.id)
            XCTAssertEqual(chunks[index].contextSegmentIDs, Set(priorCore.suffix(2)))
            XCTAssertTrue(chunks[index].coreSegmentIDs.isDisjoint(with: chunks[index].contextSegmentIDs))
        }
        XCTAssertTrue(chunks.allSatisfy { $0.estimatedPayloadCharacters <= 1_800 })
    }

    func testSingleOversizedSegmentIsKeptAsOneRecoverableChunk() {
        let oversized = segment(0, textLength: 2_000)
        let chunks = KnowledgeExtractionChunker.chunks(
            from: [oversized], maximumCharacters: 500, overlapCount: 2)

        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].coreSegmentIDs, [oversized.id])
        XCTAssertEqual(chunks[0].segments, [oversized])
        XCTAssertGreaterThan(chunks[0].estimatedPayloadCharacters, 500)
    }

    func testPromptMarksOverlapAsContextOnlyAndCoreAsExtractable() {
        let context = segment(0)
        let core = segment(1)
        let prompt = KnowledgeExtractionPrompt.userPrompt(
            sourceHash: "hash",
            chunkIndex: 1,
            meetingTitle: "虚构会议",
            meetingDate: "9月3日",
            segments: [context, core],
            coreSegmentIDs: [core.id])

        XCTAssertTrue(prompt.contains("\"context_only\":true"))
        XCTAssertTrue(prompt.contains("\"context_only\":false"))
        XCTAssertTrue(prompt.contains(context.id))
        XCTAssertTrue(prompt.contains(core.id))
        XCTAssertTrue(KnowledgeExtractionPrompt.system.contains("至少有一条 support evidence 来自 context_only=false"))
    }

    func testEmptyInputAndInvalidLimitReturnNoChunks() {
        XCTAssertTrue(KnowledgeExtractionChunker.chunks(from: []).isEmpty)
        XCTAssertTrue(KnowledgeExtractionChunker.chunks(from: [segment(0)], maximumCharacters: 0).isEmpty)
    }
}
