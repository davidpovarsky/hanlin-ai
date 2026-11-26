import CryptoKit
import Foundation
import HanlinPlatformContracts
import HanlinScriptContracts
import HanlinScriptStore

@MainActor
enum HanlinScriptCanonicalAdapter {
    static func project(
        _ snapshots: [HanlinScriptProviderSnapshot]
    ) throws -> [HanlinCanonicalToolAuthority.ScriptSource] {
        try snapshots.map { snapshot in
            let descriptor = HanlinToolDescriptor(
                logicalID: HanlinLogicalToolID(
                    providerInstanceID: snapshot.providerInstanceID,
                    localToolID: snapshot.tool.id
                ),
                descriptorRevision: snapshot.descriptorRevision,
                owner: .package(snapshot.packageID),
                title: snapshot.tool.title,
                summary: snapshot.tool.summary,
                inputSchema: snapshot.tool.inputSchema,
                outputSchema: snapshot.tool.outputSchema,
                capabilities: snapshot.tool.requiredCapabilities,
                risk: snapshot.tool.risk,
                presentation: .init(compactStyle: .automatic,
                    executionPresentation: snapshot.tool.executionPresentation),
                approval: .init(requiresApproval: snapshot.tool.requiresApproval)
            )
            let parametersData = try snapshot.tool.inputSchema.canonicalJSONData()
            guard let parameters = try JSONSerialization.jsonObject(
                with: parametersData
            ) as? [String: Any] else {
                throw HanlinScriptingError.invalidPackage("input_schema_projection")
            }
            let alias = preferredAlias(
                packageID: snapshot.packageID,
                localToolID: snapshot.tool.id,
                providerInstanceID: snapshot.providerInstanceID
            )
            let summary = snapshot.tool.summary.values[
                snapshot.tool.summary.fallbackLocale
            ] ?? snapshot.tool.id.rawValue
            return HanlinCanonicalToolAuthority.ScriptSource(
                descriptor: descriptor,
                preferredAlias: alias,
                modelSchema: [
                    "type": "function",
                    "function": [
                        "name": alias,
                        "description": summary,
                        "parameters": parameters
                    ]
                ],
                backendRoute: snapshot.route,
                presentationProfile: .generic(toolName: snapshot.tool.id.rawValue),
                resultTitle: snapshot.tool.title.values[
                    snapshot.tool.title.fallbackLocale
                ]
            )
        }
    }

    private static func preferredAlias(
        packageID: HanlinPackageID,
        localToolID: HanlinToolID,
        providerInstanceID: HanlinProviderInstanceID
    ) -> String {
        let base = "script__\(slug(packageID.rawValue))__\(slug(localToolID.rawValue))"
        guard base.count > 64 else { return base }
        let digest = SHA256.hash(data: Data(
            "\(providerInstanceID.rawValue)|\(localToolID.rawValue)".utf8
        )).prefix(4).map { String(format: "%02x", $0) }.joined()
        return "\(base.prefix(55))_\(digest)"
    }

    private static func slug(_ value: String) -> String {
        var result = value.lowercased().unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar)
                ? Character(String(scalar))
                : "_"
        }.reduce(into: "") { $0.append($1) }
        result = result.replacingOccurrences(
            of: "_+",
            with: "_",
            options: .regularExpression
        ).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return result.isEmpty ? "tool" : result
    }
}

/// A snapshot belongs to one assistant request. Execution re-resolves the live
/// installation before the native broker runs the original prepared handler.
@MainActor
struct HanlinPreparedAssistantToolAdapter {
    typealias SnapshotProvider = @MainActor () async throws -> [HanlinStoredPackageSnapshot]
    typealias Dispatcher = @MainActor (HanlinPreparedAssistantTool, HanlinValue) async throws -> HanlinValue

    private let bindings: [HanlinScriptBackendRoute: HanlinPreparedAssistantTool]
    private let currentPackages: SnapshotProvider
    private let dispatch: Dispatcher

    init(packages: [HanlinStoredPackageSnapshot],
         currentPackages: @escaping SnapshotProvider,
         dispatch: @escaping Dispatcher) throws {
        var bindings: [HanlinScriptBackendRoute: HanlinPreparedAssistantTool] = [:]
        for package in packages {
            for binding in try package.preparedAssistantTools() {
                let route = Self.route(for: binding)
                guard bindings.updateValue(binding, forKey: route) == nil else {
                    throw HanlinPreparedAssistantToolError.invalidDeclaration
                }
            }
        }
        self.bindings = bindings
        self.currentPackages = currentPackages
        self.dispatch = dispatch
    }

    static func live(platform: HanlinScriptingPlatform = .shared) async throws -> Self {
        let packages = try await platform.preparedAssistantToolPackages()
        return try Self(packages: packages,
            currentPackages: { try await platform.preparedAssistantToolPackages() },
            dispatch: { try await platform.executePreparedAssistantTool($0, parameters: $1) })
    }

    /// Readiness and corrupt MiniApp declarations affect this contribution only.
    /// Existing native, MCP and legacy tools remain available during bootstrap or transfer.
    static func catalogContribution(
        load: @MainActor () async throws -> HanlinPreparedAssistantToolAdapter = {
            try await HanlinPreparedAssistantToolAdapter.live()
        }
    ) async -> (adapter: HanlinPreparedAssistantToolAdapter?,
                sources: [HanlinCanonicalToolAuthority.ScriptSource]) {
        do {
            let adapter = try await load()
            return (adapter, try adapter.canonicalSources())
        } catch {
            NativeToolTraceLogger.shared.log("prepared_miniapp_tool_catalog_unavailable", [
                "errorType": String(describing: type(of: error)),
                "message": error.localizedDescription,
            ])
            return (nil, [])
        }
    }

    func canonicalSources() throws -> [HanlinCanonicalToolAuthority.ScriptSource] {
        let snapshots = try bindings.values.sorted {
            $0.providerInstanceID.rawValue < $1.providerInstanceID.rawValue
        }.map { binding in
            HanlinScriptProviderSnapshot(
                packageID: binding.packageID, installedPackageID: binding.installedPackageID,
                providerInstanceID: binding.providerInstanceID,
                descriptorRevision: try HanlinDescriptorRevision(binding.generation),
                tool: binding.tool, route: Self.route(for: binding))
        }
        return try HanlinScriptCanonicalAdapter.project(snapshots)
    }

    func contains(_ route: HanlinScriptBackendRoute) -> Bool { bindings[route] != nil }

    func execute(route: HanlinScriptBackendRoute, argumentsJSON: String) async -> NativeToolResult {
        do {
            guard let expected = bindings[route] else { throw HanlinPreparedAssistantToolError.staleInstallation }
            let packages = try await currentPackages()
            guard let package = packages.first(where: { $0.record.installedPackageID == expected.installedPackageID }),
                  try package.preparedAssistantTools().contains(expected) else {
                throw HanlinPreparedAssistantToolError.staleInstallation
            }
            let json = try HanlinJSONValue.decodeCanonicalJSON(Data(argumentsJSON.utf8))
            guard case .object = json else { throw HanlinPreparedAssistantToolError.invalidArguments }
            let value = try await dispatch(expected, HanlinValue(json: json))
            return NativeToolResult(
                modelText: String(decoding: try value.jsonValue().canonicalJSONData(), as: UTF8.self),
                outcome: .succeeded)
        } catch {
            // Return the real failure; a queued request or unavailable runtime
            // never becomes a completed tool result.
            return NativeToolResult(modelText: "Mini app tool failed: \(error.localizedDescription)",
                                    userText: error.localizedDescription, outcome: .failed)
        }
    }

    private static func route(for binding: HanlinPreparedAssistantTool) -> HanlinScriptBackendRoute {
        .init(providerInstanceID: binding.providerInstanceID,
              installedPackageID: binding.installedPackageID,
              entrypointPath: binding.entrypoint.id, localToolID: binding.tool.id)
    }
}
