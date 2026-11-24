import AppIntents
import CryptoKit
@preconcurrency import ExpoWidgets
import Foundation
import HanlinLocalization
import HanlinPlatformContracts

/// One original enum value, scoped to its exact installed widget registration.
/// Arbitrary imported parameter names do not become synthetic Swift properties.
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
        guard HanlinExpoWidgetsIntegration.registeredWidgets(includeInactive: includeInactive).contains(where: { $0.id == widgetID }),
              let group = WidgetsStorage.appGroupIdentifier, let defaults = UserDefaults(suiteName: group) else { return [] }
        let prefix = "__expo_widgets_\(widgetID)_configuration_options_"
        let parameters = defaults.dictionaryRepresentation().keys.compactMap { key in
            key.hasPrefix(prefix) ? String(key.dropFirst(prefix.count)) : nil
        }.sorted()
        var seen = Set<String>()
        return parameters.flatMap { parameter in
            widgetConfigurationOptions(name: widgetID, parameter: parameter, fallback: []).compactMap { option in
                let entity = HanlinOriginalExpoWidgetOptionEntity(widgetID: widgetID, parameter: parameter,
                    name: option.name, value: option.value, subtitle: option.subtitle)
                return seen.insert(entity.id).inserted ? entity : nil
            }
        }
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
