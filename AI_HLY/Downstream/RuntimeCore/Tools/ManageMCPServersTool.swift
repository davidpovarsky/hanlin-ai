import Foundation

@MainActor
struct ManageMCPServersTool: NativeTool {
    let name = "manage_mcp_servers"

    var catalogEntry: NativeToolCatalogEntry {
        .init(
            name: name,
            title: RuntimeL10n.string("Manage MCP Servers"),
            summary: RuntimeL10n.string("Inspect, preview, install, enable, select for chat, start, stop, restart, list tools, invoke tools, and uninstall local MCP servers."),
            categories: ["runtime", "mcp", "system", "packages"],
            keywords: ["mcp", "server", "install", "tools", "modelcontextprotocol", "npm", "שרת", "התקנה"],
            examples: [
                "List installed MCP servers and their status",
                "Preview or install an MCP server package",
                "Enable and start an MCP server for the current chat"
            ],
            systemImage: "server.rack",
            presentationProfile: RuntimeToolSupport.profile(
                name: name,
                image: "server.rack",
                running: "Managing MCP servers...",
                completed: "MCP server operation complete",
                arguments: ["action", "package_spec", "server", "tool_name"]
            )
        )
    }

    func openAIToolSchema() -> [String: Any] {
        NativeToolSchema.function(
            name: name,
            description: RuntimeL10n.string("Inspect and manage local Model Context Protocol (MCP) servers on device. Supports checking runtime status, listing installed servers, previewing npm MCP packages, installing, enabling/disabling globally, selecting/deselecting for the active chat, starting/stopping/restarting server workers, listing exposed MCP tools, calling an MCP tool, and uninstalling servers."),
            parameters: NativeToolSchema.object(
                properties: [
                    "action": NativeToolSchema.string(
                        description: RuntimeL10n.string("Action to perform on MCP servers."),
                        enumValues: [
                            "status",
                            "list",
                            "preview",
                            "install",
                            "enable",
                            "disable",
                            "select_for_chat",
                            "deselect_for_chat",
                            "start",
                            "stop",
                            "restart",
                            "list_tools",
                            "call_tool",
                            "uninstall"
                        ]
                    ),
                    "package_spec": NativeToolSchema.string(
                        description: RuntimeL10n.string("NPM package specification (e.g. '@modelcontextprotocol/server-memory' or 'pkg@1.0.0'), required for 'preview' and 'install'.")
                    ),
                    "server": NativeToolSchema.string(
                        description: RuntimeL10n.string("Server identifier (UUID, slug, display name, or package name) for server-specific actions ('enable', 'disable', 'select_for_chat', 'deselect_for_chat', 'start', 'stop', 'restart', 'list_tools', 'call_tool', 'uninstall').")
                    ),
                    "entry_point": NativeToolSchema.string(
                        description: RuntimeL10n.string("Optional entry point override when installing an MCP package.")
                    ),
                    "tool_name": NativeToolSchema.string(
                        description: RuntimeL10n.string("Tool name (raw or exposed alias) to invoke when action is 'call_tool'.")
                    ),
                    "tool_arguments": NativeToolSchema.string(
                        description: RuntimeL10n.string("JSON object string of arguments for 'call_tool' (default: '{}').")
                    )
                ],
                required: ["action"]
            )
        )
    }

    private static let supportedActions: [String] = [
        "status",
        "list",
        "preview",
        "install",
        "enable",
        "disable",
        "select_for_chat",
        "deselect_for_chat",
        "start",
        "stop",
        "restart",
        "list_tools",
        "call_tool",
        "uninstall"
    ]

    private static func normalizeAction(_ rawAction: String) -> String {
        switch rawAction.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "get_status", "check_status", "info", "inspect":
            return "status"
        case "list_servers", "get_servers", "servers":
            return "list"
        case "preview_package", "inspect_package", "check_package":
            return "preview"
        case "install_package", "install_server", "add", "add_server":
            return "install"
        case "enable_server", "activate":
            return "enable"
        case "disable_server", "deactivate":
            return "disable"
        case "select", "enable_for_chat", "attach_to_chat":
            return "select_for_chat"
        case "deselect", "disable_for_chat", "detach_from_chat":
            return "deselect_for_chat"
        case "start_server", "run":
            return "start"
        case "stop_server":
            return "stop"
        case "restart_server", "reload":
            return "restart"
        case "get_tools", "tools", "discover_tools":
            return "list_tools"
        case "call", "invoke", "invoke_tool", "execute_tool":
            return "call_tool"
        case "remove", "delete", "uninstall_server", "remove_server":
            return "uninstall"
        default:
            return rawAction.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
    }

    private static func knownPackageCompatibilityWarning(for specString: String) -> String? {
        let lower = specString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.contains("transit-allinone-mcp") {
            return "Package '\(specString)' does not exist on the public npm registry (HTTP 404). Do not retry installing it. For transit/routing queries, use built-in map/location tools (`query_location`, `get_route`) or web search (`search_online`)."
        }
        if lower.contains("@modelcontextprotocol/server-sqlite") || lower == "server-sqlite" {
            return "Package '\(specString)' is deprecated/unpublished on npm and uses native SQLite bindings that are unsupported in the embedded iOS Node runtime. Do not retry installing it; use `execute_local_python_code` with Python's built-in `sqlite3` module instead."
        }
        if lower.contains("@modelcontextprotocol/server-git") || lower == "server-git" {
            return "Package '\(specString)' is a Python uvx package, not a pure-JS npm MCP server, and cannot run in the embedded iOS Node host. Do not retry installing it."
        }
        return nil
    }

    func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        do {
            let arguments = try NativeToolJSON.validatedDictionary(
                from: argumentsJSON,
                allowedKeys: [
                    "action",
                    "package_spec", "package", "package_name", "npm_package",
                    "server", "server_id", "server_name", "slug", "name",
                    "entry_point",
                    "tool_name", "tool",
                    "tool_arguments", "arguments", "args"
                ]
            )
            let rawAction = try NativeToolJSON.strictRequiredString(arguments, "action")
            let action = Self.normalizeAction(rawAction)
            let packageSpecString = (
                (try? NativeToolJSON.strictOptionalString(arguments, "package_spec"))
                ?? (try? NativeToolJSON.strictOptionalString(arguments, "package"))
                ?? (try? NativeToolJSON.strictOptionalString(arguments, "package_name"))
                ?? (try? NativeToolJSON.strictOptionalString(arguments, "npm_package"))
            )?.trimmingCharacters(in: .whitespacesAndNewlines)
            let serverQuery = (
                (try? NativeToolJSON.strictOptionalString(arguments, "server"))
                ?? (try? NativeToolJSON.strictOptionalString(arguments, "server_id"))
                ?? (try? NativeToolJSON.strictOptionalString(arguments, "server_name"))
                ?? (try? NativeToolJSON.strictOptionalString(arguments, "slug"))
                ?? (try? NativeToolJSON.strictOptionalString(arguments, "name"))
            )?.trimmingCharacters(in: .whitespacesAndNewlines)
            let entryPointOverride = try NativeToolJSON.strictOptionalString(arguments, "entry_point")?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let toolNameQuery = (
                (try? NativeToolJSON.strictOptionalString(arguments, "tool_name"))
                ?? (try? NativeToolJSON.strictOptionalString(arguments, "tool"))
            )?.trimmingCharacters(in: .whitespacesAndNewlines)
            let toolArgumentsJSON: String = {
                if let str = (try? NativeToolJSON.strictOptionalString(arguments, "tool_arguments"))
                    ?? (try? NativeToolJSON.strictOptionalString(arguments, "arguments"))
                    ?? (try? NativeToolJSON.strictOptionalString(arguments, "args")) {
                    let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? "{}" : trimmed
                }
                if let dictObj = arguments["tool_arguments"] ?? arguments["arguments"] ?? arguments["args"],
                   JSONSerialization.isValidJSONObject(dictObj),
                   let data = try? JSONSerialization.data(withJSONObject: dictObj),
                   let encoded = String(data: data, encoding: .utf8) {
                    return encoded
                }
                return "{}"
            }()

            let provider = MCPRuntimeProvider.shared
            await provider.loadIfNeeded(startHost: false)
            let chatUUID = context.effectiveChatID.flatMap(UUID.init(uuidString:))
            let isTemporary = context.isTemporaryChat

            switch action {
            case "status", "list":
                let summary = await buildStatusSummary(
                    provider: provider,
                    chatUUID: chatUUID,
                    temporary: isTemporary
                )
                return makeSuccess(
                    route: "mcp.\(action)",
                    modelText: summary,
                    userText: RuntimeL10n.string("Inspected MCP runtime and server status."),
                    argumentKeys: Array(arguments.keys)
                )

            case "preview":
                guard let specStr = packageSpecString, !specStr.isEmpty else {
                    return makeFailure(
                        route: "mcp.preview",
                        outcome: .invalidArguments,
                        message: "Missing required parameter 'package_spec' for action 'preview'. Example: {\"action\": \"preview\", \"package_spec\": \"@modelcontextprotocol/server-memory\"}."
                    )
                }
                if let incompatibilityMessage = Self.knownPackageCompatibilityWarning(for: specStr) {
                    return makeFailure(
                        route: "mcp.preview",
                        outcome: .invalidArguments,
                        message: incompatibilityMessage
                    )
                }
                let spec = try MCPPackageSpec(specStr)
                let preview = try await provider.preview(spec: spec)
                let entryPointsText = preview.entryPoints.isEmpty
                    ? "none"
                    : preview.entryPoints.joined(separator: ", ")
                let output = """
                ### MCP Package Preview: \(preview.packageName)@\(preview.version)
                - Description: \(preview.summary ?? "N/A")
                - Node Requirement: \(preview.nodeRequirement ?? "any")
                - Compatibility Verdict: \(preview.compatibility.verdict.rawValue)
                - Entry Points: \(entryPointsText)
                - Dependencies Count: \(preview.dependencyCount)
                """
                return makeSuccess(
                    route: "mcp.preview",
                    modelText: output,
                    userText: "\(preview.packageName)@\(preview.version)",
                    argumentKeys: Array(arguments.keys)
                )

            case "install":
                guard let specStr = packageSpecString, !specStr.isEmpty else {
                    return makeFailure(
                        route: "mcp.install",
                        outcome: .invalidArguments,
                        message: "Missing required parameter 'package_spec' for action 'install'. Example: {\"action\": \"install\", \"package_spec\": \"@modelcontextprotocol/server-memory\"}."
                    )
                }
                if let incompatibilityMessage = Self.knownPackageCompatibilityWarning(for: specStr) {
                    return makeFailure(
                        route: "mcp.install",
                        outcome: .invalidArguments,
                        message: incompatibilityMessage
                    )
                }
                let spec = try MCPPackageSpec(specStr)
                if !provider.configuration.isEnabled {
                    await provider.setEnabled(true)
                }
                await provider.install(spec: spec, entryPointOverride: entryPointOverride)
                switch provider.installState {
                case .completed(let serverID):
                    guard let installed = provider.servers.first(where: { $0.id == serverID }) else {
                        return makeFailure(
                            route: "mcp.install",
                            outcome: .failed,
                            message: provider.lastError ?? "MCP package installation finished but descriptor was not found."
                        )
                    }
                    if let chatUUID {
                        var currentSelection = await provider.selection(chatID: chatUUID, temporary: isTemporary)
                        currentSelection.insert(installed.id)
                        await provider.setSelection(currentSelection, chatID: chatUUID, temporary: isTemporary)
                    }
                    await provider.start(installed)
                    let tools = await provider.tools(for: installed)
                    if let session = context.capabilitySession {
                        await refreshSessionMCPCatalog(
                            session: session,
                            provider: provider,
                            chatUUID: chatUUID,
                            temporary: isTemporary
                        )
                    }
                    let statusState = provider.statuses[installed.id]?.state ?? .stopped
                    let workerRunning = (statusState == .running)
                    let selectedForCurrentChatText = chatUUID != nil ? "true" : "false (no active chat context)"
                    let effectiveForNewChats = installed.isGloballyEnabled && installed.isEnabledForNewChats
                    let toolNames = tools.map { "\($0.exposedName) (raw: \($0.originalName))" }.joined(separator: ", ")
                    let heading = workerRunning
                        ? "### MCP Server Installed & Activated"
                        : "### MCP Server Installed (Worker Not Running)"
                    let startupErrorLine = (!workerRunning && provider.lastError?.isEmpty == false)
                        ? "\n- Startup Error: \(provider.lastError!)"
                        : ""
                    let output = """
                    \(heading)
                    - ID: \(installed.id.uuidString)
                    - Slug: \(installed.slug)
                    - global_mcp_enabled: \(provider.configuration.isEnabled)
                    - server_installed: true (\(installed.packageName)@\(installed.resolvedVersion))
                    - server_enabled: \(installed.isGloballyEnabled)
                    - selected_for_current_chat: \(selectedForCurrentChatText)
                    - effective_for_new_chats: \(effectiveForNewChats)
                    - worker_running: \(workerRunning) (`\(statusState.rawValue)`)
                    - Discovered Tools (\(tools.count)): \(toolNames.isEmpty ? "none" : toolNames)\(startupErrorLine)
                    """
                    return makeSuccess(
                        route: "mcp.install",
                        modelText: output,
                        userText: workerRunning
                            ? "Installed MCP server \(installed.displayName) (\(tools.count) tools)."
                            : "Installed MCP server \(installed.displayName) (worker state: \(statusState.rawValue)).",
                        argumentKeys: Array(arguments.keys)
                    )

                case .failed(_, let message, let rollback):
                    let fullError = [message, rollback].compactMap { $0 }.joined(separator: " | ")
                    return makeFailure(
                        route: "mcp.install",
                        outcome: .failed,
                        message: "MCP installation failed: \(fullError)"
                    )

                default:
                    return makeFailure(
                        route: "mcp.install",
                        outcome: .failed,
                        message: provider.lastError ?? "MCP installation did not complete (state: \(provider.installState))."
                    )
                }

            case "enable", "disable":
                let targetEnable = (action == "enable")
                if serverQuery == nil || serverQuery?.isEmpty == true || serverQuery?.lowercased() == "global" {
                    await provider.setEnabled(targetEnable)
                    if let session = context.capabilitySession {
                        await refreshSessionMCPCatalog(
                            session: session,
                            provider: provider,
                            chatUUID: chatUUID,
                            temporary: isTemporary
                        )
                    }
                    let summary = await buildStatusSummary(
                        provider: provider,
                        chatUUID: chatUUID,
                        temporary: isTemporary
                    )
                    return makeSuccess(
                        route: "mcp.\(action)",
                        modelText: "MCP global feature set to \(targetEnable).\n\n\(summary)",
                        userText: "MCP global state: \(targetEnable ? "enabled" : "disabled").",
                        argumentKeys: Array(arguments.keys)
                    )
                }
                guard var target = resolveServer(query: serverQuery, in: provider.servers) else {
                    return serverNotFoundFailure(query: serverQuery, route: "mcp.\(action)", servers: provider.servers)
                }
                if targetEnable && !provider.configuration.isEnabled {
                    await provider.setEnabled(true)
                }
                target.isGloballyEnabled = targetEnable
                target.isEnabledForNewChats = targetEnable
                target.updatedAt = .now
                await provider.update(target)
                if targetEnable {
                    await provider.start(target)
                } else {
                    await provider.stop(target)
                }
                if let session = context.capabilitySession {
                    await refreshSessionMCPCatalog(
                        session: session,
                        provider: provider,
                        chatUUID: chatUUID,
                        temporary: isTemporary,
                        allowAutoStart: targetEnable
                    )
                }
                let summary = await buildStatusSummary(
                    provider: provider,
                    chatUUID: chatUUID,
                    temporary: isTemporary
                )
                return makeSuccess(
                    route: "mcp.\(action)",
                    modelText: "Server '\(target.slug)' isGloballyEnabled=\(targetEnable).\n\n\(summary)",
                    userText: "Server '\(target.displayName)' \(targetEnable ? "enabled" : "disabled").",
                    argumentKeys: Array(arguments.keys)
                )

            case "select_for_chat", "deselect_for_chat":
                guard let target = resolveServer(query: serverQuery, in: provider.servers) else {
                    return serverNotFoundFailure(query: serverQuery, route: "mcp.\(action)", servers: provider.servers)
                }
                let select = (action == "select_for_chat")
                if let chatUUID {
                    var selectedIDs = await provider.selection(chatID: chatUUID, temporary: isTemporary)
                    if select {
                        selectedIDs.insert(target.id)
                    } else {
                        selectedIDs.remove(target.id)
                    }
                    await provider.setSelection(selectedIDs, chatID: chatUUID, temporary: isTemporary)
                }
                if select {
                    if !provider.configuration.isEnabled {
                        await provider.setEnabled(true)
                    }
                    await provider.start(target)
                }
                if let session = context.capabilitySession {
                    await refreshSessionMCPCatalog(
                        session: session,
                        provider: provider,
                        chatUUID: chatUUID,
                        temporary: isTemporary,
                        allowAutoStart: select
                    )
                }
                let summary = await buildStatusSummary(
                    provider: provider,
                    chatUUID: chatUUID,
                    temporary: isTemporary
                )
                let chatSelectionNote = chatUUID != nil
                    ? "Server '\(target.slug)' selected_for_current_chat=\(select)."
                    : "No active chat context (`chatID` is nil); per-chat selection was not modified."
                return makeSuccess(
                    route: "mcp.\(action)",
                    modelText: "\(chatSelectionNote)\n\n\(summary)",
                    userText: "Updated chat selection for MCP server '\(target.displayName)'.",
                    argumentKeys: Array(arguments.keys)
                )

            case "start", "stop", "restart":
                guard let target = resolveServer(query: serverQuery, in: provider.servers) else {
                    return serverNotFoundFailure(query: serverQuery, route: "mcp.\(action)", servers: provider.servers)
                }
                if action == "start" {
                    if !provider.configuration.isEnabled {
                        await provider.setEnabled(true)
                    }
                    await provider.start(target)
                } else if action == "stop" {
                    await provider.stop(target)
                } else {
                    await provider.restart(target)
                }
                let tools = (action == "stop") ? [] : await provider.tools(for: target)
                if let session = context.capabilitySession {
                    await refreshSessionMCPCatalog(
                        session: session,
                        provider: provider,
                        chatUUID: chatUUID,
                        temporary: isTemporary,
                        allowAutoStart: action != "stop"
                    )
                }
                let state = provider.statuses[target.id]?.state.rawValue ?? "stopped"
                let workerRunning = provider.statuses[target.id]?.state == .running
                let errorNote = provider.lastError.map { "\n- Error: \($0)" } ?? ""
                let output = """
                ### MCP Server \(action.capitalized): \(target.displayName) (\(target.slug))
                - Runtime State: \(state)
                - worker_running: \(workerRunning)
                - Discovered Tools (\(tools.count)): \(tools.map(\.exposedName).joined(separator: ", "))\(errorNote)
                """
                return makeSuccess(
                    route: "mcp.\(action)",
                    modelText: output,
                    userText: "MCP server '\(target.displayName)' state: \(state).",
                    argumentKeys: Array(arguments.keys)
                )

            case "list_tools":
                guard let target = resolveServer(query: serverQuery, in: provider.servers) else {
                    return serverNotFoundFailure(query: serverQuery, route: "mcp.list_tools", servers: provider.servers)
                }
                if provider.statuses[target.id]?.state != .running, provider.configuration.isEnabled, target.isGloballyEnabled {
                    await provider.start(target)
                }
                let tools = await provider.tools(for: target)
                if let session = context.capabilitySession {
                    await refreshSessionMCPCatalog(
                        session: session,
                        provider: provider,
                        chatUUID: chatUUID,
                        temporary: isTemporary,
                        allowAutoStart: true
                    )
                }
                var lines: [String] = [
                    "### Tools for MCP Server '\(target.displayName)' (`\(target.slug)`)",
                    "- Server ID: \(target.id.uuidString)",
                    "- Runtime State: \(provider.statuses[target.id]?.state.rawValue ?? "stopped")",
                    "- Tool Count: \(tools.count)"
                ]
                for tool in tools {
                    let desc = (tool.summary ?? tool.title)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "No description"
                    lines.append("  - `\(tool.exposedName)` (raw: `\(tool.originalName)`): \(desc)")
                }
                return makeSuccess(
                    route: "mcp.list_tools",
                    modelText: lines.joined(separator: "\n"),
                    userText: "Listed \(tools.count) tools for MCP server '\(target.displayName)'.",
                    argumentKeys: Array(arguments.keys)
                )

            case "call_tool":
                guard let target = resolveServer(query: serverQuery, in: provider.servers) else {
                    return serverNotFoundFailure(query: serverQuery, route: "mcp.call_tool", servers: provider.servers)
                }
                guard let rawQuery = toolNameQuery, !rawQuery.isEmpty else {
                    return makeFailure(
                        route: "mcp.call_tool",
                        outcome: .invalidArguments,
                        message: "Missing required parameter 'tool_name' for action 'call_tool'."
                    )
                }
                let tools = await provider.tools(for: target)
                let resolvedOriginalName: String
                if let match = tools.first(where: {
                    $0.originalName.caseInsensitiveCompare(rawQuery) == .orderedSame
                        || $0.exposedName.caseInsensitiveCompare(rawQuery) == .orderedSame
                }) {
                    resolvedOriginalName = match.originalName
                } else {
                    resolvedOriginalName = rawQuery
                }
                let callResult = await MCPToolBridge.execute(
                    serverID: target.id,
                    toolName: resolvedOriginalName,
                    resultTitle: "\(target.displayName) · \(resolvedOriginalName)",
                    argumentsJSON: toolArgumentsJSON
                )
                if !callResult.outcome.isSuccess {
                    return makeFailure(
                        route: "mcp.call_tool.\(target.slug).\(resolvedOriginalName)",
                        outcome: callResult.outcome,
                        message: callResult.modelText
                    )
                }
                return makeSuccess(
                    route: "mcp.call_tool.\(target.slug).\(resolvedOriginalName)",
                    modelText: callResult.modelText,
                    userText: callResult.userText ?? callResult.modelText,
                    argumentKeys: Array(arguments.keys)
                )

            case "uninstall":
                guard let target = resolveServer(query: serverQuery, in: provider.servers) else {
                    return serverNotFoundFailure(query: serverQuery, route: "mcp.uninstall", servers: provider.servers)
                }
                let removedName = target.displayName
                let removedSlug = target.slug
                await provider.uninstall(target)
                if let session = context.capabilitySession {
                    await refreshSessionMCPCatalog(
                        session: session,
                        provider: provider,
                        chatUUID: chatUUID,
                        temporary: isTemporary,
                        allowAutoStart: false
                    )
                }
                let remainingInstalled = !provider.servers.isEmpty
                return makeSuccess(
                    route: "mcp.uninstall",
                    modelText: "Uninstalled MCP server '\(removedName)' (`\(removedSlug)`). server_installed: \(remainingInstalled). Remaining installed servers: \(provider.servers.count).",
                    userText: "Uninstalled MCP server '\(removedName)'.",
                    argumentKeys: Array(arguments.keys)
                )

            default:
                let validList = Self.supportedActions.joined(separator: ", ")
                return makeFailure(
                    route: "mcp.unknown",
                    outcome: .invalidArguments,
                    message: "Unsupported action '\(rawAction)'. Valid 'action' values are: [\(validList)]."
                )
            }
        } catch {
            return makeFailure(
                route: "mcp.error",
                outcome: .failed,
                message: error.localizedDescription
            )
        }
    }

    private func makeSuccess(
        route: String,
        modelText: String,
        userText: String,
        argumentKeys: [String]
    ) -> NativeToolResult {
        var diag = NativeToolExecutionDiagnostics()
        diag.canonicalLogicalToolID = name
        diag.modelFacingAlias = name
        diag.backendRoute = route
        diag.source = "runtime.mcp"
        diag.runtimeKind = "node"
        diag.argumentKeys = argumentKeys
        return NativeToolResult(
            modelText: modelText,
            userText: userText,
            outcome: .succeeded,
            diagnostics: diag
        )
    }

    private func makeFailure(
        route: String,
        outcome: NativeToolExecutionOutcome,
        message: String
    ) -> NativeToolResult {
        var diag = NativeToolExecutionDiagnostics()
        diag.canonicalLogicalToolID = name
        diag.modelFacingAlias = name
        diag.backendRoute = route
        diag.source = "runtime.mcp"
        diag.runtimeKind = "node"
        diag.failureCategory = outcome.rawValue
        return NativeToolResult(
            modelText: message,
            userText: message,
            outcome: outcome,
            diagnostics: diag
        )
    }

    private func resolveServer(query: String?, in servers: [MCPServerDescriptor]) -> MCPServerDescriptor? {
        guard let raw = query?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return servers.count == 1 ? servers.first : nil
        }
        let lower = raw.lowercased()
        return servers.first { server in
            server.id.uuidString.lowercased() == lower
                || server.slug.lowercased() == lower
                || server.displayName.lowercased() == lower
                || server.packageName.lowercased() == lower
                || server.packageName.lowercased().hasSuffix("/\(lower)")
        }
    }

    private func serverNotFoundFailure(
        query: String?,
        route: String,
        servers: [MCPServerDescriptor]
    ) -> NativeToolResult {
        let available = servers.isEmpty
            ? "none installed"
            : servers.map { "\($0.slug) (\($0.packageName))" }.joined(separator: ", ")
        return makeFailure(
            route: route,
            outcome: .invalidArguments,
            message: "MCP server '\(query ?? "")' was not found. Installed servers: \(available)."
        )
    }

    private func buildStatusSummary(
        provider: MCPRuntimeProvider,
        chatUUID: UUID?,
        temporary: Bool
    ) async -> String {
        let selectedIDs: Set<UUID>
        if let chatUUID {
            selectedIDs = await provider.selection(chatID: chatUUID, temporary: temporary)
        } else {
            selectedIDs = []
        }
        let effectiveNewChatIDs = Set(
            provider.servers.filter { $0.isGloballyEnabled && $0.isEnabledForNewChats }.map(\.id)
        )

        let anyServerInstalled = !provider.servers.isEmpty
        let anyServerEnabled = provider.servers.contains(where: \.isGloballyEnabled)
        let anySelectedForChat = !selectedIDs.isEmpty
        let anyWorkerRunning = provider.runtimeSnapshot.activeWorkerCount > 0
        let selectedForCurrentChatSummary = chatUUID != nil
            ? "\(anySelectedForChat) (\(selectedIDs.count))"
            : "false (no active chat context)"

        var lines: [String] = [
            "### MCP Runtime & Server Status",
            "- global_mcp_enabled: \(provider.configuration.isEnabled)",
            "- Node Host State: \(provider.runtimeSnapshot.state.rawValue)",
            "- worker_running: \(anyWorkerRunning) (\(provider.runtimeSnapshot.activeWorkerCount))",
            "- server_installed: \(anyServerInstalled) (\(provider.servers.count))",
            "- server_enabled: \(anyServerEnabled)",
            "- selected_for_current_chat: \(selectedForCurrentChatSummary)",
            "- effective_for_new_chats: \(!effectiveNewChatIDs.isEmpty) (\(effectiveNewChatIDs.count))"
        ]
        if let lastError = provider.lastError, !lastError.isEmpty {
            lines.append("- Last Error: \(lastError)")
        }
        if provider.servers.isEmpty {
            lines.append("\nNo MCP servers are currently installed. You can preview or install an npm MCP server using `manage_mcp_servers(action: \"install\", package_spec: \"<npm-package>\")`.")
        } else {
            lines.append("\n#### Installed Servers:")
            for server in provider.servers {
                let status = provider.statuses[server.id]
                let runtimeState = status?.state.rawValue ?? "stopped"
                let isWorkerRunning = status?.state == .running
                let toolCount = status?.toolCount ?? 0
                let isSelectedText = chatUUID != nil
                    ? "\(selectedIDs.contains(server.id))"
                    : "false (no active chat context)"
                let isEffectiveForNewChats = server.isGloballyEnabled && server.isEnabledForNewChats
                lines.append("""
                - **\(server.displayName)** (slug: `\(server.slug)`, id: `\(server.id.uuidString)`)
                  - Package: `\(server.packageName)@\(server.resolvedVersion)`
                  - server_installed: true | server_enabled: \(server.isGloballyEnabled) | selected_for_current_chat: \(isSelectedText) | effective_for_new_chats: \(isEffectiveForNewChats) | worker_running: \(isWorkerRunning) (`\(runtimeState)`) | Cached Tools: \(toolCount)
                """)
            }
        }
        return lines.joined(separator: "\n")
    }

    private func refreshSessionMCPCatalog(
        session: AssistantCapabilitySession,
        provider: MCPRuntimeProvider,
        chatUUID: UUID?,
        temporary: Bool,
        allowAutoStart: Bool = true
    ) async {
        var scope = await provider.requestScope(chatID: chatUUID, temporary: temporary)
        if !allowAutoStart {
            let runningIDs = Set(provider.servers.filter { provider.statuses[$0.id]?.state == .running }.map(\.id))
            scope = AssistantToolRequestScope(
                chatID: scope.chatID,
                mcpServerIDs: scope.mcpServerIDs.intersection(runningIDs),
                mcpGloballyEnabled: scope.mcpGloballyEnabled,
                isTemporaryChat: scope.isTemporaryChat
            )
        }
        let descriptors = await MCPToolBridge.resolveDescriptors(scope: scope)
        session.syncMCPTools(activeMCPAliases: descriptors.map(\.exposedName))
        if allowAutoStart {
            await session.refreshDynamicTools()
        }
    }
}
