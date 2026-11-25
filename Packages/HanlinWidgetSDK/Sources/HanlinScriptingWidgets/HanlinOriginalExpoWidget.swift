import AppIntents
@preconcurrency import ExpoWidgets
import Foundation
import HanlinLocalization
import HanlinPlatformContracts
import SwiftUI
import WidgetKit

/// Names and ownership come from the registered original createWidget API.
/// Each product resolves its own registry; a picker ID never aliases another
/// package's name or the other Hanlin application's store.
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

public struct HanlinOriginalExpoWidgetEntry: TimelineEntry {
    public let date: Date
    public let original: WidgetsTimelineEntry?
    public let unavailableMessage: String?
    public let configuration: [String: HanlinValue]
    public init(date: Date = .now, original: WidgetsTimelineEntry? = nil, unavailableMessage: String? = nil,
                configuration: [String: HanlinValue] = [:]) {
        self.date = date
        self.original = original
        self.unavailableMessage = unavailableMessage
        self.configuration = configuration
    }
}

public struct HanlinOriginalExpoWidgetProvider: AppIntentTimelineProvider {
    public init() {}
    public func placeholder(in context: Context) -> HanlinOriginalExpoWidgetEntry {
        if let name = HanlinExpoWidgetsIntegration.registeredWidgetNames().first {
            let entry = HanlinExpoWidgetsIntegration.placeholder(named: name)
            return .init(date: entry.date, original: entry)
        }
        return .init(unavailableMessage: String(localized: "Choose an Expo widget registered by a MiniApp.", bundle: HanlinLocalization.bundle))
    }
    public func snapshot(for configuration: HanlinOriginalExpoWidgetConfiguration, in context: Context) async -> HanlinOriginalExpoWidgetEntry {
        let scheduled = await timeline(for: configuration, in: context)
        return scheduled.entries.last(where: { $0.date <= .now }) ?? scheduled.entries.first ??
            .init(unavailableMessage: String(localized: "This Expo widget has no timeline.", bundle: HanlinLocalization.bundle))
    }
    public func timeline(for configuration: HanlinOriginalExpoWidgetConfiguration, in context: Context) async -> Timeline<HanlinOriginalExpoWidgetEntry> {
        guard let selected = configuration.widget,
              HanlinExpoWidgetsIntegration.registeredWidgetNames().contains(selected.id) else {
            return Timeline(entries: [.init(unavailableMessage: String(localized: "Choose a current Expo widget from this app.", bundle: HanlinLocalization.bundle))], policy: .never)
        }
        let values: [String: HanlinValue]
        do {
            values = try HanlinOriginalExpoWidgetOptions.values(widgetID: selected.id,
                options: configuration.options, json: configuration.configurationJSON)
        } catch {
            return Timeline(entries: [.init(unavailableMessage: error.localizedDescription)], policy: .never)
        }
        let timeline = HanlinExpoWidgetsIntegration.timeline(named: selected.id, family: context.family)
        let entries = timeline.entries.map { HanlinOriginalExpoWidgetEntry(date: $0.date, original: $0, configuration: values) }
        return Timeline(entries: entries.isEmpty
            ? [.init(unavailableMessage: String(localized: "This Expo widget has no timeline.", bundle: HanlinLocalization.bundle))] : entries, policy: timeline.policy)
    }
}

public struct HanlinOriginalExpoWidget: Widget {
    public init() {}
    public var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: HanlinExpoWidgetsIntegration.genericWidgetKind,
            intent: HanlinOriginalExpoWidgetConfiguration.self, provider: HanlinOriginalExpoWidgetProvider()) { entry in
            if let original = entry.original {
                WidgetsEntryView(entry: original, configuration: entry.configuration.mapValues { $0.toAny() })
            } else {
                Text(entry.unavailableMessage ?? String(localized: "Expo widget unavailable", bundle: HanlinLocalization.bundle))
                    .multilineTextAlignment(.center)
                    .padding()
                    .containerBackground(.fill.tertiary, for: .widget)
            }
        }
        .configurationDisplayName(Text("Expo MiniApp", bundle: HanlinLocalization.bundle))
        .description(Text("Original Expo widget layouts and timelines registered by your MiniApps.", bundle: HanlinLocalization.bundle))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge,
            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
