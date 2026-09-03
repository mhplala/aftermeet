import Foundation

enum ArchiveMatchStatus: String, Codable, Sendable {
    case matched
    case ambiguous
    case orphan
    case ignored
}

enum ArchiveMatchBasis: String, Codable, Sendable {
    case exactHash = "exact_hash"
    case fingerprint
    case timeOverlap = "time_overlap"
    case none
    case belowMinimum = "below_minimum"
}

struct ArchiveMatchRecord: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let archiveTitle: String
    let archivePath: String
    let characterCount: Int
    let startedAt: TimeInterval
    let endedAt: TimeInterval
    let contentHash: String
    let status: ArchiveMatchStatus
    let basis: ArchiveMatchBasis
    let candidateMeetingIDs: [String]
}

struct ArchiveReviewSession: Identifiable, Equatable, Sendable {
    let id: UUID
    let report: ArchiveMatchReport

    init(id: UUID = UUID(), report: ArchiveMatchReport) {
        self.id = id
        self.report = report
    }
}

struct ArchiveMatchReport: Codable, Equatable, Sendable {
    let records: [ArchiveMatchRecord]

    var matchedCount: Int { records.filter { $0.status == .matched }.count }
    var ambiguousCount: Int { records.filter { $0.status == .ambiguous }.count }
    var orphanCount: Int { records.filter { $0.status == .orphan }.count }
    var ignoredCount: Int { records.filter { $0.status == .ignored }.count }
}

enum KnowledgeArchiveMatcher {
    static func reconcile(archives: [TranscriptFile],
                          meetings: [StoredLiveMeeting],
                          minimumCharacters: Int = 300,
                          timeTolerance: TimeInterval = 10 * 60) -> ArchiveMatchReport {
        let meetingInfo = meetings.map { meeting in
            (
                meeting: meeting,
                hash: KnowledgeIdentity.contentHash(meeting.transcript),
                fingerprint: fingerprint(meeting.transcript)
            )
        }
        let records = archives.sorted {
            if $0.end != $1.end { return $0.end > $1.end }
            return $0.url.path < $1.url.path
        }.map { archive -> ArchiveMatchRecord in
            let hash = KnowledgeIdentity.contentHash(archive.body)
            let archiveID = "archive-" + String(KnowledgeIdentity.contentHash(
                archive.url.path + "\u{1F}" + hash).prefix(32))
            guard archive.chars >= minimumCharacters else {
                return ArchiveMatchRecord(
                    id: archiveID,
                    archiveTitle: archive.title,
                    archivePath: archive.url.path,
                    characterCount: archive.chars,
                    startedAt: archive.start.timeIntervalSince1970,
                    endedAt: archive.end.timeIntervalSince1970,
                    contentHash: hash,
                    status: .ignored,
                    basis: .belowMinimum,
                    candidateMeetingIDs: [])
            }

            let exact = meetingInfo.filter { $0.hash == hash }.map { $0.meeting.id }.sorted()
            if !exact.isEmpty {
                return record(
                    id: archiveID, archive: archive, hash: hash,
                    basis: .exactHash, candidates: exact)
            }

            let archiveFingerprint = fingerprint(archive.body)
            let matchingFingerprints = meetingInfo.filter {
                !archiveFingerprint.isEmpty && $0.fingerprint == archiveFingerprint
            }.map { $0.meeting.id }.sorted()
            if !matchingFingerprints.isEmpty {
                return record(
                    id: archiveID, archive: archive, hash: hash,
                    basis: .fingerprint, candidates: matchingFingerprints)
            }

            let archiveStart = min(archive.start.timeIntervalSince1970, archive.end.timeIntervalSince1970)
            let archiveEnd = max(archive.start.timeIntervalSince1970, archive.end.timeIntervalSince1970)
            let overlapping = meetingInfo.filter { info in
                let meetingEnd = info.meeting.timestamp
                let meetingStart = meetingEnd - Double(max(0, info.meeting.durationSec))
                return archiveStart - timeTolerance <= meetingEnd
                    && meetingStart - timeTolerance <= archiveEnd
            }.sorted {
                abs($0.meeting.timestamp - archiveEnd) < abs($1.meeting.timestamp - archiveEnd)
            }.map { $0.meeting.id }
            if !overlapping.isEmpty {
                return record(
                    id: archiveID, archive: archive, hash: hash,
                    basis: .timeOverlap, candidates: overlapping)
            }

            return ArchiveMatchRecord(
                id: archiveID,
                archiveTitle: archive.title,
                archivePath: archive.url.path,
                characterCount: archive.chars,
                startedAt: archive.start.timeIntervalSince1970,
                endedAt: archive.end.timeIntervalSince1970,
                contentHash: hash,
                status: .orphan,
                basis: .none,
                candidateMeetingIDs: [])
        }
        return ArchiveMatchReport(records: records)
    }

    private static func record(id: String,
                               archive: TranscriptFile,
                               hash: String,
                               basis: ArchiveMatchBasis,
                               candidates: [String]) -> ArchiveMatchRecord {
        ArchiveMatchRecord(
            id: id,
            archiveTitle: archive.title,
            archivePath: archive.url.path,
            characterCount: archive.chars,
            startedAt: archive.start.timeIntervalSince1970,
            endedAt: archive.end.timeIntervalSince1970,
            contentHash: hash,
            status: candidates.count == 1 ? .matched : .ambiguous,
            basis: basis,
            candidateMeetingIDs: candidates)
    }

    private static func fingerprint(_ text: String) -> String {
        String(text.filter { !$0.isWhitespace }.prefix(160))
    }
}
