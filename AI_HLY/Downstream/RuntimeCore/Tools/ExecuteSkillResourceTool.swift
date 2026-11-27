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

    func openAIToolSchema() -> [String: Any] { SkillResourceExecutor.schema }

    func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        await SkillResourceExecutor(catalog: catalog, store: store).execute(
            argumentsJSON: argumentsJSON, session: context.capabilitySession)
    }
}
