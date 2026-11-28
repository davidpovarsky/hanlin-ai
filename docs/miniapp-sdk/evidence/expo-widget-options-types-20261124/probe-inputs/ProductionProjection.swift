import AppIntents
import CryptoKit
import Foundation
import HanlinPlatformContracts

// Fixture-only project dependencies: no Expo storage/registration/localization proof.
enum HanlinLocalization { static let bundle = Bundle.main }
enum ProbeFixtures {
    static let options = [
        HanlinOriginalExpoWidgetOptionEntity(widgetID: "widget-one", parameter: "book", name: "Genesis", value: "Genesis"),
        HanlinOriginalExpoWidgetOptionEntity(widgetID: "widget-one", parameter: "book", name: "Exodus", value: "Exodus"),
        HanlinOriginalExpoWidgetOptionEntity(widgetID: "widget-one", parameter: "é", name: "Unicode", value: "selected")
    ]
}
enum HanlinExpoWidgetsIntegration {
    static func registeredWidgets(includeInactive: Bool = false) -> [HanlinOriginalExpoWidgetEntity] {
        [.init(id: "widget-one", name: "Fixture", packageID: "fixture.package")]
    }
}

public struct HanlinOriginalExpoWidgetEntity: AppEntity {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("Expo widget", table: "HanlinAppIntents"))
    public static let defaultQuery = HanlinOriginalExpoWidgetEntityQuery()
    public let id: String
    public let name: String
    public let packageID: String
    public var displayRepresentation: DisplayRepresentation {
        .init(title: "\(name)", subtitle: "\(packageID)")
    }
    public init(id: String, name: String, packageID: String) {
        self.id = id
        self.name = name
        self.packageID = packageID
    }
}

public struct HanlinOriginalExpoWidgetEntityQuery: EnumerableEntityQuery, EntityStringQuery {
    public init() {}
    public func allEntities() async throws -> [HanlinOriginalExpoWidgetEntity] {
        HanlinExpoWidgetsIntegration.registeredWidgets().map {
            .init(id: $0.id, name: $0.name, packageID: $0.packageID)
        }
    }
    public func suggestedEntities() async throws -> [HanlinOriginalExpoWidgetEntity] { try await allEntities() }
    public func entities(for identifiers: [String]) async throws -> [HanlinOriginalExpoWidgetEntity] {
        let current = HanlinExpoWidgetsIntegration.registeredWidgets(includeInactive: true).map {
            HanlinOriginalExpoWidgetEntity(id: $0.id, name: $0.name, packageID: $0.packageID)
        }
        return identifiers.compactMap { id in current.first { $0.id == id } }
    }
    public func entities(matching string: String) async throws -> [HanlinOriginalExpoWidgetEntity] {
        try await allEntities().filter {
            string.isEmpty || $0.name.localizedCaseInsensitiveContains(string) ||
                $0.packageID.localizedCaseInsensitiveContains(string)
        }
    }
}

public struct HanlinOriginalExpoWidgetConfiguration: WidgetConfigurationIntent {
    public static let title = LocalizedStringResource("Expo widget", table: "HanlinAppIntents")
    public static let description = IntentDescription(LocalizedStringResource("Choose a widget registered by an installed MiniApp using the original Expo Widgets API.", table: "HanlinAppIntents"))
    @Parameter(title: LocalizedStringResource("Widget", table: "HanlinAppIntents")) public var widget: HanlinOriginalExpoWidgetEntity?
    @Parameter(title: LocalizedStringResource("Widget options", table: "HanlinAppIntents"),
        description: LocalizedStringResource("Choose one value for each parameter. These choices override matching JSON values.", table: "HanlinAppIntents"),
        default: [])
    public var options: [HanlinOriginalExpoWidgetOptionEntity]
    @Parameter(title: LocalizedStringResource("Configuration (JSON)", table: "HanlinAppIntents"),
        description: LocalizedStringResource("Additional widget values, for example text, numbers and true or false.", table: "HanlinAppIntents"),
        default: "{}")
    public var configurationJSON: String
    public init() {}
    public init(widget: HanlinOriginalExpoWidgetEntity?, options: [HanlinOriginalExpoWidgetOptionEntity] = [],
                configurationJSON: String = "{}") {
        self.widget = widget
        self.options = options
        self.configurationJSON = configurationJSON
    }
}

public struct HanlinOriginalExpoWidgetOptionEntity: AppEntity {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Widget option", table: "HanlinAppIntents"))
    public static let defaultQuery = HanlinOriginalExpoWidgetOptionQuery()
    public let id: String
    public let widgetID: String
    public let parameter: String
    public let name: String
    public let value: String
    public let subtitle: String?

    public var displayRepresentation: DisplayRepresentation {
        .init(title: "\(parameter): \(name)",
              subtitle: subtitle.map { LocalizedStringResource(stringLiteral: $0) })
    }

    public init(widgetID: String, parameter: String, name: String, value: String, subtitle: String? = nil) {
        self.widgetID = widgetID
        self.parameter = parameter
        self.name = name
        self.value = value
        self.subtitle = subtitle
        // JSON preserves the original strings without delimiter aliasing.
        let bytes = (try? JSONEncoder().encode([widgetID, parameter, value])) ?? Data()
        self.id = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}

public struct HanlinOriginalExpoWidgetOptionQuery: EnumerableEntityQuery, EntityStringQuery {
    @IntentParameterDependency<HanlinOriginalExpoWidgetConfiguration>(\.$widget)
    private var configuration

    public init() {}

    public func allEntities() async throws -> [HanlinOriginalExpoWidgetOptionEntity] {
        guard let widgetID = configuration?.widget.id else { return [] }
        return HanlinOriginalExpoWidgetOptions.options(widgetID: widgetID)
    }

    public func suggestedEntities() async throws -> [HanlinOriginalExpoWidgetOptionEntity] {
        try await allEntities()
    }

    public func entities(for identifiers: [String]) async throws -> [HanlinOriginalExpoWidgetOptionEntity] {
        let available = HanlinExpoWidgetsIntegration.registeredWidgets(includeInactive: true)
            .flatMap { HanlinOriginalExpoWidgetOptions.options(widgetID: $0.id, includeInactive: true) }
        return identifiers.compactMap { id in available.first { $0.id == id } }
    }

    public func entities(matching string: String) async throws -> [HanlinOriginalExpoWidgetOptionEntity] {
        try await allEntities().filter {
            string.isEmpty || $0.parameter.localizedCaseInsensitiveContains(string) ||
                $0.name.localizedCaseInsensitiveContains(string) || $0.value.localizedCaseInsensitiveContains(string)
        }
    }
}

public enum HanlinOriginalExpoWidgetConfigurationError: LocalizedError, Sendable {
    case invalidDictionary, unavailableOption, conflictingOptions(String)

    public var errorDescription: String? {
        switch self {
        case .invalidDictionary:
            String(localized: "Configuration JSON must contain an object.", bundle: HanlinLocalization.bundle)
        case .unavailableOption:
            String(localized: "Select this widget's current options again.", bundle: HanlinLocalization.bundle)
        case let .conflictingOptions(parameter):
            String(localized: "Choose one option for each widget parameter.", bundle: HanlinLocalization.bundle) + " " + parameter
        }
    }
}

public enum HanlinOriginalExpoWidgetOptions {
    /// Enumerate parameter keys written by original setConfigurationParameterEnum,
    /// and decode their options with the original Expo helper.
    public static func options(widgetID: String, includeInactive: Bool = false) -> [HanlinOriginalExpoWidgetOptionEntity] {
        ProbeFixtures.options.filter { $0.widgetID == widgetID }
    }

    /// JSON retains original string/number/Boolean types. Explicit native enum
    /// choices override matching dictionary keys and must remain current.
    public static func values(widgetID: String, options selected: [HanlinOriginalExpoWidgetOptionEntity],
                              json: String) throws -> [String: HanlinValue] {
        let decoded: HanlinValue
        do {
            decoded = try HanlinValue(jsonValue: HanlinJSONValue.decodeCanonicalJSON(Data(json.utf8)))
        } catch {
            throw HanlinOriginalExpoWidgetConfigurationError.invalidDictionary
        }
        guard case var .object(values) = decoded else {
            throw HanlinOriginalExpoWidgetConfigurationError.invalidDictionary
        }
        let available = options(widgetID: widgetID)
        var selections: [String: String] = [:]
        for selection in selected {
            guard selection.widgetID == widgetID,
                  let current = available.first(where: { $0.id == selection.id }),
                  current.parameter == selection.parameter, current.value == selection.value else {
                throw HanlinOriginalExpoWidgetConfigurationError.unavailableOption
            }
            if let previous = selections[current.parameter], previous != current.value {
                throw HanlinOriginalExpoWidgetConfigurationError.conflictingOptions(current.parameter)
            }
            selections[current.parameter] = current.value
            values[current.parameter] = .string(current.value)
        }
        // Preserve byte-exact option overrides until the public dictionary boundary.
        // Swift keys can alias distinct UTF-8 keys; reject that without losing data.
        var result: [String: HanlinValue] = [:]
        for (key, value) in values {
            guard result.updateValue(value, forKey: key) == nil else {
                throw HanlinContractError.duplicateObjectKey(key: key, path: "")
            }
        }
        return result
    }
}

public typealias PreparedWidgetPublisher = @Sendable (String, String, [String: HanlinValue]) async throws -> String

func publishConverted(entrypointID: String, variantID: String, rawProps: HanlinObject<HanlinJSONValue>, preparedWidgetPublisher: PreparedWidgetPublisher) async throws -> String {
            var props: [String: HanlinValue] = [:]
            for (key, value) in rawProps {
                guard props.updateValue(try HanlinValue(jsonValue: value), forKey: key) == nil else {
                    throw HanlinContractError.duplicateObjectKey(key: key, path: "/props")
                }
            }
            return try await preparedWidgetPublisher(entrypointID, variantID, props)
}
