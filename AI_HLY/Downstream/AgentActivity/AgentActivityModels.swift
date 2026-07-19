//
//  AgentActivityModels.swift
//  AI_HLY
//
//  Provider-neutral persisted activity models for one assistant run.
//

import Foundation

enum AgentActivityStatus: String, Codable, Hashable, Sendable {
    case pending
    case running
    case completed
    case failed
    case cancelled
}

enum AgentActivityKind: String, Codable, Hashable, Sendable {
    case reasoning
    case progress
    case planning
    case toolCall
    case toolExecution
    case webSearch
    case sourceRead
    case documentRead
    case codeExecution
    case map
    case calendar
    case health
    case nativeApp
    case result
    case error
    case cancellation
}

enum ProgressSummarySource: String, Codable, Hashable, Sendable {
    case model
    case providerReasoningSummary
    case applicationGenerated
}

struct AgentActivitySource: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var title: String
    var url: String?
    var domain: String?
    var providerName: String?
    var snippet: String?

    init(
        id: String = UUID().uuidString,
        title: String,
        url: String? = nil,
        domain: String? = nil,
        providerName: String? = nil,
        snippet: String? = nil
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.domain = domain ?? url.flatMap(URL.init(string:))?.host()
        self.providerName = providerName
        self.snippet = snippet
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, url, domain, providerName, sourceName, snippet
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        url = try container.decodeIfPresent(String.self, forKey: .url)
        domain = try container.decodeIfPresent(String.self, forKey: .domain)
            ?? url.flatMap(URL.init(string:))?.host()
        providerName = try container.decodeIfPresent(String.self, forKey: .providerName)
            ?? container.decodeIfPresent(String.self, forKey: .sourceName)
        snippet = try container.decodeIfPresent(String.self, forKey: .snippet)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(url, forKey: .url)
        try container.encodeIfPresent(domain, forKey: .domain)
        try container.encodeIfPresent(providerName, forKey: .providerName)
        try container.encodeIfPresent(snippet, forKey: .snippet)
    }

    var displayTitle: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty, URL(string: trimmedTitle)?.host() == nil {
            AgentSearchDiagnostics.sourceLabelResolved(strategy: "title")
            return trimmedTitle
        }
        if let domain, !domain.isEmpty {
            AgentSearchDiagnostics.sourceLabelResolved(strategy: "domain")
            return domain
        }
        if let host = url.flatMap(URL.init(string:))?.host(), !host.isEmpty {
            AgentSearchDiagnostics.sourceLabelResolved(strategy: "host")
            return host
        }
        AgentSearchDiagnostics.sourceLabelResolved(strategy: "fallback")
        return String(localized: "Source")
    }
}

struct AgentActivityStep: Codable, Hashable, Identifiable {
    var id: UUID
    var externalID: String?
    var sequence: Int
    var kind: AgentActivityKind
    var presentationProfile: ToolPresentationProfile?
    var resultPresentationRequest: ToolResultPresentationRequest?
    var title: String
    var subtitle: String?
    var userFacingSummary: String?
    var summarySource: ProgressSummarySource?
    var status: AgentActivityStatus
    var startedAt: Date
    var completedAt: Date?
    var input: String?
    var output: String?
    var queryItems: [String]
    var searchProviderName: String?
    var sourceItems: [AgentActivitySource]
    var richResultBlocks: [NativeUIBlock]
    var errorDescription: String?

    init(
        id: UUID = UUID(),
        externalID: String? = nil,
        sequence: Int,
        kind: AgentActivityKind,
        presentationProfile: ToolPresentationProfile? = nil,
        resultPresentationRequest: ToolResultPresentationRequest? = nil,
        title: String,
        subtitle: String? = nil,
        userFacingSummary: String? = nil,
        summarySource: ProgressSummarySource? = nil,
        status: AgentActivityStatus = .running,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        input: String? = nil,
        output: String? = nil,
        queryItems: [String] = [],
        searchProviderName: String? = nil,
        sourceItems: [AgentActivitySource] = [],
        richResultBlocks: [NativeUIBlock] = [],
        errorDescription: String? = nil
    ) {
        self.id = id
        self.externalID = externalID
        self.sequence = sequence
        self.kind = kind
        self.presentationProfile = presentationProfile
        self.resultPresentationRequest = resultPresentationRequest
        self.title = title
        self.subtitle = subtitle
        self.userFacingSummary = userFacingSummary
        self.summarySource = summarySource
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.input = input
        self.output = output
        self.queryItems = queryItems
        self.searchProviderName = searchProviderName
        self.sourceItems = sourceItems
        self.richResultBlocks = richResultBlocks
        self.errorDescription = errorDescription
    }

    private enum CodingKeys: String, CodingKey {
        case id, externalID, sequence, kind, presentationProfile, resultPresentationRequest
        case title, subtitle, userFacingSummary, summarySource
        case status, startedAt, completedAt, input, output, queryItems, searchProviderName, sourceItems
        case richResultBlocks, errorDescription
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        externalID = try container.decodeIfPresent(String.self, forKey: .externalID)
        sequence = try container.decodeIfPresent(Int.self, forKey: .sequence) ?? 0
        kind = try container.decodeIfPresent(AgentActivityKind.self, forKey: .kind) ?? .progress
        presentationProfile = try container.decodeIfPresent(ToolPresentationProfile.self, forKey: .presentationProfile)
        resultPresentationRequest = try container.decodeIfPresent(ToolResultPresentationRequest.self, forKey: .resultPresentationRequest)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        userFacingSummary = try container.decodeIfPresent(String.self, forKey: .userFacingSummary)
        summarySource = try container.decodeIfPresent(ProgressSummarySource.self, forKey: .summarySource)
        status = try container.decodeIfPresent(AgentActivityStatus.self, forKey: .status) ?? .completed
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt) ?? Date()
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        input = try container.decodeIfPresent(String.self, forKey: .input)
        output = try container.decodeIfPresent(String.self, forKey: .output)
        queryItems = try container.decodeIfPresent([String].self, forKey: .queryItems) ?? []
        searchProviderName = try container.decodeIfPresent(String.self, forKey: .searchProviderName)
        sourceItems = try container.decodeIfPresent([AgentActivitySource].self, forKey: .sourceItems) ?? []
        richResultBlocks = try container.decodeIfPresent([NativeUIBlock].self, forKey: .richResultBlocks) ?? []
        errorDescription = try container.decodeIfPresent(String.self, forKey: .errorDescription)
    }
}

struct AgentRun: Codable, Hashable, Identifiable {
    static let currentSchemaVersion = 4

    var schemaVersion: Int
    var id: UUID
    var groupID: UUID
    var providerID: String?
    var modelID: String?
    var startedAt: Date
    var completedAt: Date?
    var status: AgentActivityStatus
    var steps: [AgentActivityStep]
    var transcriptItems: [AgentTranscriptItem]
    var evidenceItems: [AgentEvidenceItem]
    var finalAnswer: String?

    init(
        schemaVersion: Int = currentSchemaVersion,
        id: UUID = UUID(),
        groupID: UUID,
        providerID: String? = nil,
        modelID: String? = nil,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        status: AgentActivityStatus = .running,
        steps: [AgentActivityStep] = [],
        transcriptItems: [AgentTranscriptItem] = [],
        evidenceItems: [AgentEvidenceItem] = [],
        finalAnswer: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.groupID = groupID
        self.providerID = providerID
        self.modelID = modelID
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.status = status
        self.steps = steps
        self.transcriptItems = transcriptItems
        self.evidenceItems = evidenceItems
        self.finalAnswer = finalAnswer
    }

    var elapsedTime: TimeInterval {
        max(0, (completedAt ?? Date()).timeIntervalSince(startedAt))
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, groupID, providerID, modelID, startedAt, completedAt
        case status, steps, transcriptItems, evidenceItems, finalAnswer
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        groupID = try container.decodeIfPresent(UUID.self, forKey: .groupID) ?? UUID()
        providerID = try container.decodeIfPresent(String.self, forKey: .providerID)
        modelID = try container.decodeIfPresent(String.self, forKey: .modelID)
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt) ?? Date()
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        status = try container.decodeIfPresent(AgentActivityStatus.self, forKey: .status) ?? .completed
        steps = try container.decodeIfPresent([AgentActivityStep].self, forKey: .steps) ?? []
        let decodedTranscript = try container.decodeIfPresent(
            [AgentTranscriptItem].self,
            forKey: .transcriptItems
        ) ?? []
        transcriptItems = AgentTranscriptValidation.normalized(
            decodedTranscript,
            promotingFinalAnswerForCompletedRun: status == .completed
        )
        evidenceItems = try container.decodeIfPresent([AgentEvidenceItem].self, forKey: .evidenceItems) ?? []
        finalAnswer = AgentTranscriptValidation.finalAnswer(in: transcriptItems)
    }
}

enum AgentSearchDiagnostics {
    static func queryCaptured(count: Int) {
        log("searchQueryCaptured", ["queryCount": count])
    }

    static func sourceCaptured(count: Int) {
        log("searchSourceCaptured", ["sourceCount": count])
    }

    static func sourceLabelResolved(strategy: String) {
        log("searchSourceLabelResolved", ["strategy": strategy])
    }

    private static func log(_ event: String, _ fields: [String: Any]) {
        guard AgentDiagnosticsConfiguration.level == .fullLocalDebug else { return }
        NativeToolTraceLogger.shared.log(event, fields)
    }
}
