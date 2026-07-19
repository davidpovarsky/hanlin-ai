import Foundation

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
    case databaseRecord
    case genericItem
}

struct AgentEvidenceItem: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var kind: AgentEvidenceKind

    var toolCallID: String?
    var toolName: String?
    var sequence: Int?
    var roundIndex: Int?

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
    var wasUsedInCompletedRun: Bool

    init(
        id: String = UUID().uuidString,
        kind: AgentEvidenceKind,
        toolCallID: String? = nil,
        toolName: String? = nil,
        sequence: Int? = nil,
        roundIndex: Int? = nil,
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
        wasUsedInCompletedRun: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.sequence = sequence
        self.roundIndex = roundIndex
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
        self.wasUsedInCompletedRun = wasUsedInCompletedRun
    }

    var primaryURL: URL? {
        [deepLink, url]
            .compactMap { $0 }
            .compactMap(URL.init(string:))
            .first
    }
}

struct AgentEvidenceGroup: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var items: [AgentEvidenceItem]
}
