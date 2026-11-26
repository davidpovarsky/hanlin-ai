import CryptoKit
import Foundation
import HanlinPlatformContracts
import HanlinScriptContracts

/// A request-scoped identity. Updating, replacing or disabling an installation
/// invalidates a previously selected tool without registering a legacy runtime.
public struct HanlinPreparedAssistantTool: Hashable, Sendable {
    public let installedPackageID: HanlinInstalledPackageID
    public let packageID: HanlinPackageID
    public let generation: UInt64
    public let sourceDigest: String
    public let artifactDigest: String
    public let entrypoint: HanlinPackageEntrypointDescriptor
    public let actionID: HanlinActionID
    public let providerInstanceID: HanlinProviderInstanceID
    public let tool: HanlinScriptExportedTool

    fileprivate init(package: HanlinStoredPackageSnapshot,
                     entrypoint: HanlinPackageEntrypointDescriptor,
                     declaration: HanlinPreparedAssistantToolDeclaration) throws {
        installedPackageID = package.record.installedPackageID
        packageID = package.record.packageID
        generation = package.record.activeGeneration
        sourceDigest = package.record.sourceDigest
        artifactDigest = package.record.artifactDigest
        self.entrypoint = entrypoint
        actionID = declaration.action.id
        let identity = try JSONEncoder().encode([
            installedPackageID.rawValue, packageID.rawValue, String(generation),
            entrypoint.id, entrypoint.sourcePath, actionID.rawValue, sourceDigest, artifactDigest
        ])
        let digest = SHA256.hash(data: identity).map { String(format: "%02x", $0) }.joined()
        providerInstanceID = try HanlinProviderInstanceID(validating: "prepared-miniapp." + digest)
        // Canonical tool IDs are lowercase. The separate actionID retains the
        // exact JavaScript spelling; provider identity prevents case collisions.
        tool = HanlinScriptExportedTool(
            id: try HanlinToolID(validating: actionID.rawValue.lowercased()),
            title: declaration.action.title, summary: declaration.summary,
            inputSchema: declaration.action.inputSchema, outputSchema: declaration.action.outputSchema,
            requiredCapabilities: declaration.action.capabilities, risk: declaration.action.risk)
    }
}

extension HanlinStoredPackageSnapshot {
    public func preparedAssistantTools() throws -> [HanlinPreparedAssistantTool] {
        guard enabled else { return [] }
        let entries = entrypoints.filter {
            $0.kind == .assistantTool && $0.runtimePolicyID == "prepared-foreground-action-v1" &&
                [.hanlinExpo, .hanlinNativeScript].contains($0.runtimeProfile)
        }
        guard !entries.isEmpty else { return [] }
        guard let manifest else { throw HanlinPreparedAssistantToolError.invalidDeclaration }
        return try entries.map { entrypoint in
            let declaration = try HanlinPreparedAssistantToolDeclaration(
                manifest: manifest, entrypoint: entrypoint, entrypoints: entrypoints)
            return try HanlinPreparedAssistantTool(package: self, entrypoint: entrypoint, declaration: declaration)
        }
    }
}
