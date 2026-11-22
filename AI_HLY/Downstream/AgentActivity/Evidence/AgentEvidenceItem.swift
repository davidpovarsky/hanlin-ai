import Foundation

/// The original transcript prefix is hashed at admission. Appending later text
/// does not move the anchor, and edited/replaced/history-mismatched text cannot borrow it.
struct AgentSourceClaimAnchor: Codable, Hashable, Sendable {
    let providerTextPartID: String
    let transcriptSegmentID: String
    let prefixSHA256: String
    let prefixUTF16Length: Int
    let startUTF16: Int
    let endUTF16: Int
}

struct AgentSourceCitation: Sendable {
    let textPartID: String
    let text: String
    let range: Range<Int>
    let source: AgentEvidenceItem
}

enum AgentEvidenceKind: String, Codable, Hashable, Sendable {
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

struct AgentEvidenceItem: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var kind: AgentEvidenceKind

    var toolCallID: String?
    var toolName: String?
    var sequence: Int?

    var title: String
    var subtitle: String?
    var sourceName: String?

    var url: String?
    var deepLink: String?
    var reference: String?
    var externalID: String?

    var snippet: String?
    var timestamp: Date?

    var wasReturnedToModel: Bool
    var claimAnchors: [AgentSourceClaimAnchor]?
    /// Exact additional URLs retained from admitted results for this canonical
    /// source. Optional so persisted records from before URL aliases still decode.
    var alternateURLs: [String]?

    init(
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

    var primaryURL: URL? {
        [deepLink, url]
            .compactMap { $0 }
            .compactMap(URL.init(string:))
            .first
    }
}
