import Foundation
import HanlinPlatformContracts

public enum LoadSkillTool {
    public static let toolName = "load_skill"

    public static var schema: [String: Any] {
        [
            "type": "function",
            "function": [
                "name": toolName,
                "description": "Load specialized instructions and enable tool access for a specific skill. Skills provide focused workflows and expose relevant tools on demand.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "skill_id": [
                            "type": "string",
                            "description": "The unique identifier of the skill to load (e.g. from the skill index)."
                        ]
                    ],
                    "required": ["skill_id"]
                ]
            ]
        ]
    }

    public struct Arguments: Decodable, Sendable {
        public let skill_id: String
    }

    @MainActor
    public static func execute(
        argumentsJSON: String,
        session: AssistantCapabilitySession,
        catalog: HanlinSkillCatalog = .shared,
        planner: AssistantToolExposurePlanner = AssistantToolExposurePlanner(),
        schemaSizes: [String: Int] = [:],
        availableAliases: Set<String>? = nil
    ) async -> String {
        guard let data = argumentsJSON.data(using: .utf8),
              let args = try? JSONDecoder().decode(Arguments.self, from: data) else {
            return "Error: Invalid arguments for load_skill. Expected JSON with 'skill_id'."
        }

        guard let descriptor = catalog.resolve(rawID: args.skill_id) else {
            let available = catalog.allSkills().map { $0.id.rawValue }.joined(separator: ", ")
            return "Error: Skill '\(args.skill_id)' not found. Available skills: [\(available)]."
        }

        let candidateAliases: [String]
        let unavailableAliases: [String]
        if let available = availableAliases {
            candidateAliases = descriptor.preferredToolIDs.filter { available.contains($0) }
            unavailableAliases = descriptor.preferredToolIDs.filter { !available.contains($0) }
        } else {
            candidateAliases = descriptor.preferredToolIDs
            unavailableAliases = []
        }

        if session.isSkillLoaded(descriptor.id) {
            let decision = planner.plan(
                candidateAliases: candidateAliases,
                schemaSizes: schemaSizes,
                currentlyExposedAliases: session.exposedToolAliases
            )

            if !decision.exposedAliases.isEmpty {
                session.exposeTools(aliases: decision.exposedAliases)
            }

            var response = "Skill '\(descriptor.title.preferredValue())' [\(descriptor.id.rawValue)] is already loaded."
            if !decision.exposedAliases.isEmpty {
                response += "\n\nNewly exposed tools:\n" + decision.exposedAliases.map { "- `\($0)`" }.joined(separator: "\n")
            }
            if !unavailableAliases.isEmpty {
                response += "\n\nUnavailable or disabled tools:\n" + unavailableAliases.map { "- `\($0)` (disabled)" }.joined(separator: "\n")
            }
            let allExposed = session.exposedToolAliases.sorted()
            if !allExposed.isEmpty {
                response += "\n\nCurrently exposed tools:\n" + allExposed.map { "- `\($0)`" }.joined(separator: "\n")
            }
            return response
        }

        let instructions = await catalog.loadInstructions(for: descriptor)
        session.recordSkillLoaded(
            id: descriptor.id,
            instructionText: instructions,
            preferredToolIDs: candidateAliases
        )

        let decision = planner.plan(
            candidateAliases: candidateAliases,
            schemaSizes: schemaSizes,
            currentlyExposedAliases: session.exposedToolAliases
        )

        if !decision.exposedAliases.isEmpty {
            session.exposeTools(aliases: decision.exposedAliases)
        }

        var response = "Skill '\(descriptor.title.preferredValue())' [\(descriptor.id.rawValue)] loaded successfully.\n\n"
        if !instructions.isEmpty {
            response += "### Instructions\n\(instructions)\n\n"
        }

        if !decision.exposedAliases.isEmpty {
            response += "The following tools are now exposed and ready to call:\n"
            for alias in decision.exposedAliases {
                response += "- `\(alias)`\n"
            }
        }
        if !unavailableAliases.isEmpty {
            response += "\nPreferred tools currently disabled or unavailable:\n"
            for alias in unavailableAliases {
                response += "- `\(alias)` (disabled)\n"
            }
        }
        if !decision.deferredAliases.isEmpty {
            response += "\nAdditional tools for this skill exceed the immediate schema budget and can be discovered with `tool_search` when needed:\n"
            for alias in decision.deferredAliases {
                response += "- `\(alias)`\n"
            }
        }

        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
