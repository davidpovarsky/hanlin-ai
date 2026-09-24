import Foundation
import HanlinPlatformContracts

/// Request-scoped capability session tracking dynamically exposed tools,
/// loaded skills, and large tool result storage for a single assistant turn/run.
///
/// Must NOT leak exposed schemas or loaded skills across unrelated user requests.
/// Reused across recursive steps within the same run.
@MainActor
public final class AssistantCapabilitySession {
    public let id: UUID
    public let resultStore: ToolResultStore

    public private(set) var loadedSkillIDs: Set<HanlinSkillID> = []
    public private(set) var loadedInstructionTexts: [String] = []
    public var loadedSkillInstructions: [String] { loadedInstructionTexts }
    public private(set) var activeSkillToolHints: Set<String> = []
    public private(set) var exposedToolAliases: Set<String> = []
    public private(set) var discoveredToolAliases: [String] = []

    public init(
        id: UUID = UUID(),
        resultStore: ToolResultStore = ToolResultStore(),
        initialExposedAliases: Set<String> = []
    ) {
        self.id = id
        self.resultStore = resultStore
        self.exposedToolAliases = initialExposedAliases
    }

    /// Mark a skill as loaded, append its instructions and record preferred tool hints.
    public func recordSkillLoaded(
        id: HanlinSkillID,
        instructionText: String,
        preferredToolIDs: [String] = []
    ) {
        loadedSkillIDs.insert(id)
        if !instructionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            loadedInstructionTexts.append(instructionText)
        }
        for hint in preferredToolIDs {
            activeSkillToolHints.insert(hint)
        }
    }

    /// Expose tool aliases for model-visibility in subsequent recursive rounds.
    public func exposeTools(aliases: [String]) {
        for alias in aliases {
            exposedToolAliases.insert(alias)
            if !discoveredToolAliases.contains(alias) {
                discoveredToolAliases.append(alias)
            }
        }
    }

    /// Check if a skill is already loaded.
    public func isSkillLoaded(_ id: HanlinSkillID) -> Bool {
        loadedSkillIDs.contains(id)
    }

    /// Check if a tool alias is currently exposed.
    public func isToolExposed(_ alias: String) -> Bool {
        exposedToolAliases.contains(alias)
    }

    /// Clears run-scoped state and expires stored large tool results.
    public func reset() {
        loadedSkillIDs.removeAll()
        loadedInstructionTexts.removeAll()
        activeSkillToolHints.removeAll()
        exposedToolAliases.removeAll()
        discoveredToolAliases.removeAll()
        resultStore.clear()
    }

    /// Explicitly finishes the current assistant run, clearing temporary stored results.
    public func finishRun() {
        resultStore.clear()
    }
}
