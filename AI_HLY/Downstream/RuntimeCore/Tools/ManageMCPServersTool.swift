import Foundation

@MainActor
struct ManageMCPServersTool: NativeTool {
    let name = "manage_mcp_servers"

    var catalogEntry: NativeToolCatalogEntry {
        .init(
            name: name,
            title: RuntimeL10n.string("Manage MCP Servers"),
            summary: RuntimeL10n.string("Inspect, preview, install, enable, select for chat, start, stop, restart, list tools, and uninstall local MCP servers."),
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
                arguments: ["action", "package_spec", "server"]
            )
        )
    }

    func openAIToolSchema() -> [String: Any] {
        NativeToolSchema.function(
            name: name,
            description: RuntimeL10n.string("Inspect and manage local Model Context Protocol (MCP) servers on device. Supports checking runtime status, listing installed servers, previewing npm MCP packages, installing, enabling/disabling globally, selecting/deselecting for the active chat, starting/stopping/restarting server workers, listing exposed MCP tools, and uninstalling servers."),
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
                            "uninstall"
                        ]
                    ),
                    "package_spec": NativeToolSchema.string(
                        description: RuntimeL10n.string("NPM package specification (e.g. '@modelcontextprotocol/server-memory' or 'pkg@1.0.0'), required for 'preview' and 'install'.")
                    ),
                    "server": NativeToolSchema.string(
                        description: RuntimeL10n.string("Server identifier (UUID, slug, display name, or package name) for server-specific actions ('enable', 'disable', 'select_for_chat', 'deselect_for_chat', 'start', 'stop', 'restart', 'list_tools', 'uninstall').")
                    ),
                    "entry_point": NativeToolSchema.string(
                        description: RuntimeL10n.string("Optional entry point override when installing an MCP package.")
                    )
                ],
                required: ["action"]
            )
        )
    }

    func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        do {
            let arguments = try NativeToolJSON.validatedDictionary(
                from: argumentsJSON,
                allowedKeys: ["action", "package_spec", "server", "entry_point"]
            )
            let action = try NativeToolJSON.strictRequiredString(arguments, "action")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let packageSpecString = try NativeToolJSON.strictOptionalString(arguments, "package_spec")?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let serverQuery = try NativeToolJSON.strictOptionalString(arguments, "server")?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let entryPointOverride = try NativeToolJSON.strictOptionalString(arguments, "entry_point")?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let provider = MCPRuntimeProvider.shared
            await provider.loadIfNeeded(startHost: false)
            let chatUUID = context.chatID.flatMap(UUID.init(uuidString:))

            switch action {
            case "status", "list":
                let summary = await buildStatusSummary(provider: provider, chatUUID: chatUUID)
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
                        message: "Missing required parameter 'package_spec' for action 'preview'."
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
                        message: "Missing required parameter 'package_spec' for action 'install'."
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
                        var currentSelection = await provider.selection(chatID: chatUUID, temporary: false)
                        currentSelection.insert(installed.id)
                        await provider.setSelection(currentSelection, chatID: chatUUID, temporary: false)
                    }
                    await provider.start(installed)
                    let tools = await provider.tools(for: installed)
                    if let session = context.capabilitySession {
                        await refreshSessionMCPCatalog(session: session, provider: provider, chatUUID: chatUUID)
                    }
                    let statusState = provider.statuses[installed.id]?.state.rawValue ?? "unknown"
                    let toolNames = tools.map(\.originalName).joined(separator: ", ")
                    let output = """
                    ### MCP Server Installed & Activated
                    - ID: \(installed.id.uuidString)
                    - Slug: \(installed.slug)
                    - Package: \(installed.packageName)@\(installed.resolvedVersion)
                    - Globally Enabled: \(installed.isGloballyEnabled)
                    - Selected for Current Chat: true
                    - Runtime State: \(statusState)
                    - Discovered Tools (\(tools.count)): \(toolNames.isEmpty ? "none" : toolNames)
                    """
                    return makeSuccess(
                        route: "mcp.install",
                        modelText: output,
                        userText: "Installed MCP server \(installed.displayName) (\(tools.count) tools).",
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
                    let summary = await buildStatusSummary(provider: provider, chatUUID: chatUUID)
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
                    await refreshSessionMCPCatalog(session: session, provider: provider, chatUUID: chatUUID)
                }
                let summary = await buildStatusSummary(provider: provider, chatUUID: chatUUID)
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
                    var selectedIDs = await provider.selection(chatID: chatUUID, temporary: false)
                    if select {
                        selectedIDs.insert(target.id)
                    } else {
                        selectedIDs.remove(target.id)
                    }
                    await provider.setSelection(selectedIDs, chatID: chatUUID, temporary: false)
                }
                if select {
                    if !provider.configuration.isEnabled {
                        await provider.setEnabled(true)
                    }
                    await provider.start(target)
                }
                if let session = context.capabilitySession {
                    await refreshSessionMCPCatalog(session: session, provider: provider, chatUUID: chatUUID)
                }
                let summary = await buildStatusSummary(provider: provider, chatUUID: chatUUID)
                return makeSuccess(
                    route: "mcp.\(action)",
                    modelText: "Server '\(target.slug)' selected_for_chat=\(select).\n\n\(summary)",
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
                    await refreshSessionMCPCatalog(session: session, provider: provider, chatUUID: chatUUID)
                }
                let state = provider.statuses[target.id]?.state.rawValue ?? "stopped"
                let errorNote = provider.lastError.map { "\n- Error: \($0)" } ?? ""
                let output = """
                ### MCP Server \(action.capitalized): \(target.displayName) (\(target.slug))
                - Runtime State: \(state)
                - Discovered Tools (\(tools.count)): \(tools.map(\.originalName).joined(separator: ", "))\(errorNote)
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
                    await refreshSessionMCPCatalog(session: session, provider: provider, chatUUID: chatUUID)
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

            case "uninstall":
                guard let target = resolveServer(query: serverQuery, in: provider.servers) else {
                    return serverNotFoundFailure(query: serverQuery, route: "mcp.uninstall", servers: provider.servers)
                }
                let removedName = target.displayName
                let removedSlug = target.slug
                await provider.uninstall(target)
                if let session = context.capabilitySession {
                    await refreshSessionMCPCatalog(session: session, provider: provider, chatUUID: chatUUID)
                }
                return makeSuccess(
                    route: "mcp.uninstall",
                    modelText: "Uninstalled MCP server '\(removedName)' (`\(removedSlug)`). Remaining installed servers: \(provider.servers.count).",
                    userText: "Uninstalled MCP server '\(removedName)'.",
                    argumentKeys: Array(arguments.keys)
                )

            default:
                return makeFailure(
                    route: "mcp.unknown",
                    outcome: .invalidArguments,
                    message: "Unsupported action '\(action)'."
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
        chatUUID: UUID?
    ) async -> String {
        let selectedIDs: Set<UUID>
        if let chatUUID {
            selectedIDs = await provider.selection(chatID: chatUUID, temporary: false)
        } else {
            selectedIDs = Set(provider.servers.filter { $0.isGloballyEnabled && $0.isEnabledForNewChats }.map(\.id))
        }

        let anyServerInstalled = !provider.servers.isEmpty
        let anyServerEnabled = provider.servers.contains(where: \.isGloballyEnabled)
        let anySelectedForChat = !selectedIDs.isEmpty
        let anyWorkerRunning = provider.runtimeSnapshot.activeWorkerCount > 0

        var lines: [String] = [
            "### MCP Runtime & Server Status",
            "- MCP Feature Globally Enabled (`global_mcp_enabled`): \(provider.configuration.isEnabled)",
            "- Node Host State: \(provider.runtimeSnapshot.state.rawValue)",
            "- Active Worker Count (`worker_running`): \(anyWorkerRunning) (\(provider.runtimeSnapshot.activeWorkerCount))",
            "- Installed Servers Count (`server_installed`): \(anyServerInstalled) (\(provider.servers.count))",
            "- Enabled Servers (`server_enabled`): \(anyServerEnabled)",
            "- Selected for Current Chat (`selected_for_current_chat`): \(anySelectedForChat) (\(selectedIDs.count))"
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
                let isSelected = selectedIDs.contains(server.id)
                lines.append("""
                - **\(server.displayName)** (slug: `\(server.slug)`, id: `\(server.id.uuidString)`)
                  - Package: `\(server.packageName)@\(server.resolvedVersion)`
                  - `server_installed`: true | `server_enabled`: \(server.isGloballyEnabled) | `selected_for_current_chat`: \(isSelected) | `worker_running`: \(isWorkerRunning) (`\(runtimeState)`) | Cached Tools: \(toolCount)
                """)
            }
        }
        return lines.joined(separator: "\n")
    }

    private func refreshSessionMCPCatalog(
        session: AssistantCapabilitySession,
        provider: MCPRuntimeProvider,
        chatUUID: UUID?
    ) async {
        let scope = await provider.requestScope(chatID: chatUUID, temporary: false)
        _ = await MCPToolBridge.resolveDescriptors(scope: scope)
    }
}
