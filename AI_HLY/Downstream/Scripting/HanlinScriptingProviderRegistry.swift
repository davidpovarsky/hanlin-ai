import Foundation
import HanlinPlatformContracts

struct HanlinScriptBackendRoute: Hashable, Sendable {
    let providerInstanceID: HanlinProviderInstanceID
    let installedPackageID: HanlinInstalledPackageID
    let entrypointPath: String
    let localToolID: HanlinToolID
}

struct HanlinScriptProviderSnapshot: Hashable, Sendable {
    let packageID: HanlinPackageID
    let installedPackageID: HanlinInstalledPackageID
    let providerInstanceID: HanlinProviderInstanceID
    let descriptorRevision: HanlinDescriptorRevision
    let tool: HanlinScriptExportedTool
    let route: HanlinScriptBackendRoute
}

struct HanlinScriptToolExecutionResult: Hashable, Sendable {
    let success: Bool
    let message: String
    let data: HanlinValue?
}

actor HanlinScriptingProviderRegistry {
    static let shared = HanlinScriptingProviderRegistry()

    typealias Authorizer = @Sendable (
        HanlinPackageID,
        HanlinInstalledPackageID,
        HanlinScriptExportedTool
    ) async -> Bool

    private struct Provider {
        let package: HanlinLoadedScriptPackage
        let session: HanlinQuickJSSession
    }

    private var providers: [HanlinProviderInstanceID: Provider] = [:]
    private var authorizer: Authorizer = { _, _, tool in
        tool.requiredCapabilities.isEmpty && !tool.requiresApproval
    }

    func setAuthorizer(_ authorizer: @escaping Authorizer) {
        self.authorizer = authorizer
    }

    func loadPackage(at directory: URL) async throws -> HanlinProviderInstanceID {
        let package = try HanlinScriptPackageLoader.load(packageDirectory: directory)
        guard providers[package.providerInstanceID] == nil else {
            return package.providerInstanceID
        }
        let session = try HanlinQuickJSSession()
        do {
            try await session.loadProgram(
                package.javaScript,
                filename: package.manifest.entrypoint.compiledPath,
                expectedToolCount: package.manifest.entrypoint.exportedTools.count
            )
        } catch {
            await session.dispose()
            throw error
        }
        providers[package.providerInstanceID] = Provider(
            package: package,
            session: session
        )
        return package.providerInstanceID
    }

    func unloadPackage(providerInstanceID: HanlinProviderInstanceID) async {
        guard let provider = providers.removeValue(forKey: providerInstanceID) else {
            return
        }
        await provider.session.dispose()
    }

    func unloadAll() async {
        let sessions = providers.values.map(\.session)
        providers.removeAll(keepingCapacity: false)
        for session in sessions {
            await session.dispose()
        }
    }

    func snapshots() -> [HanlinScriptProviderSnapshot] {
        providers.values.flatMap { provider in
            provider.package.manifest.entrypoint.exportedTools.map { tool in
                HanlinScriptProviderSnapshot(
                    packageID: provider.package.manifest.packageID,
                    installedPackageID: provider.package.installedPackageID,
                    providerInstanceID: provider.package.providerInstanceID,
                    descriptorRevision: provider.package.manifest.descriptorRevision,
                    tool: tool,
                    route: HanlinScriptBackendRoute(
                        providerInstanceID: provider.package.providerInstanceID,
                        installedPackageID: provider.package.installedPackageID,
                        entrypointPath: provider.package.manifest.entrypoint.compiledPath,
                        localToolID: tool.id
                    )
                )
            }
        }.sorted { left, right in
            if left.providerInstanceID != right.providerInstanceID {
                return left.providerInstanceID.rawValue < right.providerInstanceID.rawValue
            }
            return left.tool.id.rawValue < right.tool.id.rawValue
        }
    }

    func execute(
        route: HanlinScriptBackendRoute,
        argumentsJSON: String
    ) async throws -> HanlinScriptToolExecutionResult {
        guard let provider = providers[route.providerInstanceID],
              provider.package.installedPackageID == route.installedPackageID,
              provider.package.manifest.entrypoint.compiledPath == route.entrypointPath,
              provider.package.manifest.entrypoint.exportedTools.contains(where: {
                  $0.id == route.localToolID
              }) else {
            throw HanlinScriptingError.unavailableProvider(
                route.providerInstanceID.rawValue
            )
        }
        let json: HanlinJSONValue
        do {
            json = try HanlinJSONValue.decodeCanonicalJSON(Data(argumentsJSON.utf8))
        } catch {
            throw HanlinScriptingError.invalidBridgeValue("invalid_arguments_json")
        }
        guard let toolIndex = provider.package.manifest.entrypoint.exportedTools.firstIndex(
            where: { $0.id == route.localToolID }
        ) else {
            throw HanlinScriptingError.unavailableProvider(route.localToolID.rawValue)
        }
        let tool = provider.package.manifest.entrypoint.exportedTools[toolIndex]
        guard await authorizer(provider.package.manifest.packageID, route.installedPackageID, tool) else {
            throw HanlinScriptingError.unsupportedABI("tool_permission_denied")
        }
        guard !Task.isCancelled else { throw HanlinScriptingError.cancelled }
        let value = try HanlinValue(jsonValue: json)
        let result = try await provider.session.invoke(toolIndex: toolIndex, parameters: value)
        guard case let .object(members) = result,
              case let .bool(success)? = members["success"],
              case let .string(message)? = members["message"] else {
            throw HanlinScriptingError.invalidBridgeValue("invalid_tool_result")
        }
        return HanlinScriptToolExecutionResult(
            success: success,
            message: message,
            data: members["data"]
        )
    }
}
