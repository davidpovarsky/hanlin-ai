import Foundation

enum AgentTranscriptItemKind: String, Codable, Hashable, Sendable {
    case reasoning
    case progress
    case toolActivity
    case assistantText
    case userVisibleToolResult
    case error
}

enum AgentTranscriptTextRole: String, Codable, Hashable, Sendable {
    case provisional
    case interim
    case final
}

enum AgentTranscriptCompletionVisibility: String, Codable, Hashable, Sendable {
    case collapseIntoThinking
    case remainInChat
}

struct AgentTranscriptItem: Codable, Hashable, Identifiable {
    var id: UUID
    var externalID: String?
    var sequence: Int
    var kind: AgentTranscriptItemKind

    var roundID: String?
    var callID: String?
    var toolName: String?
    var resultRendererKind: ToolResultRendererKind?
    var resultPresentationRequest: ToolResultPresentationRequest?
    var activityStepID: UUID?

    var startedAt: Date
    var completedAt: Date?
    var status: AgentActivityStatus

    var text: String?
    var nativeUIBlocks: [NativeUIBlock]

    var textRole: AgentTranscriptTextRole?
    var visibilityAfterCompletion: AgentTranscriptCompletionVisibility

    init(
        id: UUID = UUID(),
        externalID: String? = nil,
        sequence: Int,
        kind: AgentTranscriptItemKind,
        roundID: String? = nil,
        callID: String? = nil,
        toolName: String? = nil,
        resultRendererKind: ToolResultRendererKind? = nil,
        resultPresentationRequest: ToolResultPresentationRequest? = nil,
        activityStepID: UUID? = nil,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        status: AgentActivityStatus = .running,
        text: String? = nil,
        nativeUIBlocks: [NativeUIBlock] = [],
        textRole: AgentTranscriptTextRole? = nil,
        visibilityAfterCompletion: AgentTranscriptCompletionVisibility
    ) {
        self.id = id
        self.externalID = externalID
        self.sequence = sequence
        self.kind = kind
        self.roundID = roundID
        self.callID = callID
        self.toolName = toolName
        self.resultRendererKind = resultRendererKind
        self.resultPresentationRequest = resultPresentationRequest
        self.activityStepID = activityStepID
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.status = status
        self.text = text
        self.nativeUIBlocks = nativeUIBlocks
        self.textRole = textRole
        self.visibilityAfterCompletion = visibilityAfterCompletion
    }

    private enum CodingKeys: String, CodingKey {
        case id, externalID, sequence, kind, roundID, callID, toolName
        case resultRendererKind, resultPresentationRequest, activityStepID
        case startedAt, completedAt, status, text, nativeUIBlocks, textRole
        case visibilityAfterCompletion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        externalID = try container.decodeIfPresent(String.self, forKey: .externalID)
        sequence = try container.decodeIfPresent(Int.self, forKey: .sequence) ?? 0
        kind = try container.decodeIfPresent(AgentTranscriptItemKind.self, forKey: .kind) ?? .progress
        roundID = try container.decodeIfPresent(String.self, forKey: .roundID)
        callID = try container.decodeIfPresent(String.self, forKey: .callID)
        toolName = try container.decodeIfPresent(String.self, forKey: .toolName)
        resultRendererKind = try container.decodeIfPresent(ToolResultRendererKind.self, forKey: .resultRendererKind)
        resultPresentationRequest = try container.decodeIfPresent(ToolResultPresentationRequest.self, forKey: .resultPresentationRequest)
        activityStepID = try container.decodeIfPresent(UUID.self, forKey: .activityStepID)
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt) ?? Date()
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        status = try container.decodeIfPresent(AgentActivityStatus.self, forKey: .status) ?? .completed
        text = try container.decodeIfPresent(String.self, forKey: .text)
        nativeUIBlocks = try container.decodeIfPresent([NativeUIBlock].self, forKey: .nativeUIBlocks) ?? []
        textRole = try container.decodeIfPresent(AgentTranscriptTextRole.self, forKey: .textRole)
        visibilityAfterCompletion = try container.decodeIfPresent(
            AgentTranscriptCompletionVisibility.self,
            forKey: .visibilityAfterCompletion
        ) ?? .collapseIntoThinking
    }
}

extension AgentRun {
    var hasModernTranscript: Bool {
        schemaVersion >= 2
    }

    var hasMeaningfulThinkingActivity: Bool {
        transcriptItems.contains {
            $0.visibilityAfterCompletion == .collapseIntoThinking
                && $0.kind != .userVisibleToolResult
                && $0.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
    }
}
