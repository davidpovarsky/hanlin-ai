import AppIntents
import CoreFoundation
import Foundation
import HanlinPlatformContracts

public struct HanlinInvokeScriptActionIntent: AppIntent {
    public static let title: LocalizedStringResource = "Run Script Action"
    public static let description = IntentDescription("Runs an action supplied by an installed Script package.")
    public static let openAppWhenRun = true

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
        try HanlinScriptExtensionStore().enqueue(command)
        return .result(value: command.id.uuidString, snippetIntent: HanlinInvocationSnippetIntent(invocationID: command.id))
    }

    static func decodeParameters(_ json: String) throws -> HanlinValue {
        guard let data = json.data(using: .utf8) else { throw HanlinScriptAppIntentBridgeError.invalidParameters }
        return try value(JSONSerialization.jsonObject(with: data))
    }

    private static func value(_ object: Any) throws -> HanlinValue {
        switch object {
        case is NSNull:
            return .null
        case let string as String:
            return .string(string)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return .bool(number.boolValue) }
            let value = number.doubleValue
            if value.rounded(.towardZero) == value,
               value >= Double(Int64.min), value <= Double(Int64.max) {
                return .integer(number.int64Value)
            }
            return try .finiteNumber(value)
        case let array as [Any]:
            return .array(try array.map { try value($0) })
        case let dictionary as [String: Any]:
            return .object(try .init(uniqueMembers: dictionary.map {
                (key: $0.key, value: try value($0.value))
            }))
        default:
            throw HanlinScriptAppIntentBridgeError.invalidParameters
        }
    }
}

private enum HanlinScriptAppIntentBridgeError: Error {
    case invalidParameters
}

/// Metadata entry point for the existing shared action and widget intents.
public struct HanlinScriptExtensionIntentsPackage: AppIntentsPackage {}
