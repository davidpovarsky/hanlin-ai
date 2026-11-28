import AppIntents
import Foundation
import HanlinPlatformContracts

/// Source-aware continuation for the existing native-node ActivityKit renderer.
/// It is distinct from WidgetProgram-origin admission and its local callbacks.
public struct HanlinLiveActivityHostActionIntent: AppIntent {
    public static let title: LocalizedStringResource = "Run Live Activity Action"
    public static let isDiscoverable = false
    public static var supportedModes: IntentModes { .foreground(.immediate) }
#if os(iOS)
    public static var allowedExecutionTargets: IntentExecutionTargets { .main }
#endif

    @Parameter(title: "Live Activity Action") public var commandJSON: String

    private struct Target: Codable {
        let identity: HanlinScriptExtensionIdentity
        let actionName: String
        let parameters: HanlinValue
    }

    public init() { commandJSON = "" }

    public init(identity: HanlinScriptExtensionIdentity, actionName: String, parameters: HanlinValue) throws {
        commandJSON = String(decoding: try JSONEncoder().encode(
            Target(identity: identity, actionName: actionName, parameters: parameters)), as: UTF8.self)
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<String> & ShowsSnippetIntent {
        let target = try JSONDecoder().decode(Target.self, from: Data(commandJSON.utf8))
        let store = try HanlinScriptExtensionStore()
        let queued = try HanlinWidgetHostActionExecutor.enqueueLiveActivity(identity: target.identity,
            actionName: target.actionName, parameters: target.parameters, store: store)
        await HanlinWidgetHostActionContinuation.resume(storeRoot: store.root)
        return .result(value: queued.id.uuidString,
                       snippetIntent: HanlinInvocationSnippetIntent(invocationID: queued.id))
    }
}

#if os(iOS)
extension HanlinLiveActivityHostActionIntent: LiveActivityIntent {}
#endif
