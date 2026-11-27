import CryptoKit
import Foundation
import HanlinAgentCore
import HanlinHostContracts
import HanlinPlatformContracts

/// Builds a host grant from the admitted route and manifest, never from a model's
/// "allowed" text or a historic approval event.
@MainActor
enum HanlinToolApprovalScopeFactory {
    private struct ManifestIdentity: Encodable {
        let descriptor: HanlinToolDescriptor
        let originalInputSchema: Data?
        let providerConfigurationFingerprint: String
    }
    private struct PermissionIdentity: Encodable {
        let risk: HanlinRiskLevel
        let capabilities: [HanlinCapabilityID]
        let approval: HanlinToolApprovalDescriptor
        let selectedIdentityFields: [String: String]
    }
    private struct MCPIdentity: Encodable {
        let id: UUID
        let packageName: String
        let resolvedVersion: String
        let integrity: String?
        let entryPoint: String
        let arguments: [String]
        let environment: [MCPEnvironmentVariable]
    }

    #if !HANLIN_ASSISTANT_CAPABILITIES_SDK
    static func scope(for invocation: HanlinHostInvocation, tool: HanlinHostTool,
                      adapter: HanlinAISDKToolAdapter?) throws -> HanlinToolApprovalScope? {
        try scope(for: invocation, tool: tool, source: adapter)
    }
    #endif

    static func scope(for invocation: HanlinHostInvocation, tool: HanlinHostTool,
                      source: (any HanlinOriginalToolSource)?) throws -> HanlinToolApprovalScope? {
        let descriptor = tool.descriptor
        let policy = descriptor.approvalPolicy
        guard policy.requiresConsent(arguments: invocation.request.arguments, risk: descriptor.risk) else { return nil }
        guard let original = invocation.originalArgumentsJSON else { throw HanlinHostError.invalidArguments }
        let identityKeys = policy.scopeParameters + (policy.actionParameter.map { [$0] } ?? [])
        let identityFields = try HanlinHostSchemaValidation.topLevelStringFields(
            argumentsJSON: original, keys: Array(Set(identityKeys)).sorted()
        )
        let manifest = ManifestIdentity(
            descriptor: descriptor,
            originalInputSchema: tool.originalInputSchemaJSON,
            providerConfigurationFingerprint: try providerFingerprint(
                logicalID: descriptor.logicalID, alias: invocation.request.aliasUsed, identityFields: identityFields, source: source
            )
        )
        let permissions = PermissionIdentity(
            risk: descriptor.risk, capabilities: descriptor.capabilities.sorted { $0.rawValue < $1.rawValue },
            approval: policy, selectedIdentityFields: identityFields
        )
        let namespace = invocation.session.context.namespace
        let scope = HanlinToolApprovalScope(
            app: namespace.app, account: namespace.account, workspace: namespace.workspace,
            providerID: descriptor.logicalID.providerInstanceID.rawValue,
            toolID: descriptor.logicalID.localToolID.rawValue,
            manifestFingerprint: try fingerprint(manifest),
            permissionFingerprint: try fingerprint(permissions)
        )
        guard scope.isValid else { throw HanlinHostError.invalidArguments }
        return scope
    }

    private static func providerFingerprint(logicalID: HanlinLogicalToolID, alias: String,
                                            identityFields: [String: String], source: (any HanlinOriginalToolSource)?) throws -> String {
        if let serverID = source?.mcpServerID(for: alias) {
            guard let server = MCPRuntimeProvider.shared.servers.first(where: { $0.id == serverID }) else {
                throw HanlinHostError.staleContext
            }
            return try fingerprint(mcpIdentity(server))
        }
        // The management wrapper can delegate to a different tool/account. Its
        // declared scope also includes server + tool_name; changing any installed
        // credential reference or provider code invalidates its remembered grant.
        if logicalID.localToolID.rawValue == "manage_mcp_servers" {
            return try fingerprint(MCPRuntimeProvider.shared.servers.sorted { $0.id.uuidString < $1.id.uuidString }.map(mcpIdentity))
        }
        if logicalID.localToolID.rawValue == "execute_skill_resource" {
            guard let rawID = identityFields["skill_id"],
                  let skillID = try? HanlinSkillID(validating: rawID),
                  let descriptor = HanlinSkillCatalog.shared.resolve(id: skillID) else {
                throw HanlinHostError.staleContext
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let source = HanlinSkillCatalog.shared.markdownDocument(for: skillID)?.originalSource ?? Data()
            return try fingerprint(["tool": try encoder.encode(logicalID),
                                    "skill": try encoder.encode(descriptor), "manifest": source])
        }
        return try fingerprint(logicalID)
    }

    private static func mcpIdentity(_ server: MCPServerDescriptor) -> MCPIdentity {
        .init(id: server.id, packageName: server.packageName, resolvedVersion: server.resolvedVersion,
              integrity: server.integrity, entryPoint: server.entryPoint, arguments: server.arguments,
              environment: server.environment.sorted { $0.name < $1.name })
    }

    private static func fingerprint<Value: Encodable>(_ value: Value) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let bytes = try HanlinHostSchemaValidation.deterministicJSONData(encoder.encode(value))
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}
