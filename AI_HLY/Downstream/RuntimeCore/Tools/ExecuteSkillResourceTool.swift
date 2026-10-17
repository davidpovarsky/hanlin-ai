import Foundation
import HanlinPlatformContracts

struct ExecuteSkillResourceTool: NativeTool {
    let name: String

    init(name: String = "execute_skill_resource") {
        self.name = name
    }

    var catalogEntry: NativeToolCatalogEntry {
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

    func openAIToolSchema() -> [String: Any] {
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

    func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
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
                    HanlinHostServiceError.invalidRequest("Invalid skill ID: \(skillIDRaw)"),
                    title: "Invalid Skill ID"
                )
            }

            // Require loaded and enabled Skill within the current active session context
            guard let session = context.capabilitySession else {
                return RuntimeToolSupport.failure(
                    HanlinHostServiceError.invalidRequest("Skill execution requires an active authorized session context."),
                    title: "Authorization Denied"
                )
            }

            guard session.isSkillLoaded(skillID) else {
                return RuntimeToolSupport.failure(
                    HanlinHostServiceError.invalidRequest("Skill '\(skillIDRaw)' is not currently loaded in this session. Call load_skill first."),
                    title: "Skill Not Loaded"
                )
            }

            guard await MainActor.run(body: { SkillStore.shared.isSkillEnabled(id: skillID) }) else {
                return RuntimeToolSupport.failure(
                    HanlinHostServiceError.invalidRequest("Skill '\(skillIDRaw)' is currently disabled."),
                    title: "Skill Disabled"
                )
            }

            // Path security validation: reject leading slash, empty, null bytes before normalization
            guard !relPath.isEmpty,
                  !relPath.hasPrefix("/"),
                  !relPath.contains("\0") else {
                return RuntimeToolSupport.failure(
                    HanlinHostServiceError.invalidRequest("Invalid resource path '\(relPath)': absolute paths and null bytes are rejected."),
                    title: "Invalid Path"
                )
            }

            let cleanPath = relPath.replacingOccurrences(of: "\\", with: "/")
            let components = cleanPath.split(separator: "/")
            if components.contains("..") || components.contains(".") {
                return RuntimeToolSupport.failure(
                    HanlinHostServiceError.invalidRequest("Directory traversal is not permitted."),
                    title: "Security Violation"
                )
            }

            // Resolve file strictly inside the skill store (never bundle fallback for execution!)
            guard let resourceURL = await MainActor.run(body: {
                SkillStore.shared.safeResourceURL(for: skillID, relativePath: cleanPath)
            }) else {
                return RuntimeToolSupport.failure(
                    HanlinHostServiceError.invalidRequest("Script '\(cleanPath)' not found in skill '\(skillIDRaw)' or path is outside package root."),
                    title: "Resource Not Found"
                )
            }

            let resourceValues = try? resourceURL.resourceValues(forKeys: [.isSymbolicLinkKey])
            if resourceValues?.isSymbolicLink == true {
                return RuntimeToolSupport.failure(
                    HanlinHostServiceError.invalidRequest("Symbolic links are not permitted."),
                    title: "Security Violation"
                )
            }

            guard FileManager.default.fileExists(atPath: resourceURL.path) else {
                return RuntimeToolSupport.failure(
                    HanlinHostServiceError.invalidRequest("Script file does not exist at '\(cleanPath)'."),
                    title: "File Not Found"
                )
            }

            // Read script content
            guard let scriptContent = try? String(contentsOf: resourceURL, encoding: .utf8) else {
                return RuntimeToolSupport.failure(
                    HanlinHostServiceError.invalidRequest("Unable to read script content as UTF-8."),
                    title: "Read Error"
                )
            }

            // Determine runtime kind from file extension
            let ext = resourceURL.pathExtension.lowercased()
            let runtimeKind: RuntimeKind
            let requiredCapability: String
            switch ext {
            case "py":
                runtimeKind = .localPython
                requiredCapability = "runtime.python"
            case "js", "mjs":
                runtimeKind = .node
                requiredCapability = "runtime.node"
            case "ts":
                runtimeKind = .typeScript
                requiredCapability = "runtime.typescript"
            default:
                return RuntimeToolSupport.failure(
                    HanlinHostServiceError.invalidRequest("Unsupported script file extension '.\(ext)'. Only .py, .js, and .ts are executable."),
                    title: "Unsupported Runtime"
                )
            }

            // Build isolated per-session/per-run workspace with automatic cleanup
            let sessionID = session.id.uuidString
            let runID = context.toolCallID ?? UUID().uuidString
            let workspaceID = "skill-\(skillIDRaw)-\(runID)"
            let workspaceURL = FileManager.default.temporaryDirectory.appendingPathComponent(workspaceID)
            try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: workspaceURL) }

            // Strictly allowlisted environment — never leak host secrets, PYTHONPATH, or PYTHONHOME
            var scriptEnv: [String: String] = [
                "CAIRO_GENIZAH_STATE_DIR": workspaceURL.path,
                "SKILL_RESOURCE_DIR": resourceURL.deletingLastPathComponent().path,
                "SKILL_ID": skillIDRaw,
                "TMPDIR": workspaceURL.path,
                "TEMP": workspaceURL.path
            ]
            let processEnv = ProcessInfo.processInfo.environment
            // Allow only minimal safe runtime path/locale vars; strictly avoid host PYTHONPATH/PYTHONHOME injection
            for key in ["PATH", "LANG", "LC_ALL"] {
                if let val = processEnv[key] {
                    scriptEnv[key] = val
                }
            }

            let executionLimits = RuntimeExecutionLimits(timeout: .seconds(timeout))
            let fullArgv = [cleanPath] + argv

            // Pass explicit restricted HanlinHostCallContext with only required capability (never 'all')
            let skillCallContext = HanlinHostCallContext.forSkill(
                skillID: skillID,
                capabilities: [requiredCapability, "files"],
                workspaceIdentifier: workspaceID
            )

            let result = try await AgentHostServicesAdapter.executeRuntime(
                runtimeKind,
                source: scriptContent,
                arguments: fullArgv,
                environment: scriptEnv,
                limits: executionLimits,
                context: skillCallContext
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
