import Foundation
import HanlinPlatformContracts

public struct ExecuteSkillResourceTool: NativeTool {
    public let name = "execute_skill_resource"

    public var catalogEntry: NativeToolCatalogEntry {
        .init(
            name: name,
            title: RuntimeL10n.string("Execute Skill Resource"),
            summary: RuntimeL10n.string("Execute an approved script resource from a loaded skill bundle."),
            categories: ["runtime", "skills", "code"],
            keywords: ["skill", "script", "resource", "execute", "python", "js"],
            examples: ["Run skill script", "הרץ סקריפט מתוך ה-Skill"],
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

    public func openAIToolSchema() -> [String: Any] {
        NativeToolSchema.function(
            name: name,
            description: "Execute a script resource (such as a Python or JavaScript helper) belonging to an active skill package. Scripts run locally within the application sandbox. Path traversal outside the skill package is prohibited.",
            parameters: NativeToolSchema.object(
                properties: [
                    "skill_id": NativeToolSchema.string(description: "The unique identifier of the active skill."),
                    "relative_path": NativeToolSchema.string(description: "Relative path to the executable script inside the skill package (e.g. 'scripts/search.py')."),
                    "arguments": NativeToolSchema.stringArray(description: "Optional command-line arguments passed to the script via sys.argv."),
                    "timeout_seconds": NativeToolSchema.integer(description: "Timeout in seconds (default 30, maximum 300).", minimum: 1, maximum: 300)
                ],
                required: ["skill_id", "relative_path"]
            )
        )
    }

    public func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        do {
            let arguments = try NativeToolJSON.validatedDictionary(
                from: argumentsJSON,
                allowedKeys: ["skill_id", "relative_path", "arguments", "timeout_seconds"]
            )
            let skillIDRaw = try NativeToolJSON.strictRequiredString(arguments, "skill_id")
            let relPath = try NativeToolJSON.strictRequiredString(arguments, "relative_path")
            let argv = try NativeToolJSON.strictStringArray(arguments, "arguments")
            let timeout = try NativeToolJSON.strictInt(arguments, "timeout_seconds", default: 30, range: 1...300)

            guard let skillID = try? HanlinSkillID(validating: skillIDRaw) else {
                return RuntimeToolSupport.failure(
                    HanlinHostServiceError.invalidArguments("Invalid skill ID: \(skillIDRaw)"),
                    title: "Invalid Skill ID"
                )
            }

            // Path security validation
            let cleanPath = relPath.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
            guard !cleanPath.isEmpty,
                  !cleanPath.hasPrefix("/"),
                  !cleanPath.contains("\0") else {
                return RuntimeToolSupport.failure(
                    HanlinHostServiceError.invalidArguments("Invalid resource path '\(relPath)'."),
                    title: "Invalid Path"
                )
            }

            let components = cleanPath.split(separator: "/")
            if components.contains("..") || components.contains(".") {
                return RuntimeToolSupport.failure(
                    HanlinHostServiceError.invalidArguments("Directory traversal is not permitted."),
                    title: "Security Violation"
                )
            }

            // Resolve file strictly inside the skill store (never bundle fallback for execution!)
            guard let resourceURL = await MainActor.run(body: {
                SkillStore.shared.safeResourceURL(for: skillID, relativePath: cleanPath)
            }) else {
                return RuntimeToolSupport.failure(
                    HanlinHostServiceError.invalidArguments("Script '\(cleanPath)' not found in skill '\(skillIDRaw)' or path is outside package root."),
                    title: "Resource Not Found"
                )
            }

            guard FileManager.default.fileExists(atPath: resourceURL.path) else {
                return RuntimeToolSupport.failure(
                    HanlinHostServiceError.invalidArguments("Script file does not exist at '\(cleanPath)'."),
                    title: "File Not Found"
                )
            }

            // Read script content
            guard let scriptContent = try? String(contentsOf: resourceURL, encoding: .utf8) else {
                return RuntimeToolSupport.failure(
                    HanlinHostServiceError.invalidArguments("Unable to read script content as UTF-8."),
                    title: "Read Error"
                )
            }

            // Determine runtime kind from file extension
            let ext = resourceURL.pathExtension.lowercased()
            let runtimeKind: RuntimeKind
            switch ext {
            case "py":
                runtimeKind = .localPython
            case "js", "mjs":
                runtimeKind = .quickJS
            case "ts":
                runtimeKind = .typeScript
            default:
                return RuntimeToolSupport.failure(
                    HanlinHostServiceError.invalidArguments("Unsupported script file extension '.\(ext)'. Only .py, .js, and .ts are executable."),
                    title: "Unsupported Runtime"
                )
            }

            // Build isolated environment with workspace state
            let workspaceURL = FileManager.default.temporaryDirectory.appendingPathComponent("skill_\(skillIDRaw)")
            try? FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

            var scriptEnv = try await AppRuntimeCore.shared.environment.resolved(scopes: [.shared, .python])
            scriptEnv["CAIRO_GENIZAH_STATE_DIR"] = workspaceURL.path
            scriptEnv["SKILL_RESOURCE_DIR"] = resourceURL.deletingLastPathComponent().path
            scriptEnv["SKILL_ID"] = skillIDRaw

            let executionLimits = RuntimeExecutionLimits(timeout: .seconds(timeout))
            let fullArgv = [cleanPath] + argv

            let result = try await AgentHostServicesAdapter.executeRuntime(
                runtimeKind,
                source: scriptContent,
                arguments: fullArgv,
                environment: scriptEnv,
                limits: executionLimits
            )

            return RuntimeToolSupport.result(
                result,
                title: "Skill Resource: \(components.last ?? "")",
                systemImage: "terminal",
                runtimeKind: runtimeKind,
                argumentKeys: Array(arguments.keys)
            )
        } catch {
            return RuntimeToolSupport.failure(error, title: "Skill resource execution failed")
        }
    }
}
