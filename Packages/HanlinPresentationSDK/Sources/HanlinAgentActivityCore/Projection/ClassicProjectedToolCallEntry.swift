import Foundation
import HanlinLocalization
import HanlinPlatformContracts


/// Represents one discrete, chronologically ordered tool invocation and its user-facing output
/// within a single `AgentRun`, preventing output conflation or mislabeling across tools.
public struct ClassicProjectedToolCallEntry: Equatable, Sendable, Identifiable {
    public let id: String
    public let runID: UUID
    public let callID: String
    public let toolName: String
    public var sequence: Int = 0
    public var startedAt: Date = Date()
    public var status: AgentActivityStatus = .completed
    public var summary: String?
    public var output: String
    public var errorDescription: String?
    public var embeddedResultPayload: HanlinEmbeddedResultPayload?
    public var isMetaSkillOrDiscoveryTool: Bool

    public var statusText: String {
        switch status {
        case .running: return String(localized: "Running", bundle: HanlinLocalization.bundle)
        case .pending: return String(localized: "Pending", bundle: HanlinLocalization.bundle)
        case .completed: return String(localized: "Completed", bundle: HanlinLocalization.bundle)
        case .failed: return String(localized: "Failed", bundle: HanlinLocalization.bundle)
        case .cancelled: return String(localized: "Cancelled", bundle: HanlinLocalization.bundle)
        }
    }

    public static let metaToolNames = AgentActivityVisibilityPolicy.internalToolNames

    public static func isMetaTool(_ name: String) -> Bool {
        AgentActivityVisibilityPolicy.isInternalTool(name)
    }

    /// Formats a single entry for `ChatBubbleView.toolContentView()`, always keeping its own tool label
    /// when multiple tools execute in the same run.
    public func formattedBlock(includeHeader: Bool) -> String {
        let cleanName = toolName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanOutput = Self.sanitizeUserFacingToolOutput(output, isMetaSkillOrDiscoveryTool: isMetaSkillOrDiscoveryTool)
        let cleanSummary = summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var lines: [String] = []
        if includeHeader, !cleanName.isEmpty {
            lines.append("[\(cleanName)]")
        }
        if !cleanSummary.isEmpty,
           cleanSummary != cleanName,
           cleanSummary != cleanOutput,
           !ProgressSummarySanitizer.looksLikeRawChainOfThought(cleanSummary) {
            lines.append(cleanSummary)
        }
        if !cleanOutput.isEmpty {
            lines.append(cleanOutput)
        }
        return lines.joined(separator: "\n")
    }

    /// Strips any accidental raw `### Instructions` skill body from user-facing tool output for meta skill/discovery tools.
    /// Preserves legitimate user-facing markdown headings for domain tools.
    public static func sanitizeUserFacingToolOutput(_ raw: String, isMetaSkillOrDiscoveryTool: Bool = false) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if isMetaSkillOrDiscoveryTool {
            if let range = trimmed.range(of: "### Instructions") {
                let prefix = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !prefix.isEmpty {
                    return prefix
                }
                return "Skill loaded."
            }
        }
        return trimmed
    }

    public static func sanitizeUserFacingToolOutput(_ raw: String, toolName: String) -> String {
        sanitizeUserFacingToolOutput(raw, isMetaSkillOrDiscoveryTool: isMetaTool(toolName))
    }

    public init(
        id: String,
        runID: UUID,
        callID: String,
        toolName: String,
        sequence: Int = 0,
        startedAt: Date = Date(),
        status: AgentActivityStatus = .completed,
        summary: String? = nil,
        output: String,
        errorDescription: String? = nil,
        embeddedResultPayload: HanlinEmbeddedResultPayload? = nil,
        isMetaSkillOrDiscoveryTool: Bool
    ) {
        self.id = id
        self.runID = runID
        self.callID = callID
        self.toolName = toolName
        self.sequence = sequence
        self.startedAt = startedAt
        self.status = status
        self.summary = summary
        self.output = output
        self.errorDescription = errorDescription
        self.embeddedResultPayload = embeddedResultPayload
        self.isMetaSkillOrDiscoveryTool = isMetaSkillOrDiscoveryTool
    }
}
