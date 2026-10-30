import AppIntents
import Foundation
import WidgetKit

public struct HanlinGenericWidgetActionIntent: AppIntent {
    public static let title: LocalizedStringResource = "Hanlin Widget Action"
    public static let isDiscoverable = false
    public static let openAppWhenRun = false
    @Parameter(title: "Widget action") public var commandJSON: String
    public init() { commandJSON = "" }
    public init(command: HanlinWidgetActionCommand) throws {
        commandJSON = String(decoding: try JSONEncoder().encode(command), as: UTF8.self)
    }
    public func perform() async throws -> some IntentResult {
        guard commandJSON.utf8.count <= 256 * 1_024 else { throw HanlinWidgetActionError.invalidIdentity }
        let command = try JSONDecoder().decode(HanlinWidgetActionCommand.self, from: Data(commandJSON.utf8))
        _ = try HanlinWidgetActionExecutor.perform(command, store: HanlinScriptExtensionStore())
        WidgetCenter.shared.reloadTimelines(ofKind: HanlinWidgetActionExecutor.widgetKind)
        return .result()
    }
}

/// SDK SetValueIntent supplies the intended Boolean; repeated on/off requests
/// set that value rather than interpreting a string or blindly flipping it.
public struct HanlinSetWidgetValueIntent: SetValueIntent {
    public static let title: LocalizedStringResource = "Set Hanlin Widget Value"
    public static let isDiscoverable = false
    public static let openAppWhenRun = false
    @Parameter(title: "Widget action") public var commandJSON: String
    @Parameter(title: "Value") public var value: Bool
    public init() { commandJSON = ""; value = false }
    public init(command: HanlinWidgetActionCommand, value: Bool) throws {
        commandJSON = String(decoding: try JSONEncoder().encode(command), as: UTF8.self)
        self.value = value
    }
    public func perform() async throws -> some IntentResult {
        guard commandJSON.utf8.count <= 256 * 1_024 else { throw HanlinWidgetActionError.invalidIdentity }
        var command = try JSONDecoder().decode(HanlinWidgetActionCommand.self, from: Data(commandJSON.utf8))
        command.desiredValue = value
        _ = try HanlinWidgetActionExecutor.perform(command, store: HanlinScriptExtensionStore())
        WidgetCenter.shared.reloadTimelines(ofKind: HanlinWidgetActionExecutor.widgetKind)
        return .result()
    }
}