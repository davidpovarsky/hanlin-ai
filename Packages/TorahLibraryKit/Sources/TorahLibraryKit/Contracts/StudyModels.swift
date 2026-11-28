import Foundation

public enum StudyProcessingPolicy: String, Codable, Sendable {
    case localOnly = "local_only"
    case preferLocal = "prefer_local"
    case allowRemoteWithConsent = "allow_remote_with_consent"
}

public struct OCRPoint: Codable, Hashable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct OCRBoundingBox: Codable, Hashable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static let zero = OCRBoundingBox(x: 0, y: 0, width: 0, height: 0)
    public static let full = OCRBoundingBox(x: 0, y: 0, width: 1, height: 1)
}

public struct OCRRegion: Codable, Hashable, Sendable {
    public let boundingBox: OCRBoundingBox
    public let normalizedPolygon: [OCRPoint]?

    public init(boundingBox: OCRBoundingBox, normalizedPolygon: [OCRPoint]? = nil) {
        self.boundingBox = boundingBox
        self.normalizedPolygon = normalizedPolygon
    }
}

public struct StudyRequest: Codable, Hashable, Sendable {
    public let requestID: String
    public let chatID: String
    public let attachmentHandle: String
    public let selectedRegion: OCRRegion?
    public let language: String
    public let policy: StudyProcessingPolicy

    public init(
        requestID: String = UUID().uuidString,
        chatID: String,
        attachmentHandle: String,
        selectedRegion: OCRRegion? = nil,
        language: String = "he",
        policy: StudyProcessingPolicy = .preferLocal
    ) {
        self.requestID = requestID
        self.chatID = chatID
        self.attachmentHandle = attachmentHandle
        self.selectedRegion = selectedRegion
        self.language = language
        self.policy = policy
    }
}

public struct OCRLine: Codable, Hashable, Sendable, Identifiable {
    public var id: String { lineID }
    public let lineID: String
    public let rawText: String
    public let alternatives: [String]
    public let boundingBox: OCRBoundingBox
    public let polygon: [OCRPoint]?
    public let coordinateSpace: String
    public let reportedConfidence: Double?
    public let readingOrder: Int

    public init(
        lineID: String,
        rawText: String,
        alternatives: [String] = [],
        boundingBox: OCRBoundingBox,
        polygon: [OCRPoint]? = nil,
        coordinateSpace: String = "normalized_unit",
        reportedConfidence: Double? = nil,
        readingOrder: Int = 0
    ) {
        self.lineID = lineID
        self.rawText = rawText
        self.alternatives = alternatives
        self.boundingBox = boundingBox
        self.polygon = polygon
        self.coordinateSpace = coordinateSpace
        self.reportedConfidence = reportedConfidence
        self.readingOrder = readingOrder
    }
}

public struct OCREvidence: Codable, Hashable, Sendable, Identifiable {
    public var id: String { evidenceID }
    public let evidenceID: String
    public let imageHash: String
    public let imageWidth: Double
    public let imageHeight: Double
    public let orientation: String
    public let cropTransform: [Double]?
    public let providerID: String
    public let modelRevision: String
    public let rawText: String
    public let lines: [OCRLine]
    public let warnings: [String]
    public let createdAt: Date

    public init(
        evidenceID: String = UUID().uuidString,
        imageHash: String,
        imageWidth: Double,
        imageHeight: Double,
        orientation: String = "up",
        cropTransform: [Double]? = nil,
        providerID: String,
        modelRevision: String,
        rawText: String,
        lines: [OCRLine],
        warnings: [String] = [],
        createdAt: Date = Date()
    ) {
        self.evidenceID = evidenceID
        self.imageHash = imageHash
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.orientation = orientation
        self.cropTransform = cropTransform
        self.providerID = providerID
        self.modelRevision = modelRevision
        self.rawText = rawText
        self.lines = lines
        self.warnings = warnings
        self.createdAt = createdAt
    }
}

public enum PositionKind: String, Codable, Sendable {
    case canonicalRef
    case line
    case lineRange
    case pdfPage
    case segment
}

public struct SourceLocator: Codable, Hashable, Sendable {
    public let providerID: String
    public let corpusID: String
    public let corpusGeneration: String
    public let workKey: String
    public let positionKind: PositionKind
    public let positionValue: String
    public let versionID: String?
    public let editionID: String?

    public init(
        providerID: String,
        corpusID: String,
        corpusGeneration: String = "default",
        workKey: String,
        positionKind: PositionKind,
        positionValue: String,
        versionID: String? = nil,
        editionID: String? = nil
    ) {
        self.providerID = providerID
        self.corpusID = corpusID
        self.corpusGeneration = corpusGeneration
        self.workKey = workKey
        self.positionKind = positionKind
        self.positionValue = positionValue
        self.versionID = versionID
        self.editionID = editionID
    }

    public var persistenceKey: String {
        "\(providerID):\(corpusID):\(workKey):\(positionKind.rawValue):\(positionValue)"
    }

    public static func parse(persistenceKey: String) -> SourceLocator? {
        let parts = persistenceKey.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 5 else { return nil }
        guard let positionKind = PositionKind(rawValue: parts[3]) else { return nil }
        let positionValue = parts[4...].joined(separator: ":")
        return SourceLocator(
            providerID: parts[0],
            corpusID: parts[1],
            workKey: parts[2],
            positionKind: positionKind,
            positionValue: positionValue
        )
    }
}

public enum SourceRole: String, Codable, Sendable {
    case primaryWork
    case citedWork
    case commentary
    case liturgicalCommon
    case biblicalQuotation
}

public enum PhysicalEditionStatus: String, Codable, Sendable {
    case verified
    case probable
    case unknown
    case notApplicable
}

public struct AlignmentSpan: Codable, Hashable, Sendable {
    public let ocrLineIndex: Int
    public let ocrStartChar: Int
    public let ocrEndChar: Int
    public let sourceStartChar: Int
    public let sourceEndChar: Int
    public let matchQuality: Double

    public init(
        ocrLineIndex: Int,
        ocrStartChar: Int,
        ocrEndChar: Int,
        sourceStartChar: Int,
        sourceEndChar: Int,
        matchQuality: Double
    ) {
        self.ocrLineIndex = ocrLineIndex
        self.ocrStartChar = ocrStartChar
        self.ocrEndChar = ocrEndChar
        self.sourceStartChar = sourceStartChar
        self.sourceEndChar = sourceEndChar
        self.matchQuality = matchQuality
    }
}

public struct ScoreComponents: Codable, Hashable, Sendable {
    public let lexicalCoverage: Double
    public let sequenceOrderScore: Double
    public let boundaryMatchScore: Double
    public let anchorUniqueness: Double

    public init(
        lexicalCoverage: Double,
        sequenceOrderScore: Double,
        boundaryMatchScore: Double,
        anchorUniqueness: Double
    ) {
        self.lexicalCoverage = lexicalCoverage
        self.sequenceOrderScore = sequenceOrderScore
        self.boundaryMatchScore = boundaryMatchScore
        self.anchorUniqueness = anchorUniqueness
    }
}

public struct ExcerptCandidate: Codable, Hashable, Sendable, Identifiable {
    public var id: String { locator.persistenceKey }
    public let locator: SourceLocator
    public let workTitle: String
    public let matchedSourceText: String
    public let alignment: [AlignmentSpan]
    public let evidenceIDs: [String]
    public let scoreComponents: ScoreComponents
    public let overallScore: Double
    public let ambiguityReasons: [String]
    public let retrievalMode: String
    public let sourceRole: SourceRole
    public let physicalEditionStatus: PhysicalEditionStatus

    public init(
        locator: SourceLocator,
        workTitle: String,
        matchedSourceText: String,
        alignment: [AlignmentSpan],
        evidenceIDs: [String],
        scoreComponents: ScoreComponents,
        overallScore: Double,
        ambiguityReasons: [String] = [],
        retrievalMode: String = "lexical_anchor",
        sourceRole: SourceRole = .primaryWork,
        physicalEditionStatus: PhysicalEditionStatus = .unknown
    ) {
        self.locator = locator
        self.workTitle = workTitle
        self.matchedSourceText = matchedSourceText
        self.alignment = alignment
        self.evidenceIDs = evidenceIDs
        self.scoreComponents = scoreComponents
        self.overallScore = overallScore
        self.ambiguityReasons = ambiguityReasons
        self.retrievalMode = retrievalMode
        self.sourceRole = sourceRole
        self.physicalEditionStatus = physicalEditionStatus
    }
}

public enum IdentificationStatus: String, Codable, Sendable {
    case verified
    case ambiguous
    case notFound
    case insufficientImage
    case corpusUnavailable
    case cancelled
    case failed
}

public struct IdentificationResult: Codable, Hashable, Sendable {
    public let status: IdentificationStatus
    public let candidates: [ExcerptCandidate]
    public let selectedCandidate: ExcerptCandidate?
    public let searchedCorpora: [String]
    public let unavailableCorpora: [String]
    public let warnings: [String]
    public let requestID: String

    public init(
        status: IdentificationStatus,
        candidates: [ExcerptCandidate],
        selectedCandidate: ExcerptCandidate? = nil,
        searchedCorpora: [String] = [],
        unavailableCorpora: [String] = [],
        warnings: [String] = [],
        requestID: String
    ) {
        self.status = status
        self.candidates = candidates
        self.selectedCandidate = selectedCandidate
        self.searchedCorpora = searchedCorpora
        self.unavailableCorpora = unavailableCorpora
        self.warnings = warnings
        self.requestID = requestID
    }
}

public struct TorahLinkedSource: Identifiable, Hashable, Codable, Sendable {
    public var id: String { "\(sourceRef)|\(type)|\(category)" }
    public let sourceRef: String
    public let sourceHebrewRef: String?
    public let category: String
    public let type: String
    public let collectiveTitle: String?
    public let hebrewCollectiveTitle: String?
    public let hebrewText: String?
    public let englishText: String?
    public let versionTitle: String?
    public let license: String?
    public let provenance: String

    public init(
        sourceRef: String,
        sourceHebrewRef: String? = nil,
        category: String,
        type: String,
        collectiveTitle: String? = nil,
        hebrewCollectiveTitle: String? = nil,
        hebrewText: String? = nil,
        englishText: String? = nil,
        versionTitle: String? = nil,
        license: String? = nil,
        provenance: String = "library"
    ) {
        self.sourceRef = sourceRef
        self.sourceHebrewRef = sourceHebrewRef
        self.category = category
        self.type = type
        self.collectiveTitle = collectiveTitle
        self.hebrewCollectiveTitle = hebrewCollectiveTitle
        self.hebrewText = hebrewText
        self.englishText = englishText
        self.versionTitle = versionTitle
        self.license = license
        self.provenance = provenance
    }

    public var sourceTitle: String {
        collectiveTitle ?? sourceRef
    }

    public var primaryText: String {
        hebrewText ?? englishText ?? ""
    }
}

public struct TorahLinkedTopic: Identifiable, Hashable, Codable, Sendable {
    public var id: String { slug }
    public let slug: String
    public let titleHe: String?
    public let titleEn: String?
    public let provenance: String

    public init(slug: String, titleHe: String? = nil, titleEn: String? = nil, provenance: String = "library") {
        self.slug = slug
        self.titleHe = titleHe
        self.titleEn = titleEn
        self.provenance = provenance
    }

    public var topicTitle: String {
        titleHe ?? titleEn ?? slug
    }
}

public struct VersionMetadata: Codable, Hashable, Sendable {
    public let versionTitle: String
    public let versionTitleInHebrew: String?
    public let language: String

    public init(versionTitle: String, versionTitleInHebrew: String? = nil, language: String = "he") {
        self.versionTitle = versionTitle
        self.versionTitleInHebrew = versionTitleInHebrew
        self.language = language
    }
}

public struct LicenseMetadata: Codable, Hashable, Sendable {
    public let licenseName: String
    public let copyrightNotice: String?

    public init(licenseName: String, copyrightNotice: String? = nil) {
        self.licenseName = licenseName
        self.copyrightNotice = copyrightNotice
    }
}

public struct StudySource: Codable, Hashable, Sendable, Identifiable {
    public var id: String { locator.persistenceKey }
    public let locator: SourceLocator
    public let primaryText: String
    public let contextBefore: String?
    public let contextAfter: String?
    public let links: [TorahLinkedSource]
    public let topics: [TorahLinkedTopic]
    public let versionMetadata: VersionMetadata
    public let licenseMetadata: LicenseMetadata
    public let provenance: String
    public let retrievedAt: Date

    public init(
        locator: SourceLocator,
        primaryText: String,
        contextBefore: String? = nil,
        contextAfter: String? = nil,
        links: [TorahLinkedSource] = [],
        topics: [TorahLinkedTopic] = [],
        versionMetadata: VersionMetadata,
        licenseMetadata: LicenseMetadata,
        provenance: String = "otzaria",
        retrievedAt: Date = Date()
    ) {
        self.locator = locator
        self.primaryText = primaryText
        self.contextBefore = contextBefore
        self.contextAfter = contextAfter
        self.links = links
        self.topics = topics
        self.versionMetadata = versionMetadata
        self.licenseMetadata = licenseMetadata
        self.provenance = provenance
        self.retrievedAt = retrievedAt
    }
}
