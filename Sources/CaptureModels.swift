import Foundation

enum CaptureTranscriptionMode: String, Codable, Sendable {
    case cloud
    case local
    case mixed
    case unknown

    static func resolve(usedCloud: Bool, usedLocal: Bool) -> Self {
        switch (usedCloud, usedLocal) {
        case (true, true): return .mixed
        case (true, false): return .cloud
        case (false, true): return .local
        case (false, false): return .unknown
        }
    }
}

enum CaptureTimeline {
    static func absoluteRange(sessionOffsetMS: Int, startMS: Int, endMS: Int,
                              minimumStartMS: Int? = nil) -> ClosedRange<Int> {
        let rawStart = max(0, sessionOffsetMS + startMS)
        let start = max(rawStart, minimumStartMS ?? rawStart)
        let end = max(start, sessionOffsetMS + endMS)
        return start...end
    }

    static func approximateRange(sessionElapsedSec: Int, sampleCount: Int, sampleRate: Double,
                                 minimumStartMS: Int? = nil) -> ClosedRange<Int> {
        let end = max(0, sessionElapsedSec * 1000)
        let duration = sampleRate > 0 ? Int((Double(sampleCount) / sampleRate * 1000).rounded()) : 0
        let rawStart = max(0, end - duration)
        let start = min(end, max(rawStart, minimumStartMS ?? rawStart))
        return start...end
    }
}

enum CaptureTimingQuality: String, Codable, Sendable {
    case exact
    case approximate
    case unavailable
}

struct CapturedSegment: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let ordinal: Int
    let text: String
    let speaker: String?
    let startMS: Int?
    let endMS: Int?
    let timingQuality: CaptureTimingQuality
}

struct CapturedSegmentRecord: Codable, Hashable, Sendable {
    static let currentVersion = 1

    let version: Int
    let sessionID: String
    let segment: CapturedSegment

    init(sessionID: String, segment: CapturedSegment) {
        self.version = Self.currentVersion
        self.sessionID = sessionID
        self.segment = segment
    }
}

enum CaptureSidecarStore {
    static func create(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: url, options: .atomic)
    }

    static func append(_ record: CapturedSegmentRecord, to url: URL) throws {
        var data = try JSONEncoder().encode(record)
        data.append(0x0A)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.synchronize()
    }

    static func load(from url: URL) throws -> [CapturedSegmentRecord] {
        let data = try Data(contentsOf: url)
        return data.split(separator: 0x0A).compactMap { line in
            try? JSONDecoder().decode(CapturedSegmentRecord.self, from: Data(line))
        }
    }
}

struct CapturedTranscript: Codable, Hashable, Sendable {
    let text: String
    let segments: [CapturedSegment]
    let transcriptionMode: CaptureTranscriptionMode
    let sessionID: String
    let startedAt: TimeInterval
    let endedAt: TimeInterval
    let durationSec: Int
    let transcriptPath: String
    let segmentSidecarPath: String?
}
