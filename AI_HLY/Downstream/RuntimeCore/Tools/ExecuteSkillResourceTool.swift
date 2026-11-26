import Foundation
import HanlinPlatformContracts

struct ExecuteSkillResourceTool: NativeTool {
    let name = "execute_skill_resource"
    private let catalog: HanlinSkillCatalog?
    private let store: SkillStore?

    init(catalog: HanlinSkillCatalog? = nil, store: SkillStore? = nil) {
        self.catalog = catalog
        self.store = store
    }

    var catalogEntry: NativeToolCatalogEntry {
        .init(
            name: name,
            title: RuntimeL10n.string("Execute Skill Resource"),
            summary: RuntimeL10n.string("Execute a script resource from a loaded skill bundle."),
            categories: ["runtime", "skills", "code"],
            keywords: ["skill", "script", "resource", "execute", "python", "js"],
            examples: ["Run skill script", "הרץ סקריפט מתוך ה-Skill"],
            isSensitive: true,
            approval: .init(scopeParameters: ["skill_id", "relative_path"]),
            systemImage: "terminal",
            presentationProfile: RuntimeToolSupport.profile(
                name: name,
                image: "terminal",
                running: "Running skill resource",
                completed: "Skill resource execution complete",
                arguments: ["skill_id", "relative_path"]
            )
        )
    }

    func openAIToolSchema() -> [String: Any] {
        NativeToolSchema.function(
            name: name,
            description: "Execute a script resource (such as a Python or JavaScript helper) belonging to an active skill package. Scripts run locally within the application sandbox. Path traversal outside the skill package is prohibited.",
            parameters: NativeToolSchema.object(
                properties: [
                    "skill_id": NativeToolSchema.string(description: "The unique identifier of the active skill."),
                    "relative_path": NativeToolSchema.string(description: "Relative path to the executable script inside the skill package (e.g. 'scripts/search.py')."),
                    "arguments": NativeToolSchema.stringArray(description: "Command-line arguments after the script name: sys.argv[1:] in Python and process.argv.slice(2) in Node/TypeScript."),
                    "engine": NativeToolSchema.string(description: "Explicit original engine: node, typeScript, localPython, javaScriptCore or shell. Omit to use the declared resource-language route; availability is always checked."),
                    "timeout_seconds": NativeToolSchema.integer(description: "Optional deadline in seconds. Omit for no deadline; user cancellation and actual errors still stop execution.", minimum: 1)
                ],
                required: ["skill_id", "relative_path"]
            )
        )
    }

    func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        await SkillResourceExecutor(catalog: catalog, store: store).execute(
            argumentsJSON: argumentsJSON, session: context.capabilitySession)
    }
}
