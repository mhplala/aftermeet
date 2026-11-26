import CryptoKit
import Foundation

struct KnowledgeSourceBundle: Sendable {
    let document: KnowledgeSourceDocument
    let segments: [KnowledgeSourceSegment]
}

enum KnowledgeSegmenter {
    static func sourceBundle(from capture: CapturedTranscript,
                             meetingID: String,
                             sourceKindOverride: KnowledgeSourceKind? = nil,
                             sensitivity: KnowledgeSensitivity = .normal) -> KnowledgeSourceBundle {
        let inferredSourceKind: KnowledgeSourceKind = switch capture.transcriptionMode {
        case .cloud, .mixed: .liveCloud
        case .local, .unknown: .liveLocal
        }
        let sourceKind = sourceKindOverride ?? inferredSourceKind
        let hash = KnowledgeIdentity.contentHash(capture.text)
        let sourceID = KnowledgeIdentity.sourceID(
            meetingID: meetingID, sourceKind: sourceKind, contentHash: hash)
        let now = capture.endedAt
        var sourceMetadataObject: [String: Any] = [
            "captureSessionID": capture.sessionID,
            "transcriptionMode": capture.transcriptionMode.rawValue
        ]
        if let sidecarPath = capture.segmentSidecarPath {
            sourceMetadataObject["segmentSidecarPath"] = sidecarPath
        }
        let sourceMetadata = json(sourceMetadataObject)
        let document = KnowledgeSourceDocument(
            id: sourceID,
            meetingID: meetingID,
            sourceKind: sourceKind,
            locator: capture.transcriptPath,
            fullText: capture.text,
            contentHash: hash,
            sourceRevision: 1,
            startedAt: capture.startedAt,
            endedAt: capture.endedAt,
            language: nil,
            sensitivity: sensitivity,
            metadataJSON: sourceMetadata,
            createdAt: now,
            updatedAt: now)

        let segments: [KnowledgeSourceSegment]
        if capture.segments.isEmpty {
            segments = plainTextSegments(
                content: capture.text,
                sourceID: sourceID,
                meetingID: meetingID,
                observedAt: now,
                parser: "capture-fallback")
        } else {
            var searchStart = capture.text.startIndex
            segments = capture.segments.map { captured -> KnowledgeSourceSegment in
                let remaining = searchStart..<capture.text.endIndex
                let matched = capture.text.range(of: captured.text, range: remaining)
                    ?? capture.text.range(of: captured.text)
                let startIndex = matched?.lowerBound ?? searchStart
                let endIndex = matched?.upperBound ?? startIndex
                let charStart = capture.text.distance(from: capture.text.startIndex, to: startIndex)
                let charEnd = capture.text.distance(from: capture.text.startIndex, to: endIndex)
                if let matched, matched.upperBound >= searchStart { searchStart = matched.upperBound }
                return KnowledgeSourceSegment(
                    id: KnowledgeIdentity.segmentID(sourceID: sourceID, ordinal: captured.ordinal),
                    sourceID: sourceID,
                    meetingID: meetingID,
                    ordinal: captured.ordinal,
                    speaker: captured.speaker,
                    startMS: captured.startMS,
                    endMS: captured.endMS,
                    charStart: charStart,
                    charEnd: charEnd,
                    text: captured.text,
                    contentHash: KnowledgeIdentity.contentHash(captured.text),
                    metadataJSON: json([
                        "timingQuality": captured.timingQuality.rawValue,
                        "rangeMatched": matched != nil
                    ]),
                    createdAt: now,
                    updatedAt: now)
            }
        }
        return KnowledgeSourceBundle(document: document, segments: segments)
    }

    static func plainTextSourceBundle(content: String,
                                      meetingID: String,
                                      sourceKind: KnowledgeSourceKind = .archive,
                                      locator: String? = nil,
                                      startedAt: TimeInterval? = nil,
                                      endedAt: TimeInterval? = nil,
                                      observedAt: TimeInterval = Date().timeIntervalSince1970,
                                      sensitivity: KnowledgeSensitivity = .normal) -> KnowledgeSourceBundle {
        let hash = KnowledgeIdentity.contentHash(content)
        let sourceID = KnowledgeIdentity.sourceID(
            meetingID: meetingID, sourceKind: sourceKind, contentHash: hash)
        let document = KnowledgeSourceDocument(
            id: sourceID,
            meetingID: meetingID,
            sourceKind: sourceKind,
            locator: locator,
            fullText: content,
            contentHash: hash,
            sourceRevision: 1,
            startedAt: startedAt,
            endedAt: endedAt,
            language: nil,
            sensitivity: sensitivity,
            metadataJSON: json(["segmentation": "plain-text-v1"]),
            createdAt: observedAt,
            updatedAt: observedAt)
        return KnowledgeSourceBundle(
            document: document,
            segments: plainTextSegments(
                content: content,
                sourceID: sourceID,
                meetingID: meetingID,
                observedAt: observedAt,
                parser: "plain-text-v1"))
    }

    static func estimatedTokenCount(_ text: String) -> Int {
        let units = text.reduce(0) { $0 + tokenUnits($1) }
        return max(0, (units + 3) / 4)
    }

    private struct PlainTextRange {
        var start: Int
        var end: Int
        var tokenUnits: Int
    }

    private static func plainTextSegments(content: String,
                                          sourceID: String,
                                          meetingID: String,
                                          observedAt: TimeInterval,
                                          parser: String) -> [KnowledgeSourceSegment] {
        let characters = Array(content)
        guard !characters.isEmpty else { return [] }
        let minimumUnits = 250 * 4
        let targetUnits = 400 * 4
        let maximumUnits = 600 * 4
        var ranges: [PlainTextRange] = []
        var start = 0
        var cursor = 0
        var units = 0
        var lastBoundary: Int?
        var lastBoundaryUnits = 0

        func appendRange(end: Int, rangeUnits: Int) {
            guard end > start else { return }
            ranges.append(PlainTextRange(start: start, end: end, tokenUnits: rangeUnits))
        }

        while cursor < characters.count {
            units += tokenUnits(characters[cursor])
            cursor += 1
            if isNaturalBoundary(characters[cursor - 1]) {
                lastBoundary = cursor
                lastBoundaryUnits = units
            }

            if units >= targetUnits,
               let boundary = lastBoundary,
               boundary > start,
               lastBoundaryUnits >= minimumUnits {
                appendRange(end: boundary, rangeUnits: lastBoundaryUnits)
                start = boundary
                cursor = boundary
                units = 0
                lastBoundary = nil
                lastBoundaryUnits = 0
            } else if units >= maximumUnits {
                let useBoundary = lastBoundary != nil && lastBoundaryUnits >= minimumUnits
                let end = useBoundary ? lastBoundary! : cursor
                let emittedUnits = useBoundary ? lastBoundaryUnits : units
                appendRange(end: end, rangeUnits: emittedUnits)
                start = end
                cursor = end
                units = 0
                lastBoundary = nil
                lastBoundaryUnits = 0
            }
        }
        if start < characters.count {
            let tailUnits = characters[start...].reduce(0) { $0 + tokenUnits($1) }
            ranges.append(PlainTextRange(start: start, end: characters.count, tokenUnits: tailUnits))
        }

        if ranges.count >= 2, let tail = ranges.last {
            let tailText = String(characters[tail.start..<tail.end])
            let previousIndex = ranges.count - 2
            let combinedUnits = ranges[previousIndex].tokenUnits + tail.tokenUnits
            if tailText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || (tail.tokenUnits < minimumUnits && combinedUnits <= maximumUnits) {
                ranges[previousIndex].end = tail.end
                ranges[previousIndex].tokenUnits = combinedUnits
                ranges.removeLast()
            }
        }

        return ranges.enumerated().map { ordinal, range in
            let text = String(characters[range.start..<range.end])
            return KnowledgeSourceSegment(
                id: KnowledgeIdentity.segmentID(sourceID: sourceID, ordinal: ordinal),
                sourceID: sourceID,
                meetingID: meetingID,
                ordinal: ordinal,
                speaker: nil,
                startMS: nil,
                endMS: nil,
                charStart: range.start,
                charEnd: range.end,
                text: text,
                contentHash: KnowledgeIdentity.contentHash(text),
                metadataJSON: json([
                    "estimatedTokens": max(0, (range.tokenUnits + 3) / 4),
                    "parser": parser,
                    "timingQuality": "unavailable"
                ]),
                createdAt: observedAt,
                updatedAt: observedAt)
        }
    }

    private static func tokenUnits(_ character: Character) -> Int {
        character.unicodeScalars.allSatisfy { $0.value < 128 } ? 1 : 4
    }

    private static func isNaturalBoundary(_ character: Character) -> Bool {
        "。！？!?；;\n".contains(character)
    }

    static func feishuSourceBundle(content: String,
                                   meetingID: String,
                                   docToken: String,
                                   title: String = "",
                                   observedAt: TimeInterval = Date().timeIntervalSince1970,
                                   sensitivity: KnowledgeSensitivity? = nil) -> KnowledgeSourceBundle {
        let resolvedSensitivity = sensitivity
            ?? KnowledgeSensitivityClassifier.classify(title: title, content: content)
        let hash = KnowledgeIdentity.contentHash(content)
        let sourceID = KnowledgeIdentity.sourceID(
            meetingID: meetingID, sourceKind: .feishu, contentHash: hash)
        let document = KnowledgeSourceDocument(
            id: sourceID,
            meetingID: meetingID,
            sourceKind: .feishu,
            locator: docToken,
            fullText: content,
            contentHash: hash,
            sourceRevision: 1,
            startedAt: nil,
            endedAt: nil,
            language: nil,
            sensitivity: resolvedSensitivity,
            metadataJSON: json(["documentFormat": "markdown", "parserVersion": 1]),
            createdAt: observedAt,
            updatedAt: observedAt)
        let segments = parseFeishuSegments(
            content: content,
            sourceID: sourceID,
            meetingID: meetingID,
            observedAt: observedAt)
        return KnowledgeSourceBundle(document: document, segments: segments)
    }

    private struct FeishuHeader {
        let speaker: String
        let timeMS: Int
        let rawTime: String
        let inlineText: String
    }

    private struct FeishuDraft {
        let speaker: String
        let startMS: Int
        var endMS: Int
        let rawTime: String
        let charStart: Int
        var charEnd: Int
        var lines: [String]
    }

    private static let timeFirstPattern = try! NSRegularExpression(pattern:
        #"^\s*(?:[-*]\s*)?\[?(\d{1,2}):(\d{2})(?::(\d{2}))?\]?\s+(?:\*\*)?([^:：\n]{1,40}?)(?:\*\*)?\s*[:：]\s*(.*)$"#)
    private static let speakerFirstPattern = try! NSRegularExpression(pattern:
        #"^\s*(?:[-*]\s*)?(?:\*\*)?(.{1,40}?)(?:\*\*)?\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(?:[:：-]\s*)?(.*)$"#)
    private static let userNamePattern = try! NSRegularExpression(pattern:
        #"^.*user-name\s*[=:]\s*[\"']?([^\"'\]\s>]+).*?(\d{1,2}):(\d{2})(?::(\d{2}))?.*?(?:\]|>)?\s*(.*)$"#,
        options: [.caseInsensitive])

    private static func parseFeishuSegments(content: String,
                                             sourceID: String,
                                             meetingID: String,
                                             observedAt: TimeInterval) -> [KnowledgeSourceSegment] {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        var drafts: [FeishuDraft] = []
        var current: FeishuDraft?
        var charOffset = 0

        func flush(nextOffset: Int, nextStartMS: Int?) {
            guard var draft = current else { return }
            draft.charEnd = max(draft.charStart, min(content.count, nextOffset))
            if let nextStartMS { draft.endMS = max(draft.startMS, nextStartMS) }
            drafts.append(draft)
            current = nil
        }

        for substring in lines {
            let line = String(substring)
            if let header = feishuHeader(in: line) {
                flush(nextOffset: max(0, charOffset - 1), nextStartMS: header.timeMS)
                let initial = header.inlineText.trimmingCharacters(in: .whitespacesAndNewlines)
                current = FeishuDraft(
                    speaker: header.speaker,
                    startMS: header.timeMS,
                    endMS: header.timeMS,
                    rawTime: header.rawTime,
                    charStart: charOffset,
                    charEnd: charOffset + line.count,
                    lines: initial.isEmpty ? [] : [initial])
            } else if current != nil {
                let cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty { current?.lines.append(cleaned) }
            }
            charOffset += line.count + 1
        }
        flush(nextOffset: content.count, nextStartMS: nil)

        if drafts.isEmpty {
            return plainTextSegments(
                content: content,
                sourceID: sourceID,
                meetingID: meetingID,
                observedAt: observedAt,
                parser: "feishu-fallback")
        }

        return drafts.enumerated().compactMap { ordinal, draft in
            let text = draft.lines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return KnowledgeSourceSegment(
                id: KnowledgeIdentity.segmentID(sourceID: sourceID, ordinal: ordinal),
                sourceID: sourceID,
                meetingID: meetingID,
                ordinal: ordinal,
                speaker: draft.speaker,
                startMS: draft.startMS,
                endMS: draft.endMS,
                charStart: draft.charStart,
                charEnd: draft.charEnd,
                text: text,
                contentHash: KnowledgeIdentity.contentHash(text),
                metadataJSON: json([
                    "parser": "feishu-markdown",
                    "rawTime": draft.rawTime,
                    "timingQuality": "exact"
                ]),
                createdAt: observedAt,
                updatedAt: observedAt)
        }
    }

    private static func feishuHeader(in line: String) -> FeishuHeader? {
        if let groups = captures(timeFirstPattern, in: line),
           let speaker = cleanSpeaker(groups[4]) {
            return FeishuHeader(
                speaker: speaker,
                timeMS: timeMS(groups[1], groups[2], groups[3]),
                rawTime: rawTime(groups[1], groups[2], groups[3]),
                inlineText: groups[5] ?? "")
        }
        if let groups = captures(userNamePattern, in: line),
           let speaker = cleanSpeaker(groups[1]) {
            return FeishuHeader(
                speaker: speaker,
                timeMS: timeMS(groups[2], groups[3], groups[4]),
                rawTime: rawTime(groups[2], groups[3], groups[4]),
                inlineText: groups[5] ?? "")
        }
        if let groups = captures(speakerFirstPattern, in: line),
           let speaker = cleanSpeaker(groups[1]) {
            return FeishuHeader(
                speaker: speaker,
                timeMS: timeMS(groups[2], groups[3], groups[4]),
                rawTime: rawTime(groups[2], groups[3], groups[4]),
                inlineText: groups[5] ?? "")
        }
        return nil
    }

    private static func captures(_ regex: NSRegularExpression, in string: String) -> [String?]? {
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        guard let match = regex.firstMatch(in: string, range: range) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            let range = match.range(at: index)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: string) else { return nil }
            return String(string[swiftRange])
        }
    }

    private static func cleanSpeaker(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "#*-[]()（）\"'"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = value.lowercased()
        guard !value.isEmpty, value.count <= 40,
              !lower.contains("会议时间"), !lower.contains("meeting time"),
              !lower.contains("duration") else { return nil }
        return value
    }

    private static func timeMS(_ first: String?, _ second: String?, _ third: String?) -> Int {
        let a = Int(first ?? "0") ?? 0
        let b = Int(second ?? "0") ?? 0
        if let third, let c = Int(third) { return ((a * 60 + b) * 60 + c) * 1000 }
        return (a * 60 + b) * 1000
    }

    private static func rawTime(_ first: String?, _ second: String?, _ third: String?) -> String {
        [first, second, third].compactMap { $0 }.joined(separator: ":")
    }

    private static func json(_ object: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else { return "{}" }
        return string
    }
}

enum KnowledgeIdentity {
    static func normalizedForHash(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .precomposedStringWithCanonicalMapping
    }

    static func contentHash(_ text: String) -> String {
        sha256(normalizedForHash(text))
    }

    static func sourceID(meetingID: String,
                         sourceKind: KnowledgeSourceKind,
                         contentHash: String) -> String {
        "source-" + String(sha256(
            meetingID + "\u{1F}" + sourceKind.rawValue + "\u{1F}" + contentHash
        ).prefix(32))
    }

    static func segmentID(sourceID: String, ordinal: Int) -> String {
        "segment-" + String(sha256(sourceID + "\u{1F}" + String(ordinal)).prefix(32))
    }

    private static func sha256(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
