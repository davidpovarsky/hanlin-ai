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
        let session: Session
    }

    private enum Session: Sendable {
        case javaScriptCore(HanlinJavaScriptCoreSession)
        case quickJS(HanlinQuickJSSession)
        case node(HanlinNodeWorkerSession)
        case python(HanlinPythonWorkerSession)

        func loadProgram(_ source: String, filename: String, expectedToolCount: Int) async throws {
            switch self {
            case let .javaScriptCore(session):
                try await session.loadProgram(source, filename: filename, expectedToolCount: expectedToolCount)
            case let .quickJS(session):
                try await session.loadProgram(source, filename: filename, expectedToolCount: expectedToolCount)
            case let .node(session):
                try await session.loadProgram(source, filename: filename, expectedToolCount: expectedToolCount)
            case let .python(session):
                try await session.loadProgram(source, filename: filename, expectedToolCount: expectedToolCount)
            }
        }

        func invoke(toolIndex: Int, parameters: HanlinValue) async throws -> HanlinValue {
            switch self {
            case let .javaScriptCore(session): try await session.invoke(toolIndex: toolIndex, parameters: parameters)
            case let .quickJS(session): try await session.invoke(toolIndex: toolIndex, parameters: parameters)
            case let .node(session): try await session.invoke(toolIndex: toolIndex, parameters: parameters)
            case let .python(session): try await session.invoke(toolIndex: toolIndex, parameters: parameters)
            }
        }

        func dispose() async {
            switch self {
            case let .javaScriptCore(session): await session.dispose()
            case let .quickJS(session): await session.dispose()
            case let .node(session): await session.dispose()
            case let .python(session): await session.dispose()
            }
        }
    }

    private var providers: [HanlinProviderInstanceID: Provider] = [:]
    private var authorizer: Authorizer = { _, _, tool in
        tool.requiredCapabilities.isEmpty && !tool.requiresApproval
    }

    func setAuthorizer(_ authorizer: @escaping Authorizer) {
        self.authorizer = authorizer
    }

    func loadPackage(
        at directory: URL,
        trust: HanlinPackageTrust
    ) async throws -> HanlinProviderInstanceID {
        let package = try HanlinScriptPackageLoader.load(packageDirectory: directory)
        guard trust.satisfies(package.manifest.runtime.minimumTrust) else {
            throw HanlinScriptingError.unsupportedABI("runtime_minimum_trust")
        }
        guard providers[package.providerInstanceID] == nil else {
            return package.providerInstanceID
        }
        let session: Session = switch package.runtimeProfile {
        case .scriptingJSC: .javaScriptCore(try HanlinJavaScriptCoreSession())
        case .hanlinQuickJS: .quickJS(try HanlinQuickJSSession())
        case .hanlinNode:
            .node(try HanlinNodeWorkerSession(identifier: package.providerInstanceID.rawValue))
        case .hanlinPython:
            .python(try HanlinPythonWorkerSession(identifier: package.providerInstanceID.rawValue))
        }
        do {
            try await session.loadProgram(
                package.program,
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
