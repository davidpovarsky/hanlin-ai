import AppIntents
import Foundation
import HanlinPlatformContracts

public struct HanlinInvokeScriptActionIntent: AppIntent {
    public static let title: LocalizedStringResource = "Run Script Action"
    public static let description = IntentDescription("Runs an action supplied by an installed Script package.")
    public static var supportedModes: IntentModes { .foreground(.immediate) }
#if os(iOS)
    public static var allowedExecutionTargets: IntentExecutionTargets { .main }
#endif

    @Parameter(title: "Installed Package")
    public var installedPackageID: String

    @Parameter(title: "Package")
    public var packageID: String

    @Parameter(title: "Generation")
    public var generation: Int

    @Parameter(title: "Entrypoint")
    public var entrypointID: String

    @Parameter(title: "Action")
    public var actionName: String

    @Parameter(title: "Parameters")
    public var parametersJSON: String

    public init() {
        installedPackageID = ""
        packageID = ""
        generation = 0
        entrypointID = ""
        actionName = ""
        parametersJSON = "{}"
    }

    public init(
        identity: HanlinScriptExtensionIdentity,
        actionName: String,
        parametersJSON: String
    ) {
        installedPackageID = identity.installedPackageID.rawValue
        packageID = identity.packageID.rawValue
        generation = Int(clamping: identity.generation)
        entrypointID = identity.entrypointID
        self.actionName = actionName
        self.parametersJSON = parametersJSON
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<String> & ShowsSnippetIntent {
        guard generation >= 0 else { throw HanlinScriptAppIntentBridgeError.invalidParameters }
        let parameters = try Self.decodeParameters(parametersJSON)
        let identity = HanlinScriptExtensionIdentity(
            installedPackageID: try .init(validating: installedPackageID),
            packageID: try .init(validating: packageID),
            generation: UInt64(generation),
            entrypointID: entrypointID
        )
        let command = HanlinScriptResumeCommand(invocation: .init(
            identity: identity,
            entityID: actionName,
            parameters: parameters,
            continueInForeground: true
        ))
        let store = try HanlinScriptExtensionStore()
        try store.enqueue(command)
        await HanlinWidgetHostActionContinuation.resume(storeRoot: store.root)
        return .result(value: command.id.uuidString, snippetIntent: HanlinInvocationSnippetIntent(invocationID: command.id))
    }

    static func decodeParameters(_ json: String) throws -> HanlinValue {
        try HanlinShortcutValueCodec.decode(json, as: .json)
    }

}

private enum HanlinScriptAppIntentBridgeError: Error {
    case invalidParameters
}

/// Metadata entry point for the existing shared action and widget intents.
public struct HanlinScriptExtensionIntentsPackage: AppIntentsPackage {}
