import Foundation
import HanlinPlatformContracts

/// Read-only MCP provider/catalog projection. MCP runtime/controller/catalog
/// actors remain authoritative for discovery, aliases, collisions, and calls.
///
/// Legacy sources: `MCPServerDescriptor`, `MCPToolDescriptor`, and
/// `MCPRuntimeSnapshot`. Canonical targets: provider instances, logical tools,
/// and runtime snapshots. Absolute paths, environment values, cached counts,
/// compatibility cache, and executable sessions are never copied. Invalid local
/// tool IDs or duplicate-key schemas fail. Delete after MCP publishes canonical
/// provider records and descriptors directly.
enum MCPCanonicalShadowAdapter {
    static func projectProvider(_ server: MCPServerDescriptor) throws -> HanlinProviderInstance {
        let instanceID = try HanlinProviderInstanceID(
            validating: server.id.uuidString.lowercased()
        )
        var secretReferences: [String: String] = [:]
        for variable in server.environment {
            guard let reference = variable.secretReference else { continue }
            guard secretReferences.updateValue(reference, forKey: variable.name) == nil else {
                throw HanlinContractError.duplicateObjectKey(
                    key: variable.name,
                    path: "/environment"
                )
            }
        }
        return HanlinProviderInstance(
            id: instanceID,
            providerID: try HanlinProviderID(validating: "mcp"),
            externalReference: server.id.uuidString.lowercased(),
            configuration: .init(
                enabled: server.isGloballyEnabled,
                values: [
                    "autoStart": .bool(server.autoStart),
                    "enabledForNewChats": .bool(server.isEnabledForNewChats),
                    "resolvedVersion": .string(server.resolvedVersion)
                ],
                secretReferences: secretReferences
            )
        )
    }

    static func projectTools(
        _ tools: [MCPToolDescriptor],
        revision: HanlinCatalogRevision,
        descriptorRevision: HanlinDescriptorRevision
    ) throws -> HanlinToolCatalogSnapshot {
        let entries = try tools.sorted { $0.exposedName < $1.exposedName }.map { tool in
            return HanlinToolCatalogEntry(
                descriptor: try projectTool(
                    tool,
                    descriptorRevision: descriptorRevision
                ),
                availability: .available,
                modelAlias: tool.exposedName
            )
        }
        return HanlinToolCatalogSnapshot(
            revision: revision,
            generatedAt: .now,
            entries: entries
        )
    }

    static func projectTool(
        _ tool: MCPToolDescriptor,
        descriptorRevision: HanlinDescriptorRevision
    ) throws -> HanlinToolDescriptor {
        let providerInstanceID = try HanlinProviderInstanceID(
            validating: tool.serverID.uuidString.lowercased()
        )
        let schema = try HanlinJSONSchemaDocument.decodeCanonicalJSON(
            tool.inputSchemaJSON,
            defaultDialect: .draft2020_12
        )
        return HanlinToolDescriptor(
            logicalID: HanlinLogicalToolID(
                providerInstanceID: providerInstanceID,
                localToolID: try HanlinToolID(validating: tool.originalName)
            ),
            descriptorRevision: descriptorRevision,
            owner: .mcpServer(
                try HanlinMCPServerID(validating: tool.serverID.uuidString.lowercased())
            ),
            title: try LocalizedValue(["en": tool.title ?? tool.originalName]),
            summary: try LocalizedValue([
                "en": tool.summary ?? "Tool provided by \(tool.serverDisplayName)"
            ]),
            inputSchema: schema,
            outputSchema: nil,
            risk: .read,
            presentation: .init(compactStyle: .automatic)
        )
    }

    static func projectRuntime(
        _ snapshot: MCPRuntimeSnapshot,
        sessionID: HanlinRuntimeSessionID,
        createdAt: Date,
        observedAt: Date
    ) throws -> HanlinRuntimeSessionDescriptor {
        let state: HanlinRuntimeSessionState = switch snapshot.state {
        case .stopped: .stopped
        case .starting: .preparing
        case .running: .ready
        case .failed: .failed
        }
        return HanlinRuntimeSessionDescriptor(
            id: sessionID,
            providerInstanceID: try HanlinProviderInstanceID(validating: "mcp.host"),
            kind: .mcp,
            runtimeVersion: snapshot.nodeVersion,
            protocolVersion: snapshot.protocolVersion.map {
                .init(major: UInt16(clamping: $0), minor: 0)
            },
            state: state,
            createdAt: createdAt,
            stateChangedAt: observedAt,
            activeExecutionCount: snapshot.activeWorkerCount,
            failureCode: state == .failed ? snapshot.message : nil
        )
    }
}
