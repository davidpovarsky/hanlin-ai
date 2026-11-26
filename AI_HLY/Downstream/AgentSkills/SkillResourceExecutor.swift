import Foundation
import HanlinPlatformContracts

/// The original loaded-Skill executor, shared by the original native tool,
/// Skill Center and embedding SDK. Runtime05 plans, approval, source checks,
/// cancellation journals and the same runtime broker remain authoritative.
@MainActor
struct SkillResourceExecutor {
    private let catalog: HanlinSkillCatalog?
    private let store: SkillStore?

    init(catalog: HanlinSkillCatalog? = nil, store: SkillStore? = nil) {
        self.catalog = catalog
        self.store = store
    }

    func execute(argumentsJSON: String, session: AssistantCapabilitySession?) async -> NativeToolResult {
        var receiptContext: (SkillRuntimeContract.ExecutionPlan, HanlinSkillID, String, RuntimeKind)?
        var observedJob: RuntimeJobSnapshot?
        do {
            let arguments = try NativeToolJSON.validatedDictionary(
                from: argumentsJSON,
                allowedKeys: ["skill_id", "relative_path", "arguments", "timeout_seconds", "engine"]
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
            guard let session else {
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

            guard (store ?? SkillStore.shared).isSkillEnabled(id: skillID) else {
                return RuntimeToolSupport.failure(
                    HanlinHostServiceError.invalidRequest("Skill '\(skillIDRaw)' is currently disabled."),
                    title: "Skill Disabled"
                )
            }

            guard SkillRuntimeAuthorization.approved else {
                throw HanlinHostServiceError.capabilityNotGranted("Skill execution requires one-use user approval in the active chat or Skill Center.")
            }

            guard try await (catalog ?? .shared).permitsInvocation(skillID,
                source: SkillRuntimeAuthorization.invocationSource, store: store ?? .shared) else {
                throw HanlinHostServiceError.invalidRequest("This Skill is not available for the current invocation source or environment.")
            }
            try Task.checkCancellation()

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

            // Resource language selects a route, never readiness. An explicit selection is
            // checked for compatibility and then verified against the live original engine.
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
            case "sh", "bash":
                runtimeKind = .shell
                requiredCapability = "runtime.shell"
            default:
                return RuntimeToolSupport.failure(
                    HanlinHostServiceError.invalidRequest("Unsupported script file extension '.\(ext)'. Supported resources are .py, .js, .mjs, .ts, .sh and .bash."),
                    title: "Unsupported Runtime"
                )
            }

            let selectedKind: RuntimeKind
            if let explicit = arguments["engine"] as? String {
                guard let value = RuntimeKind(rawValue: explicit),
                      value == runtimeKind || (runtimeKind == .node && value == .javaScriptCore && ext == "js") else {
                    throw HanlinHostServiceError.invalidRequest("The selected engine cannot run this resource language.")
                }
                selectedKind = value
            } else { selectedKind = runtimeKind }
            _ = try await AppRuntimeCore.shared.ensureStarted(selectedKind)
            if selectedKind == .shell { _ = try await AppRuntimeCore.shared.ensureStarted(.node) }
            try Task.checkCancellation()
            try await SkillRuntimeService.shared.analyze(skillID: skillID, path: cleanPath, catalog: catalog ?? .shared, store: store ?? .shared)
            let plan = try await SkillRuntimeService.shared.plan(skillID: skillID, path: cleanPath,
                engine: SkillRuntimeRequirements.engine(selectedKind), arguments: argv,
                catalog: catalog ?? .shared, store: store ?? .shared, forExecution: true)
            guard plan.isExecutable else {
                let reasons = plan.issues.map { $0.code.rawValue }.joined(separator: ", ")
                throw HanlinHostServiceError.invalidRequest("Skill requirements are not verified for this engine (\(plan.readiness.rawValue): \(reasons)). Recheck compatibility in Skill Center.")
            }
            guard plan.action.actionFingerprint == SkillRuntimeRequirements.digest(Data(scriptContent.utf8)),
                  (catalog ?? .shared).resolveResourceURL(skillID: skillID, relativePath: cleanPath) == resourceURL,
                  SkillRuntimeRequirements.digest(try Data(contentsOf: resourceURL)) == plan.action.actionFingerprint,
                  try await SkillRuntimeService.shared.sourceFingerprint(skillID: skillID, catalog: catalog ?? .shared, store: store ?? .shared) == plan.action.sourceFingerprint,
                  (store ?? .shared).isSkillEnabled(id: skillID), session.isSkillLoaded(skillID) else {
                throw HanlinHostServiceError.invalidRequest("Skill source or session changed after compatibility evaluation. Reopen and review the current resource.")
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
                capabilities: [selectedKind == .javaScriptCore ? "runtime.javascript" : requiredCapability, "files"],
                workspaceIdentifier: workspaceID,
                sessionID: try HanlinAppSessionID(validating: session.id.uuidString.lowercased())
            )

            receiptContext = (plan, skillID, cleanPath, selectedKind)
            try Task.checkCancellation()
            let priorReporter = RuntimeJobProgress.reporter
            let result = try await RuntimeJobProgress.$reporter.withValue({ job in
                observedJob = job
                await priorReporter?(job)
            }) {
                try await AgentHostServicesAdapter.executeRuntime(
                selectedKind,
                source: scriptContent,
                arguments: argv,
                environment: scriptEnv,
                limits: executionLimits,
                context: skillCallContext
                )
            }

            try SkillRuntimeService.shared.record(result, plan: plan, skillID: skillID, path: cleanPath, store: store ?? .shared)

            return RuntimeToolSupport.result(
                result,
                title: "Skill Resource: \(components.last ?? "")",
                systemImage: "terminal",
                runtimeKind: selectedKind,
                argumentKeys: Array(arguments.keys),
                jobRuntime: selectedKind == .shell ? .node : nil
            )
        } catch {
            // Observation cancellation never replays source. Preserve an actual settled Node
            // cancellation receipt from the existing journal, including partial output.
            if let (plan, id, path, kind) = receiptContext, [.node, .typeScript, .shell].contains(kind), let observedJob,
               error is CancellationError || Task.isCancelled {
                let result = await Task<RuntimeExecutionResult?, Never> { @MainActor in
                    await AppRuntimeCore.shared.node.cancelExecution(id: observedJob.executionID)
                    // Cancellation acknowledgement can precede the terminal journal write.
                    // Observe only this exact existing job; never replay source or invent output.
                    for _ in 0..<30 {
                        if let snapshot = try? await AppRuntimeCore.shared.node.existingExecution(id: observedJob.executionID),
                           snapshot.state.isTerminal, let result = snapshot.result { return result }
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                    return nil
                }.value
                if let result {
                    try? SkillRuntimeService.shared.record(result, plan: plan, skillID: id, path: path, store: store ?? .shared)
                }
            }
            return RuntimeToolSupport.failure(error, title: "Skill resource execution failed")
        }
    }
}
