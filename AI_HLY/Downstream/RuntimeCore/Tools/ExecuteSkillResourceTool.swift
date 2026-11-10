import Foundation
import HanlinPlatformContracts

struct ExecuteSkillResourceTool: NativeTool {
    let name = "execute_skill_resource"
    private let catalog: HanlinSkillCatalog?

    init(catalog: HanlinSkillCatalog? = nil) {
        self.catalog = catalog
    }

    var catalogEntry: NativeToolCatalogEntry {
        .init(
            name: name,
            title: RuntimeL10n.string("Execute Skill Resource"),
            summary: RuntimeL10n.string("Execute a script resource from a loaded skill bundle."),
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
                    "arguments": NativeToolSchema.stringArray(description: "Command-line arguments after the script name: sys.argv[1:] in Python and process.argv.slice(2) in Node/TypeScript."),
                    "timeout_seconds": NativeToolSchema.integer(description: "Optional deadline in seconds. Omit for no deadline; user cancellation and actual errors still stop execution.", minimum: 1)
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
            let executionLimits = try RuntimeToolSupport.limits(arguments)

            guard let skillID = try? HanlinSkillID(validating: skillIDRaw) else {
                return RuntimeToolSupport.failure(
                    HanlinHostServiceError.invalidRequest("Invalid skill ID: \(skillIDRaw)"),
                    title: "Invalid Skill ID"
                )
            }

            // Use the loaded Skill context; this is not an additional permission grant.
            guard let session = context.capabilitySession else {
                return RuntimeToolSupport.failure(
                    HanlinHostServiceError.invalidRequest("Skill execution requires an active conversation context. Call load_skill first."),
                    title: "Missing Skill Context"
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

            // Use the same catalog/source resolver as read_skill_resource, including
            // installed package generations. A loaded instruction is not a second file store.
            guard let resourceURL = await MainActor.run(body: {
                let activeCatalog = catalog ?? HanlinSkillCatalog.shared
                guard activeCatalog.resolve(id: skillID) != nil else { return nil as URL? }
                return activeCatalog.resolveResourceURL(skillID: skillID, relativePath: cleanPath)
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
            let runID = UUID().uuidString.lowercased()
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

            // Runtime actors supply argv[0] / the Node entry point. Preserve
            // user arguments exactly, without inserting the logical resource path.

            // Retain Skill identity and legacy capability metadata; the host applies its autonomous policy.
            let skillCallContext = HanlinHostCallContext.forSkill(
                skillID: skillID,
                capabilities: [requiredCapability, "files"],
                workspaceIdentifier: workspaceID,
                sessionID: try HanlinAppSessionID(validating: session.id.uuidString.lowercased())
            )

            let result = try await AgentHostServicesAdapter.executeRuntime(
                runtimeKind,
                source: scriptContent,
                arguments: argv,
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
