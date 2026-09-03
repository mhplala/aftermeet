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

enum KnowledgeConflictStatus: String, Codable, CaseIterable, Sendable {
    case none
    case pending
    case resolved
}

struct KnowledgeUnit: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let kind: KnowledgeKind
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
    let reviewStatus: KnowledgeReviewStatus
    let evidenceLevel: KnowledgeEvidenceLevel
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
    var isMissingOwner: Bool { unit.kind == .action && unit.owner == nil }
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
