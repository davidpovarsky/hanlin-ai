import Foundation

@MainActor
struct ListToolsTool: NativeTool {
    let name = "list_tools"

    var catalogEntry: NativeToolCatalogEntry {
        .init(
            name: name,
            title: RuntimeL10n.string("List Registered Tools"),
            summary: RuntimeL10n.string("List all registered tools across native apps, runtime engines, and MCP servers with pagination and availability metadata."),
            categories: ["runtime", "system", "discovery"],
            keywords: ["tools", "list", "discovery", "catalog", "כלים", "רשימה"],
            examples: ["List registered tools", "הצג את כל הכלים הרשומים"],
            systemImage: "list.bullet.rectangle",
            presentationProfile: RuntimeToolSupport.profile(
                name: name,
                image: "list.bullet.rectangle",
                running: "Listing tools...",
                completed: "Tool listing ready",
                arguments: ["offset", "limit", "include_disabled"]
            )
        )
    }

    func openAIToolSchema() -> [String: Any] {
        NativeToolSchema.function(
            name: name,
            description: RuntimeL10n.string("Enumerate registered tools in the application catalog with pagination, showing logical IDs, provider identities, enabled/disabled state, and unavailable reasons without executing them."),
            parameters: NativeToolSchema.object(
                properties: [
                    "offset": NativeToolSchema.integer(description: RuntimeL10n.string("0-based offset for pagination (default: 0)."), minimum: 0),
                    "limit": NativeToolSchema.integer(description: RuntimeL10n.string("Maximum number of tools to return in this page (default: 20, max: 100)."), minimum: 1, maximum: 100),
                    "include_disabled": [
                        "type": "boolean",
                        "description": RuntimeL10n.string("Whether to include disabled tools in the listing (default: true).")
                    ]
                ],
                required: []
            )
        )
    }

    func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        do {
            let arguments = try? NativeToolJSON.validatedDictionary(
                from: argumentsJSON,
                allowedKeys: ["offset", "limit", "include_disabled"]
            )
            let offset = (try? NativeToolJSON.strictOptionalInt(arguments ?? [:], "offset")) ?? 0
            let limit = min(max((try? NativeToolJSON.strictOptionalInt(arguments ?? [:], "limit")) ?? 20, 1), 100)
            let includeDisabled = (try? NativeToolJSON.strictOptionalBool(arguments ?? [:], "include_disabled")) ?? true

            NativeToolCatalog.shared.ensureBuiltinsRegistered()
            var allEntries = NativeToolCatalog.shared.allEntries()

            let provider = MCPRuntimeProvider.shared
            await provider.loadIfNeeded(startHost: false)
            let chatUUID = context.effectiveChatID.flatMap(UUID.init(uuidString:))
            let scope = await provider.requestScope(chatID: chatUUID, temporary: context.isTemporaryChat)
            let mcpDescriptors = await MCPToolBridge.resolveDescriptors(scope: scope)
            for descriptor in mcpDescriptors where !allEntries.contains(where: { $0.name == descriptor.exposedName }) {
                allEntries.append(
                    NativeToolCatalogEntry(
                        name: descriptor.exposedName,
                        title: descriptor.originalName,
                        summary: descriptor.description,
                        categories: ["mcp"],
                        keywords: ["mcp", descriptor.serverSlug, descriptor.originalName],
                        examples: [],
                        systemImage: "server.rack",
                        sourceAppID: "mcp.\(descriptor.serverSlug)",
                        sourceAppTitle: "MCP (\(descriptor.serverDisplayName))"
                    )
                )
            }
            if let session = context.capabilitySession, !mcpDescriptors.isEmpty {
                session.exposeTools(aliases: mcpDescriptors.map(\.exposedName))
            }

            var metaTools: [NativeToolCatalogEntry] = []
            var nativeTools: [NativeToolCatalogEntry] = []
            var legacyTools: [NativeToolCatalogEntry] = []
            var mcpTools: [NativeToolCatalogEntry] = []
            var scriptTools: [NativeToolCatalogEntry] = []
            var miniAppTools: [NativeToolCatalogEntry] = []

            for entry in allEntries {
                if entry.categories.contains("discovery") || entry.name == "load_skill" || entry.name == "tool_search" || entry.name == "read_tool_result" || entry.name == "read_skill_resource" || entry.name == "list_tools" || entry.name == "get_runtime_capabilities" || entry.name == "manage_runtime_packages" || entry.name == "manage_mcp_servers" {
                    metaTools.append(entry)
                } else if entry.categories.contains("mcp") {
                    mcpTools.append(entry)
                } else if entry.sourceAppID != nil {
                    miniAppTools.append(entry)
                } else if entry.categories.contains("scripting") {
                    scriptTools.append(entry)
                } else if entry.categories.contains("legacy") {
                    legacyTools.append(entry)
                } else {
                    nativeTools.append(entry)
                }
            }

            let filteredEntries = allEntries.filter { entry in
                if !includeDisabled && !entry.categories.contains("mcp") && !NativeToolCatalog.shared.isEffectivelyEnabled(entry) {
                    return false
                }
                return true
            }

            let totalCount = filteredEntries.count
            let start = min(offset, totalCount)
            let end = min(start + limit, totalCount)
            let page = filteredEntries[start..<end]

            var response = "### Tool Catalog Summary\n"
            response += "- Total registered tools: \(allEntries.count)\n"
            response += "- Meta tools: \(metaTools.count)\n"
            response += "- Native app/built-in tools: \(nativeTools.count)\n"
            response += "- MiniApp tools: \(miniAppTools.count)\n"
            response += "- Scripting tools: \(scriptTools.count)\n"
            response += "- MCP tools: \(mcpTools.count)\n"
            response += "- Legacy tools: \(legacyTools.count)\n\n"
            response += "### Tools (showing \(totalCount == 0 ? 0 : start + 1)-\(end) of \(totalCount)):\n"

            for entry in page {
                let enabled = entry.categories.contains("mcp") || NativeToolCatalog.shared.isEffectivelyEnabled(entry)
                let status = enabled ? "enabled" : "disabled"
                let source = entry.sourceAppTitle ?? entry.sourceAppID ?? "Built-in"
                response += "- `\(entry.name)` [\(status)] — \(entry.title): \(entry.summary) (source: \(source))\n"
            }

            if end < totalCount {
                response += "\n*Use offset=\(end) to view the next page of tools.*"
            }

            let executionResult = RuntimeExecutionResult(
                executionID: UUID(),
                stdout: response,
                stderr: "",
                value: nil,
                exitCode: 0,
                durationMilliseconds: 1,
                didTimeOut: false,
                wasCancelled: false,
                outputWasTruncated: false
            )

            return RuntimeToolSupport.result(
                executionResult,
                title: "Tool Listing",
                systemImage: "list.bullet.rectangle",
                runtimeKind: .shell,
                argumentKeys: Array((arguments ?? [:]).keys)
            )
        } catch {
            return RuntimeToolSupport.failure(error, title: "List Tools Failed", runtimeKind: .shell)
        }
    }
}
