import Foundation

enum KnowledgeSensitivity: String, Codable, CaseIterable, Sendable {
    case normal
    case restricted
}

enum KnowledgeSourceKind: String, Codable, CaseIterable, Sendable {
    case liveCloud = "live_cloud"
    case liveLocal = "live_local"
    case feishu
    case archive
}

struct KnowledgeSourceDocument: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let meetingID: String
    let sourceKind: KnowledgeSourceKind
    let locator: String?
    let fullText: String
    let contentHash: String
    let sourceRevision: Int
    let startedAt: TimeInterval?
    let endedAt: TimeInterval?
    let language: String?
    let sensitivity: KnowledgeSensitivity
    let metadataJSON: String
    let createdAt: TimeInterval
    let updatedAt: TimeInterval
}

struct KnowledgeSourceSegment: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let sourceID: String
    let meetingID: String
    let ordinal: Int
    let speaker: String?
    let startMS: Int?
    let endMS: Int?
    let charStart: Int
    let charEnd: Int
    let text: String
    let contentHash: String
    let metadataJSON: String
    let createdAt: TimeInterval
    let updatedAt: TimeInterval
}

enum KnowledgeKind: String, Codable, CaseIterable, Sendable {
    case fact
    case decision
    case action
    case openQuestion = "open_question"
    case metric
    case risk
    case dispute
}

enum KnowledgeReviewStatus: String, Codable, CaseIterable, Sendable {
    case candidate
    case confirmed
    case edited
    case rejected
}

enum KnowledgeEvidenceLevel: String, Codable, CaseIterable, Sendable {
    case direct
    case inferred
}

enum KnowledgeClaimType: String, Codable, CaseIterable, Sendable {
    case observedFact = "observed_fact"
    case attributedOpinion = "attributed_opinion"
    case forecast
    case proposal
    case decision
    case commitment
    case statusUpdate = "status_update"
    case openQuestion = "open_question"
}

enum KnowledgeEpistemicStatus: String, Codable, CaseIterable, Sendable {
    case certain
    case soft
    case tentative
    case conditional
}

enum KnowledgeVerificationStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case passed
    case blocked
}

enum KnowledgeObservationBasis: String, Codable, CaseIterable, Sendable {
    case meetingTime = "meeting_time"
    case ingestionTime = "ingestion_time"
    case unknown
}

enum KnowledgeConflictStatus: String, Codable, CaseIterable, Sendable {
    case none
    case pending
    case resolved
}

/// A topic-level understanding. Every substantive statement cites immutable source segments.
struct KnowledgeContextStatement: Codable, Hashable, Sendable {
    let text: String
    let segmentIDs: [String]
    enum CodingKeys: String, CodingKey { case text; case segmentIDs = "segment_ids" }
}

struct KnowledgeTopicContext: Codable, Hashable, Sendable {
    enum Retention: String, Codable, Sendable { case durable, historicalDecision = "historical_decision", transient }
    let topic: String
    let background: KnowledgeContextStatement
    let keyFacts: [KnowledgeContextStatement]
    let rationale: [KnowledgeContextStatement]
    let applicability: KnowledgeContextStatement?
    let unknowns: [String]
    let significance: String
    let retention: Retention
    enum CodingKeys: String, CodingKey {
        case topic, background, rationale, applicability, unknowns, significance, retention
        case keyFacts = "key_facts"
    }
    var searchText: String { ([topic, significance] + statements.map(\.text) + unknowns).joined(separator: " ") }
    var statements: [KnowledgeContextStatement] {
        [background] + keyFacts + rationale + (applicability.map { [$0] } ?? [])
    }
    static func from(payloadJSON: String) -> KnowledgeTopicContext? {
        guard let data = payloadJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let context = object["topic_context"],
              let json = try? JSONSerialization.data(withJSONObject: context) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: json)
    }
}

struct KnowledgeUnit: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let kind: KnowledgeKind
    let claimType: KnowledgeClaimType
    let epistemicStatus: KnowledgeEpistemicStatus
    let attributedTo: String?
    let canonicalText: String
    let subject: String?
    let predicate: String?
    let objectText: String?
    let numericValue: Double?
    let valueUnit: String?
    let owner: String?
    let dueText: String?
    let validFrom: TimeInterval?
    let validTo: TimeInterval?
    let observedAt: TimeInterval
    let observationBasis: KnowledgeObservationBasis
    let reviewStatus: KnowledgeReviewStatus
    let evidenceLevel: KnowledgeEvidenceLevel
    let verificationStatus: KnowledgeVerificationStatus
    let verificationReasonsJSON: String
    let verifierVersion: String?
    let verifiedAt: TimeInterval?
    let conflictStatus: KnowledgeConflictStatus
    let sensitivity: KnowledgeSensitivity
    let fingerprint: String
    let revision: Int
    let extractorVersion: String
    let promptVersion: String
    let schemaVersion: Int
    let model: String
    let payloadJSON: String
    let createdAt: TimeInterval
    let updatedAt: TimeInterval

    init(id: String,
         kind: KnowledgeKind,
         claimType: KnowledgeClaimType = .observedFact,
         epistemicStatus: KnowledgeEpistemicStatus = .certain,
         attributedTo: String? = nil,
         canonicalText: String,
         subject: String?,
         predicate: String?,
         objectText: String?,
         numericValue: Double?,
         valueUnit: String?,
         owner: String?,
         dueText: String?,
         validFrom: TimeInterval?,
         validTo: TimeInterval?,
         observedAt: TimeInterval,
         observationBasis: KnowledgeObservationBasis = .meetingTime,
         reviewStatus: KnowledgeReviewStatus,
         evidenceLevel: KnowledgeEvidenceLevel,
         verificationStatus: KnowledgeVerificationStatus = .pending,
         verificationReasonsJSON: String = "[]",
         verifierVersion: String? = nil,
         verifiedAt: TimeInterval? = nil,
         conflictStatus: KnowledgeConflictStatus,
         sensitivity: KnowledgeSensitivity,
         fingerprint: String,
         revision: Int,
         extractorVersion: String,
         promptVersion: String,
         schemaVersion: Int,
         model: String,
         payloadJSON: String,
         createdAt: TimeInterval,
         updatedAt: TimeInterval) {
        self.id = id
        self.kind = kind
        self.claimType = claimType
        self.epistemicStatus = epistemicStatus
        self.attributedTo = attributedTo
        self.canonicalText = canonicalText
        self.subject = subject
        self.predicate = predicate
        self.objectText = objectText
        self.numericValue = numericValue
        self.valueUnit = valueUnit
        self.owner = owner
        self.dueText = dueText
        self.validFrom = validFrom
        self.validTo = validTo
        self.observedAt = observedAt
        self.observationBasis = observationBasis
        self.reviewStatus = reviewStatus
        self.evidenceLevel = evidenceLevel
        self.verificationStatus = verificationStatus
        self.verificationReasonsJSON = verificationReasonsJSON
        self.verifierVersion = verifierVersion
        self.verifiedAt = verifiedAt
        self.conflictStatus = conflictStatus
        self.sensitivity = sensitivity
        self.fingerprint = fingerprint
        self.revision = revision
        self.extractorVersion = extractorVersion
        self.promptVersion = promptVersion
        self.schemaVersion = schemaVersion
        self.model = model
        self.payloadJSON = payloadJSON
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var topicContext: KnowledgeTopicContext? { KnowledgeTopicContext.from(payloadJSON: payloadJSON) }

    var searchContext: String {
        var values = [subject, predicate, objectText].compactMap { $0 }
        if let context = topicContext {
            values += [context.topic, context.significance] + context.statements.map(\.text) + context.unknowns
        }
        return values.joined(separator: " ")
    }

    var isTrusted: Bool {
        [.confirmed, .edited].contains(reviewStatus) && verificationStatus == .passed
    }

    var verificationReasons: [String] {
        guard let data = verificationReasonsJSON.data(using: .utf8),
              let reasons = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return reasons
    }
}

enum KnowledgeEvidenceRole: String, Codable, CaseIterable, Sendable {
    case support
    case counter
    case context
}

struct KnowledgeUnitSource: Codable, Hashable, Sendable {
    let unitID: String
    let segmentID: String
    let evidenceRole: KnowledgeEvidenceRole
    let quote: String
    let weight: Double
    let verified: Bool
}

enum KnowledgeProjectStatus: String, Codable, CaseIterable, Sendable {
    case active
    case paused
    case completed
    case archived
}

struct KnowledgeProject: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let normalizedName: String
    let aliases: [String]
    let status: KnowledgeProjectStatus
    let createdAt: TimeInterval
    let updatedAt: TimeInterval
}

enum KnowledgeAssignmentSource: String, Codable, CaseIterable, Sendable {
    case model
    case rule
    case user
}

enum KnowledgeLinkReviewStatus: String, Codable, CaseIterable, Sendable {
    case candidate
    case confirmed
    case rejected
}

struct KnowledgeUnitProject: Codable, Hashable, Sendable {
    let unitID: String
    let projectID: String
    let role: String
    let relevance: Double
    let assignmentSource: KnowledgeAssignmentSource
    let reviewStatus: KnowledgeLinkReviewStatus
}

enum KnowledgeRelationKind: String, Codable, CaseIterable, Sendable {
    case supersedes
    case contradicts
    case dependsOn = "depends_on"
    case sameAs = "same_as"
    case updates
}

struct KnowledgeUnitRelation: Codable, Hashable, Sendable {
    let fromUnitID: String
    let toUnitID: String
    let relationKind: KnowledgeRelationKind
    let reviewStatus: KnowledgeLinkReviewStatus
    let reason: String?
    let payloadJSON: String
    let createdAt: TimeInterval
}

enum KnowledgeFeedbackAction: String, Codable, CaseIterable, Sendable {
    case confirm
    case edit
    case reject
    case merge
    case split
    case relate
    case unrelate
    case restore
}

struct KnowledgeFeedbackEvent: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let targetType: String
    let targetID: String
    let action: KnowledgeFeedbackAction
    let beforeJSON: String?
    let afterJSON: String?
    let reason: String?
    let actor: String
    let createdAt: TimeInterval
}

enum KnowledgeExtractionJobKind: String, Codable, CaseIterable, Sendable {
    case segment
    case extract
    case index
    case reextract
}

enum KnowledgeExtractionJobState: String, Codable, CaseIterable, Sendable {
    case pending
    case running
    case retry
    case failed
    case done
    case cancelled
}

struct KnowledgeExtractionJob: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let sourceID: String
    let jobKind: KnowledgeExtractionJobKind
    let state: KnowledgeExtractionJobState
    let inputHash: String
    let extractorVersion: String
    let cursor: Int
    let attempt: Int
    let nextRetryAt: TimeInterval?
    let leaseUntil: TimeInterval?
    let lastError: String?
    let createdAt: TimeInterval
    let updatedAt: TimeInterval
}

struct KnowledgeCitation: Identifiable, Codable, Hashable, Sendable {
    var id: String { segmentID }
    let segmentID: String
    let meetingID: String
    let meetingTitle: String
    let quote: String
    let speaker: String?
    let startMS: Int?
    let endMS: Int?
    let charStart: Int
    let charEnd: Int
}

struct KnowledgeAnswer: Codable, Equatable, Sendable {
    let answer: String
    let citations: [KnowledgeCitation]
    let insufficient: Bool
    let conflicts: [String]
}

enum KnowledgeExtractionDiagnosticOutcome: String, Codable, Sendable {
    case completed
    case rejected
    case retry
    case failed
}

struct KnowledgeExtractionDiagnostic: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let jobID: String
    let sourceID: String
    let chunkIndex: Int
    let inputCharacters: Int
    let outputCharacters: Int
    let candidateCount: Int
    let acceptedCount: Int
    let invalidEvidenceCount: Int
    let durationMS: Int
    let retryCount: Int
    let outcome: KnowledgeExtractionDiagnosticOutcome
    let errorCode: String?
    let createdAt: TimeInterval
}

enum KnowledgeConflictResolution: String, Codable, Sendable {
    case keepBoth = "keep_both"
    case supersedes
    case contradicts
}

struct KnowledgeBackfillProgress: Equatable, Sendable {
    let total: Int
    let completed: Int
    let running: Int
    let waiting: Int
    let failed: Int
    let cancelled: Int
    let candidateUnits: Int

    var finished: Int { completed + failed + cancelled }
    var fraction: Double { total == 0 ? 0 : Double(finished) / Double(total) }
}

struct KnowledgeConflictReview: Identifiable, Equatable, Sendable {
    let id: String
    let primary: KnowledgeInboxItem
    let alternatives: [KnowledgeInboxItem]
}

struct KnowledgeDuplicateReview: Identifiable, Equatable, Sendable {
    let id: String
    let items: [KnowledgeInboxItem]
}

struct KnowledgeInboxEvidence: Identifiable, Equatable, Sendable {
    var id: String { link.unitID + ":" + segment.id + ":" + link.evidenceRole.rawValue }
    let link: KnowledgeUnitSource
    let segment: KnowledgeSourceSegment
    let source: KnowledgeSourceDocument
}

struct KnowledgeInboxItem: Identifiable, Equatable, Sendable {
    var id: String { unit.id }
    let unit: KnowledgeUnit
    let evidence: [KnowledgeUnitSource]
    let sources: [KnowledgeSourceDocument]
    let projectLinks: [KnowledgeUnitProject]
    let evidenceContexts: [KnowledgeInboxEvidence]
    let duplicateCount: Int

    init(unit: KnowledgeUnit,
         evidence: [KnowledgeUnitSource],
         sources: [KnowledgeSourceDocument],
         projectLinks: [KnowledgeUnitProject],
         evidenceContexts: [KnowledgeInboxEvidence] = [],
         duplicateCount: Int) {
        self.unit = unit
        self.evidence = evidence
        self.sources = sources
        self.projectLinks = projectLinks
        self.evidenceContexts = evidenceContexts
        self.duplicateCount = duplicateCount
    }

    var sourceKinds: Set<KnowledgeSourceKind> { Set(sources.map(\.sourceKind)) }
    var meetingIDs: Set<String> { Set(sources.map(\.meetingID)) }
    var isMissingOwner: Bool { unit.claimType == .commitment && unit.owner == nil }
}

struct KnowledgeUnitEdits: Equatable, Sendable {
    let canonicalText: String
    let subject: String?
    let predicate: String?
    let objectText: String?
    let numericValue: Double?
    let valueUnit: String?
    let owner: String?
    let dueText: String?
    let validFrom: TimeInterval?
    let validTo: TimeInterval?
    let claimType: KnowledgeClaimType?
    let epistemicStatus: KnowledgeEpistemicStatus?
    let attributedTo: String?
    let kind: KnowledgeKind?
    let evidenceLevel: KnowledgeEvidenceLevel?

    init(canonicalText: String,
         subject: String?,
         predicate: String?,
         objectText: String?,
         numericValue: Double?,
         valueUnit: String?,
         owner: String?,
         dueText: String?,
         validFrom: TimeInterval?,
         validTo: TimeInterval?,
         claimType: KnowledgeClaimType? = nil,
         epistemicStatus: KnowledgeEpistemicStatus? = nil,
         attributedTo: String? = nil,
         kind: KnowledgeKind? = nil,
         evidenceLevel: KnowledgeEvidenceLevel? = nil) {
        self.canonicalText = canonicalText
        self.subject = subject
        self.predicate = predicate
        self.objectText = objectText
        self.numericValue = numericValue
        self.valueUnit = valueUnit
        self.owner = owner
        self.dueText = dueText
        self.validFrom = validFrom
        self.validTo = validTo
        self.claimType = claimType
        self.epistemicStatus = epistemicStatus
        self.attributedTo = attributedTo
        self.kind = kind
        self.evidenceLevel = evidenceLevel
    }
}

struct KnowledgeUnitCommit: Equatable, Sendable {
    let unit: KnowledgeUnit
    let evidence: [KnowledgeUnitSource]
    let projectLinks: [KnowledgeUnitProject]
    let suggestedRelations: [KnowledgeUnitRelation]
    let meetingID: String
    let meetingTitle: String

    init(unit: KnowledgeUnit,
         evidence: [KnowledgeUnitSource],
         projectLinks: [KnowledgeUnitProject],
         suggestedRelations: [KnowledgeUnitRelation] = [],
         meetingID: String,
         meetingTitle: String) {
        self.unit = unit
        self.evidence = evidence
        self.projectLinks = projectLinks
        self.suggestedRelations = suggestedRelations
        self.meetingID = meetingID
        self.meetingTitle = meetingTitle
    }
}

struct KnowledgeDatabaseDiagnostics: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let baseHealthy: Bool
    let knowledgeHealthy: Bool
    let tableCounts: [String: Int]
    let jobCounts: [String: Int]
    let foreignKeyViolations: Int
    let orphanReferences: Int
    let missingFTSRows: Int
    let orphanFTSRows: Int
    let duplicateFTSRows: Int
    let error: String?

    var isClean: Bool {
        baseHealthy && knowledgeHealthy
            && foreignKeyViolations == 0
            && orphanReferences == 0
            && missingFTSRows == 0
            && orphanFTSRows == 0
            && duplicateFTSRows == 0
    }
}

struct WorkQATurn: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let question: String
    var answer: KnowledgeAnswer?

    init(id: UUID = UUID(), question: String, answer: KnowledgeAnswer? = nil) {
        self.id = id
        self.question = question
        self.answer = answer
    }
}
