import Foundation

/// The original transcript prefix is hashed at admission. Appending later text
/// does not move the anchor, and edited/replaced/history-mismatched text cannot borrow it.
public struct AgentSourceClaimAnchor: Codable, Hashable, Sendable {
    public let providerTextPartID: String
    public let transcriptSegmentID: String
    public let prefixSHA256: String
    public let prefixUTF16Length: Int
    public let startUTF16: Int
    public let endUTF16: Int

    public init(
        providerTextPartID: String,
        transcriptSegmentID: String,
        prefixSHA256: String,
        prefixUTF16Length: Int,
        startUTF16: Int,
        endUTF16: Int
    ) {
        self.providerTextPartID = providerTextPartID
        self.transcriptSegmentID = transcriptSegmentID
        self.prefixSHA256 = prefixSHA256
        self.prefixUTF16Length = prefixUTF16Length
        self.startUTF16 = startUTF16
        self.endUTF16 = endUTF16
    }
}

public struct AgentSourceCitation: Sendable {
    public let textPartID: String
    public let text: String
    public let range: Range<Int>
    public let source: AgentEvidenceItem

    public init(
        textPartID: String,
        text: String,
        range: Range<Int>,
        source: AgentEvidenceItem
    ) {
        self.textPartID = textPartID
        self.text = text
        self.range = range
        self.source = source
    }
}

public enum AgentEvidenceKind: String, Codable, Hashable, Sendable {
    case webPage
    case wikipediaArticle
    case sefariaSource
    case githubRepository
    case githubFile
    case githubCommit
    case document
    case file
    case reminder
    case calendarEvent
    case email
    case contact
    case genericItem
}

public struct AgentEvidenceItem: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var kind: AgentEvidenceKind

    public var toolCallID: String?
    public var toolName: String?
    public var sequence: Int?

    public var title: String
    public var subtitle: String?
    public var sourceName: String?

    public var url: String?
    public var deepLink: String?
    public var reference: String?
    public var externalID: String?

    public var snippet: String?
    public var timestamp: Date?

    public var wasReturnedToModel: Bool
    public var claimAnchors: [AgentSourceClaimAnchor]?
    /// Exact additional URLs retained from admitted results for this canonical
    /// source. Optional so persisted records from before URL aliases still decode.
    public var alternateURLs: [String]?

    public init(
        id: String = UUID().uuidString,
        kind: AgentEvidenceKind,
        toolCallID: String? = nil,
        toolName: String? = nil,
        sequence: Int? = nil,
        title: String,
        subtitle: String? = nil,
        sourceName: String? = nil,
        url: String? = nil,
        deepLink: String? = nil,
        reference: String? = nil,
        externalID: String? = nil,
        snippet: String? = nil,
        timestamp: Date? = nil,
        wasReturnedToModel: Bool,
        claimAnchors: [AgentSourceClaimAnchor]? = nil,
        alternateURLs: [String]? = nil
    ) {
        self.id = id
        self.kind = kind
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.sequence = sequence
        self.title = title
        self.subtitle = subtitle
        self.sourceName = sourceName
        self.url = url
        self.deepLink = deepLink
        self.reference = reference
        self.externalID = externalID
        self.snippet = snippet
        self.timestamp = timestamp
        self.wasReturnedToModel = wasReturnedToModel
        self.claimAnchors = claimAnchors
        self.alternateURLs = alternateURLs
    }

    public var primaryURL: URL? {
        [deepLink, url]
            .compactMap { $0 }
            .compactMap(URL.init(string:))
            .first
    }
}
