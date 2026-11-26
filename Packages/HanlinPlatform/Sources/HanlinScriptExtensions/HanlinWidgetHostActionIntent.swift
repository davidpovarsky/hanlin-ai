import AppIntents
import Foundation

/// This action queues a declared package action and opens its owning Host.
/// Original local widget actions continue using their non-opening intents.
public struct HanlinWidgetHostActionIntent: AppIntent {
    public static let title: LocalizedStringResource = "Run Widget Host Action"
    public static let description = IntentDescription("Continues the widget's declared package action in its owning app.")
    public static let isDiscoverable = false
    public static var supportedModes: IntentModes { .foreground(.immediate) }
#if os(iOS)
    public static var allowedExecutionTargets: IntentExecutionTargets { .main }
#endif

    @Parameter(title: "Widget Action")
    public var commandJSON: String

    public init() { commandJSON = "" }

    public init(command: HanlinWidgetActionCommand) throws {
        commandJSON = String(decoding: try JSONEncoder().encode(command), as: UTF8.self)
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<String> & ShowsSnippetIntent {
        let command = try JSONDecoder().decode(HanlinWidgetActionCommand.self, from: Data(commandJSON.utf8))
        let store = try HanlinScriptExtensionStore()
        let queued = try HanlinWidgetHostActionExecutor.enqueue(command, store: store)
        // Activation can precede perform(). Wake the existing drain after the
        // actual enqueue; no scheduling result is reported as action success.
        await HanlinWidgetHostActionContinuation.resume(storeRoot: store.root)
        return .result(value: queued.id.uuidString,
                       snippetIntent: HanlinInvocationSnippetIntent(invocationID: queued.id))
    }
}

#if os(iOS)
extension HanlinWidgetHostActionIntent: LiveActivityIntent {}
#endif
