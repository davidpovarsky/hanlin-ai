// Original ScriptWidget source, Copyright 2021-2026 everettjf and contributors.
// Apache-2.0; license/notice retained in HanlinScriptWidgetOriginal/Original.
// Hanlin adaptations: public module API and installed-package/state transport.
#if os(iOS)
import AppIntents
import Foundation
import WidgetKit
import HanlinScriptExtensions
import HanlinExtensionContracts

private enum ScriptWidgetControlCatalog {
    static func controls(type: HanlinScriptWidgetControlKind) throws -> [HanlinScriptWidgetControlRecord] {
        try HanlinScriptWidgetControlCatalog.controls(type: type, store: HanlinScriptExtensionStore())
    }

    static func resolve(id: String, type: HanlinScriptWidgetControlKind) throws -> HanlinScriptWidgetControlRecord? {
        try HanlinScriptWidgetControlCatalog.resolve(identifier: id, type: type, store: HanlinScriptExtensionStore())
    }
}

public struct ScriptWidgetButtonControlEntity: AppEntity, Identifiable {
    public init(id: String, title: String, subtitle: String?, systemImage: String) {
        self.id = id; self.title = title; self.subtitle = subtitle; self.systemImage = systemImage
    }

    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Widget Button"
    public static let defaultQuery = ScriptWidgetButtonControlQuery()

    public let id: String
    public let title: String
    public let subtitle: String?
    public let systemImage: String

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: subtitle.map { "\($0)" })
    }
}

public struct ScriptWidgetButtonControlQuery: EntityQuery {
    public init() {}
    public func entities(for identifiers: [String]) async throws -> [ScriptWidgetButtonControlEntity] {
        try identifiers.compactMap { id in
            guard let control = try ScriptWidgetControlCatalog.resolve(id: id, type: .button) else { return nil }
            return .init(
                id: id,
                title: control.title,
                subtitle: control.subtitle,
                systemImage: control.systemImage
            )
        }
    }

    public func suggestedEntities() async throws -> [ScriptWidgetButtonControlEntity] {
        try ScriptWidgetControlCatalog.controls(type: .button).map { control in
            .init(
                id: control.id,
                title: control.title,
                subtitle: control.subtitle,
                systemImage: control.systemImage
            )
        }
    }
}

public struct ScriptWidgetToggleControlEntity: AppEntity, Identifiable {
    public init(id: String, title: String, subtitle: String?, systemImage: String) {
        self.id = id; self.title = title; self.subtitle = subtitle; self.systemImage = systemImage
    }

    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Widget Toggle"
    public static let defaultQuery = ScriptWidgetToggleControlQuery()

    public let id: String
    public let title: String
    public let subtitle: String?
    public let systemImage: String

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: subtitle.map { "\($0)" })
    }
}

public struct ScriptWidgetToggleControlQuery: EntityQuery {
    public init() {}
    public func entities(for identifiers: [String]) async throws -> [ScriptWidgetToggleControlEntity] {
        try identifiers.compactMap { id in
            guard let control = try ScriptWidgetControlCatalog.resolve(id: id, type: .toggle) else { return nil }
            return .init(id: id, title: control.title, subtitle: control.subtitle, systemImage: control.systemImage)
        }
    }

    public func suggestedEntities() async throws -> [ScriptWidgetToggleControlEntity] {
        try ScriptWidgetControlCatalog.controls(type: .toggle).map { control in
            .init(
                id: control.id,
                title: control.title,
                subtitle: control.subtitle,
                systemImage: control.systemImage
            )
        }
    }
}

public struct SelectScriptWidgetButtonIntent: ControlConfigurationIntent {
    public static let title: LocalizedStringResource = "Select Widget Button"
    public static var isDiscoverable: Bool { false }

    @Parameter(title: "Button") public var control: ScriptWidgetButtonControlEntity?

    public init() {}
}

public struct SelectScriptWidgetToggleIntent: ControlConfigurationIntent {
    public static let title: LocalizedStringResource = "Select Widget Toggle"
    public static var isDiscoverable: Bool { false }

    @Parameter(title: "Toggle") public var control: ScriptWidgetToggleControlEntity?

    public init() {}
}

public struct ScriptWidgetButtonControlValue: Sendable {
    public init(id: String, title: String, systemImage: String) {
        self.id = id; self.title = title; self.systemImage = systemImage
    }

    public let id: String
    public let title: String
    public let systemImage: String
}

public struct ScriptWidgetToggleControlValue: Sendable {
    public init(id: String, title: String, systemImage: String, isOn: Bool) {
        self.id = id; self.title = title; self.systemImage = systemImage; self.isOn = isOn
    }

    public let id: String
    public let title: String
    public let systemImage: String
    public let isOn: Bool
}

public struct ScriptWidgetButtonControlProvider: AppIntentControlValueProvider {
    public init() {}
    public func previewValue(configuration: SelectScriptWidgetButtonIntent) -> ScriptWidgetButtonControlValue {
        let control = configuration.control
        return .init(id: control?.id ?? "", title: control?.title ?? "ScriptWidget", systemImage: control?.systemImage ?? "play.fill")
    }

    public func currentValue(configuration: SelectScriptWidgetButtonIntent) async throws -> ScriptWidgetButtonControlValue {
        guard let id = configuration.control?.id,
              let control = try ScriptWidgetControlCatalog.resolve(id: id, type: .button) else {
            throw HanlinWidgetActionError.inactiveInstance
        }
        return .init(id: control.id, title: control.title, systemImage: control.systemImage)
    }
}

public struct ScriptWidgetToggleControlProvider: AppIntentControlValueProvider {
    public init() {}
    public func previewValue(configuration: SelectScriptWidgetToggleIntent) -> ScriptWidgetToggleControlValue {
        let control = configuration.control
        return .init(id: control?.id ?? "", title: control?.title ?? "ScriptWidget", systemImage: control?.systemImage ?? "switch.2", isOn: false)
    }

    public func currentValue(configuration: SelectScriptWidgetToggleIntent) async throws -> ScriptWidgetToggleControlValue {
        let preview = previewValue(configuration: configuration)
        guard let control = try ScriptWidgetControlCatalog.resolve(id: preview.id, type: .toggle) else {
            throw HanlinWidgetActionError.inactiveInstance
        }
        return .init(
            id: preview.id,
            title: control.title,
            systemImage: control.systemImage,
            isOn: control.isOn
        )
    }
}

public struct RunScriptWidgetControlIntent: AppIntent {
    public static let title: LocalizedStringResource = "Run Widget Control"
    public static var isDiscoverable: Bool { false }
    #if compiler(>=6.4)
    @available(iOS 27.0, *)
    public static var allowedExecutionTargets: ExecutionTargets { .widgetKitExtension }
    #endif

    @Parameter(title: "Control ID") public var controlID: String

    public init() {}
    public init(controlID: String) { self.controlID = controlID }

    public func perform() async throws -> some IntentResult {
        let host = try HanlinExtensionHostConfiguration.load()
        let store = try HanlinScriptExtensionStore(hostConfiguration: host)
        let execution = try HanlinScriptWidgetControlCatalog.perform(identifier: controlID, type: .button, store: store)
        try await HanlinScriptWidgetLiveActivityController.refresh(store: store, identity: execution.identity)
        ControlCenter.shared.reloadControls(ofKind: HanlinScriptWidgetControlCatalog.buttonKind)
        ControlCenter.shared.reloadControls(ofKind: HanlinScriptWidgetControlCatalog.toggleKind)
        WidgetCenter.shared.reloadTimelines(ofKind: try host.requireWidgetKind())
        return .result()
    }
}

public struct SetScriptWidgetControlValueIntent: SetValueIntent {
    public static let title: LocalizedStringResource = "Set Widget Control Value"
    public static var isDiscoverable: Bool { false }
    #if compiler(>=6.4)
    @available(iOS 27.0, *)
    public static var allowedExecutionTargets: ExecutionTargets { .widgetKitExtension }
    #endif

    @Parameter(title: "Enabled") public var value: Bool
    @Parameter(title: "Control ID") public var controlID: String

    public init() {}
    public init(controlID: String) { self.controlID = controlID }

    public func perform() async throws -> some IntentResult {
        let host = try HanlinExtensionHostConfiguration.load()
        let store = try HanlinScriptExtensionStore(hostConfiguration: host)
        let execution = try HanlinScriptWidgetControlCatalog.perform(identifier: controlID, type: .toggle,
            value: value, store: store)
        try await HanlinScriptWidgetLiveActivityController.refresh(store: store, identity: execution.identity)
        ControlCenter.shared.reloadControls(ofKind: HanlinScriptWidgetControlCatalog.buttonKind)
        ControlCenter.shared.reloadControls(ofKind: HanlinScriptWidgetControlCatalog.toggleKind)
        WidgetCenter.shared.reloadTimelines(ofKind: try host.requireWidgetKind())
        return .result()
    }
}

#endif
