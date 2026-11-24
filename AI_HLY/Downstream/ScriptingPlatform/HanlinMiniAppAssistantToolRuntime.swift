import Foundation
import HanlinExpoRuntime
import HanlinMiniAppCore
import HanlinNativeScriptCoreSupport
import HanlinNativeScriptRuntime
import HanlinPlatformContracts
import HanlinScriptContracts
import HanlinScriptStore

enum HanlinMiniAppAssistantToolError: LocalizedError {
    case staleSelection
    case invalidArguments
    case invalidEntrypoint
    case nativeScriptBusy

    var errorDescription: String? {
        switch self {
        case .staleSelection: return "The selected MiniApp changed or is no longer available. Attach it again."
        case .invalidArguments: return "The MiniApp action requires an object matching its declared input schema."
        case .invalidEntrypoint: return "This MiniApp does not contain a prepared, dedicated assistantTool entrypoint."
        case .nativeScriptBusy: return "Another NativeScript MiniApp is using its runtime. Close it before invoking this action."
        }
    }
}

/// Executes only a declared assistantTool bundle, only after actual tool dispatch.
/// The original NativeScript and Expo engines remain the execution authorities.
@MainActor
enum HanlinMiniAppAssistantToolRuntime {
    static func execute(
        selection: HanlinMiniAppAssistantToolSelection,
        parameters: HanlinValue
    ) async throws -> HanlinValue {
        try await HanlinScriptingPlatform.shared.withAssistantToolExecution {
            try await executeAdmitted(selection: selection, parameters: parameters)
        }
    }

    private static func executeAdmitted(
        selection: HanlinMiniAppAssistantToolSelection,
        parameters: HanlinValue
    ) async throws -> HanlinValue {
        let platform = HanlinScriptingPlatform.shared
        let package = try selection.currentPackage(in: await platform.assistantToolPackages())
        guard let artifactRoot = platform.activeArtifactURL(for: package) else {
            throw HanlinMiniAppAssistantToolError.staleSelection
        }
        let sourceURL = try dedicatedSourceURL(
            package: package, entrypoint: selection.entrypoint, artifactRoot: artifactRoot)
        try Task.checkCancellation()
        let result: HanlinValue
        switch selection.entrypoint.runtimeProfile {
        case .hanlinNativeScript:
            result = try await executeNativeScript(
                selection: selection, package: package, sourceURL: sourceURL, parameters: parameters)
        case .hanlinExpo:
            result = try await executeExpo(
                selection: selection, package: package, sourceURL: sourceURL, parameters: parameters)
        default:
            throw HanlinMiniAppAssistantToolError.invalidEntrypoint
        }
        // A renderer or later request must never reinterpret an old result using
        // an updated package generation or a replacement installed identity.
        _ = try selection.currentPackage(in: await platform.assistantToolPackages())
        try Task.checkCancellation()
        return result
    }

    /// Runtime constructors load package.json's main. Check that main is exactly
    /// the declared tool source, and that neither the source nor any parent escapes
    /// through a symlink. A distinct filename beside app/index is not sufficient.
    static func dedicatedSourceURL(
        package: HanlinStoredPackageSnapshot,
        entrypoint: HanlinPackageEntrypointDescriptor,
        artifactRoot: URL
    ) throws -> URL {
        guard entrypoint.kind == .assistantTool, entrypoint.assistantTool != nil,
              [.hanlinNativeScript, .hanlinExpo].contains(entrypoint.runtimeProfile) else {
            throw HanlinMiniAppAssistantToolError.invalidEntrypoint
        }
        let components = entrypoint.sourcePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." &&
                  !$0.contains("\\") && !$0.contains(":") && !$0.contains("\0") }) else {
            throw HanlinMiniAppAssistantToolError.invalidEntrypoint
        }
        var source = artifactRoot.standardizedFileURL
        let rootValues = try source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else {
            throw HanlinMiniAppAssistantToolError.invalidEntrypoint
        }
        for (index, component) in components.enumerated() {
            source.append(path: String(component))
            let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true,
                  (index == components.count - 1 ? values.isRegularFile == true : values.isDirectory == true) else {
                throw HanlinMiniAppAssistantToolError.invalidEntrypoint
            }
        }
        let root = source.deletingLastPathComponent()
        guard !package.entrypoints.contains(where: {
            $0.kind == .app && artifactRoot.appending(path: $0.sourcePath).standardizedFileURL
                .deletingLastPathComponent() == root
        }) else { throw HanlinMiniAppAssistantToolError.invalidEntrypoint }
        let metadataURL = root.appending(path: "package.json")
        let metadataValues = try metadataURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard metadataValues.isRegularFile == true, metadataValues.isSymbolicLink != true,
              let metadata = try JSONSerialization.jsonObject(with: Data(contentsOf: metadataURL)) as? [String: Any],
              metadata["main"] as? String == source.lastPathComponent,
              metadata["hanlinRuntime"] as? String == entrypoint.runtimeProfile.rawValue,
              entrypoint.runtimeProfile != .hanlinNativeScript || source.lastPathComponent == "bundle.mjs" else {
            throw HanlinMiniAppAssistantToolError.invalidEntrypoint
        }
        return source
    }

    private static func executeNativeScript(
        selection: HanlinMiniAppAssistantToolSelection,
        package: HanlinStoredPackageSnapshot,
        sourceURL: URL,
        parameters: HanlinValue
    ) async throws -> HanlinValue {
        guard HanlinNativeScriptSession.activeSessionIdentifier == nil else {
            throw HanlinMiniAppAssistantToolError.nativeScriptBusy
        }
        let container = try await HanlinMiniAppDataStore(
            root: HanlinMiniAppDataStore.applicationSupportRoot()).container(for: package.appID)
        let current = try selection.currentPackage(in: await HanlinScriptingPlatform.shared.assistantToolPackages())
        try Task.checkCancellation()
        let sessionID = UUID().uuidString.lowercased()
        let adapter = NativeScriptHostServicesAdapter(
            appID: current.appID, installedPackageID: current.record.installedPackageID,
            grantedCapabilities: Set(current.grantedCapabilities.map(\.rawValue)), sessionID: sessionID)
        let session = try HanlinNativeScriptSession(
            applicationRoot: sourceURL.deletingLastPathComponent(), environment: [
                "HANLIN_APP_ID": current.appID.rawValue,
                "HANLIN_MINIAPP_DATA_ROOT": container.root.path(percentEncoded: false),
                "HANLIN_MINIAPP_STATE_DIR": container.state.path(percentEncoded: false),
                "HANLIN_MINIAPP_DOCUMENTS_DIR": container.documents.path(percentEncoded: false),
                "HANLIN_MINIAPP_CACHE_DIR": container.cache.path(percentEncoded: false),
                "HANLIN_EXECUTION_MODE": "assistant-tool",
                "HANLIN_ACTION_ID": selection.action.id
            ], sessionID: sessionID)
        HanlinNativeServicesBridge.register(adapter, forSessionID: sessionID)
        defer {
            // Detach JS callback blocks while this session's VM is still alive.
            HanlinNativeServicesBridge.unregisterProvider(forSessionID: sessionID)
            session.shutdown()
        }
        HanlinScriptingPlatform.shared.recordCompiledMiniAppStorageUse()
        try session.start()
        try Task.checkCancellation()
        return try await adapter.invokeRegisteredAction(
            HanlinActionID(validating: selection.action.id),
            capability: HanlinCapabilityID(validating: "assistant-tool"),
            caller: HanlinAppID(validating: "hanlin.host"), payload: parameters)
    }

    private static func executeExpo(
        selection: HanlinMiniAppAssistantToolSelection,
        package: HanlinStoredPackageSnapshot,
        sourceURL: URL,
        parameters: HanlinValue
    ) async throws -> HanlinValue {
        let sessionID = UUID().uuidString.lowercased()
        let adapter = ExpoHostServicesAdapter(
            appID: package.appID, installedPackageID: package.record.installedPackageID,
            grantedCapabilities: Set(package.grantedCapabilities.map(\.rawValue)), sessionID: sessionID)
        let session = try HanlinExpoSession(
            applicationRoot: sourceURL.deletingLastPathComponent(), sessionID: sessionID,
            packageID: package.record.packageID.rawValue,
            installedPackageID: package.record.installedPackageID.rawValue,
            packageGeneration: package.record.activeGeneration, isNativeAPIGranted: true)
        HanlinExpoHostServicesBridge.register(provider: adapter, forSessionID: sessionID)
        defer {
            HanlinExpoHostServicesBridge.unregister(sessionID: sessionID)
            session.shutdown()
        }
        do {
            try Task.checkCancellation()
            // This empty, unpresented root belongs to the dedicated tool bundle.
            // It does not import or launch the foreground application.
            HanlinScriptingPlatform.shared.recordCompiledMiniAppStorageUse()
            try session.start(moduleName: "HanlinAssistantTool")
            let value = try await adapter.actionChannel.invoke(
                action: selection.action.id, caller: "hanlin.host", parameters: parameters)
            await adapter.actionChannel.close()
            return value
        } catch {
            await adapter.actionChannel.close()
            throw error
        }
    }
}
