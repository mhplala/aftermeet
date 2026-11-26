import XCTest
@testable import AfterMeet

final class KnowledgeArchiveMatcherTests: XCTestCase {
    private func archive(name: String,
                         body: String,
                         start: TimeInterval,
                         end: TimeInterval) -> TranscriptFile {
        TranscriptFile(
            url: URL(fileURLWithPath: "/tmp/" + name + ".txt"),
            title: name,
            chars: body.count,
            preview: String(body.prefix(40)),
            body: body,
            paragraphs: [body],
            start: Date(timeIntervalSince1970: start),
            end: Date(timeIntervalSince1970: end))
    }

    private func meeting(id: String,
                         transcript: String,
                         end: TimeInterval,
                         duration: Int = 600) -> StoredLiveMeeting {
        StoredLiveMeeting(
            id: id,
            title: id,
            timestamp: end,
            durationSec: duration,
            transcript: transcript,
            note: .processing())
    }

    func testMatchPriorityAndStatusesAreDeterministic() {
        let exactBody = String(repeating: "精确内容。", count: 80)
        let fingerprintBase = String(repeating: "指纹内容", count: 90)
        let fingerprintArchive = fingerprintBase + " A"
        let fingerprintMeeting = fingerprintBase + "A"
        let ambiguousBody = String(repeating: "重复内容。", count: 80)
        let timeBody = String(repeating: "仅靠时间匹配。", count: 60)
        let orphanBody = String(repeating: "完全没有对应会议。", count: 50)
        let ignoredBody = "太短"
        let archives = [
            archive(name: "exact", body: exactBody, start: 900_000, end: 900_100),
            archive(name: "fingerprint", body: fingerprintArchive, start: 800_000, end: 800_100),
            archive(name: "ambiguous", body: ambiguousBody, start: 700_000, end: 700_100),
            archive(name: "time", body: timeBody, start: 9_500, end: 9_900),
            archive(name: "orphan", body: orphanBody, start: 50_000, end: 50_100),
            archive(name: "ignored", body: ignoredBody, start: 60_000, end: 60_100)
        ]
        let meetings = [
            meeting(id: "meeting-exact", transcript: exactBody, end: 1_000),
            meeting(id: "meeting-fingerprint", transcript: fingerprintMeeting, end: 2_000),
            meeting(id: "meeting-ambiguous-a", transcript: ambiguousBody, end: 3_000),
            meeting(id: "meeting-ambiguous-b", transcript: ambiguousBody, end: 4_000),
            meeting(id: "meeting-time", transcript: "不同正文", end: 10_000)
        ]

        let first = KnowledgeArchiveMatcher.reconcile(archives: archives, meetings: meetings)
        let second = KnowledgeArchiveMatcher.reconcile(archives: archives, meetings: meetings)
        let byTitle = Dictionary(uniqueKeysWithValues: first.records.map { ($0.archiveTitle, $0) })

        XCTAssertEqual(first, second)
        XCTAssertEqual(byTitle["exact"]?.status, .matched)
        XCTAssertEqual(byTitle["exact"]?.basis, .exactHash)
        XCTAssertEqual(byTitle["exact"]?.candidateMeetingIDs, ["meeting-exact"])
        XCTAssertEqual(byTitle["fingerprint"]?.status, .matched)
        XCTAssertEqual(byTitle["fingerprint"]?.basis, .fingerprint)
        XCTAssertEqual(byTitle["ambiguous"]?.status, .ambiguous)
        XCTAssertEqual(byTitle["ambiguous"]?.candidateMeetingIDs.count, 2)
        XCTAssertEqual(byTitle["time"]?.status, .matched)
        XCTAssertEqual(byTitle["time"]?.basis, .timeOverlap)
        XCTAssertEqual(byTitle["orphan"]?.status, .orphan)
        XCTAssertEqual(byTitle["ignored"]?.status, .ignored)
        XCTAssertEqual(first.matchedCount, 3)
        XCTAssertEqual(first.ambiguousCount, 1)
        XCTAssertEqual(first.orphanCount, 1)
        XCTAssertEqual(first.ignoredCount, 1)
    }

    func testExactHashWinsDespiteTimezoneShiftAndMultipleTimeCandidates() {
        let body = String(repeating: "跨时区仍靠内容识别。", count: 40)
        let archive = archive(name: "timezone", body: body, start: 20_000, end: 20_100)
        let meetings = [
            meeting(id: "exact-far-away", transcript: body, end: 1_000),
            meeting(id: "time-a", transcript: "其他内容一", end: 20_050),
            meeting(id: "time-b", transcript: "其他内容二", end: 20_080)
        ]

        let record = KnowledgeArchiveMatcher.reconcile(
            archives: [archive], meetings: meetings).records[0]

        XCTAssertEqual(record.status, .matched)
        XCTAssertEqual(record.basis, .exactHash)
        XCTAssertEqual(record.candidateMeetingIDs, ["exact-far-away"])
    }

    func testMatcherDoesNotWriteDatabaseState() {
        let sourceCount = KnowledgeStore.shared.sources().count
        let jobCount = KnowledgeStore.shared.jobs().count
        let body = String(repeating: "纯分析报告。", count: 80)

        _ = KnowledgeArchiveMatcher.reconcile(
            archives: [archive(name: "pure", body: body, start: 1, end: 2)],
            meetings: [])

        XCTAssertEqual(KnowledgeStore.shared.sources().count, sourceCount)
        XCTAssertEqual(KnowledgeStore.shared.jobs().count, jobCount)
    }
}
