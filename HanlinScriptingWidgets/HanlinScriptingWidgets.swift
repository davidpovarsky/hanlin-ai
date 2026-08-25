import ActivityKit
import AppIntents
import HanlinPlatformContracts
import HanlinScriptExtensions
import HanlinScriptUI
import SwiftUI
import WidgetKit

@main
struct HanlinScriptingWidgetBundle: WidgetBundle {
    var body: some Widget {
        HanlinScriptingWidget()
        HanlinScriptingLiveActivityWidget()
    }
}

struct HanlinScriptPackageEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Script Package")
    static let defaultQuery = HanlinScriptPackageEntityQuery()

    let id: String
    let displayName: String
    let identity: HanlinScriptExtensionIdentity

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(displayName)")
    }
}

struct HanlinScriptPackageEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [HanlinScriptPackageEntity] {
        try availableEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [HanlinScriptPackageEntity] {
        try availableEntities()
    }

    private func availableEntities() throws -> [HanlinScriptPackageEntity] {
        let snapshot = try HanlinScriptExtensionStore().load()
        return snapshot?.widgets.map {
            HanlinScriptPackageEntity(
                id: Self.id($0.identity),
                displayName: $0.displayName,
                identity: $0.identity
            )
        } ?? []
    }

    static func id(_ identity: HanlinScriptExtensionIdentity) -> String {
        "\(identity.installedPackageID.rawValue)|\(identity.entrypointID)"
    }
}

struct HanlinWidgetConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Script Package"
    static let description = IntentDescription("Select an installed Script package widget.")

    @Parameter(title: "Package")
    var package: HanlinScriptPackageEntity?
}

struct HanlinWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: HanlinScriptWidgetSnapshot?
}

struct HanlinWidgetTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> HanlinWidgetEntry {
        .init(date: .now, snapshot: nil)
    }

    func snapshot(
        for configuration: HanlinWidgetConfigurationIntent,
        in context: Context
    ) async -> HanlinWidgetEntry {
        .init(date: .now, snapshot: selectedSnapshot(configuration))
    }

    func timeline(
        for configuration: HanlinWidgetConfigurationIntent,
        in context: Context
    ) async -> Timeline<HanlinWidgetEntry> {
        let selected = selectedSnapshot(configuration)
        let refresh = max(selected?.validUntil ?? Date.now.addingTimeInterval(900), .now)
        return Timeline(entries: [.init(date: .now, snapshot: selected)], policy: .after(refresh))
    }

    private func selectedSnapshot(
        _ configuration: HanlinWidgetConfigurationIntent
    ) -> HanlinScriptWidgetSnapshot? {
        guard let snapshots = try? HanlinScriptExtensionStore().load()?.widgets else { return nil }
        guard let selected = configuration.package else { return snapshots.first }
        return snapshots.first {
            HanlinScriptPackageEntityQuery.id($0.identity) == selected.id
        }
    }
}

struct HanlinScriptingWidget: Widget {
    let kind = "com.hanlin.scripting.widget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: HanlinWidgetConfigurationIntent.self,
            provider: HanlinWidgetTimelineProvider()
        ) { entry in
            HanlinExtensionSnapshotView(snapshot: entry.snapshot)
                .widgetURL(entry.snapshot?.deepLink)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Script Package")
        .description("Displays an extension-safe snapshot from an installed Script package.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct HanlinScriptingLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HanlinGenericLiveActivityAttributes.self) { context in
            HanlinExtensionNodeView(node: context.state.root)
                .padding()
                .activityBackgroundTint(Color.clear)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: "curlybraces") }
                DynamicIslandExpandedRegion(.center) { Text(context.state.title).lineLimit(2) }
                DynamicIslandExpandedRegion(.bottom) {
                    HanlinExtensionNodeView(node: context.state.root).lineLimit(2)
                }
            } compactLeading: {
                Image(systemName: "curlybraces")
            } compactTrailing: {
                Text("\(context.state.revision)")
            } minimal: {
                Image(systemName: "curlybraces")
            }
        }
    }
}

private struct HanlinExtensionSnapshotView: View {
    let snapshot: HanlinScriptWidgetSnapshot?

    var body: some View {
        if let snapshot {
            HanlinExtensionNodeView(node: snapshot.root)
        } else {
            ContentUnavailableView("Choose a Script Package", systemImage: "curlybraces.square")
        }
    }
}

private struct HanlinExtensionNodeView: View {
    let node: HanlinScriptUINode

    @ViewBuilder
    var body: some View {
        switch node.kind {
        case .text:
            Text(text("text") ?? "")
        case .image:
            Image(systemName: text("systemName") ?? "photo")
        case .hStack:
            HStack { children }
        case .vStack, .fragment, .group, .groupBox, .form, .lazyVGrid, .scrollViewReader:
            VStack { children }
        case .zStack:
            ZStack { children }
        case .spacer:
            Spacer()
        case .divider:
            Divider()
        case .progress:
            ProgressView()
        case .label:
            Label(text("title") ?? "", systemImage: text("systemImage") ?? "circle")
        case .markdown:
            Text(text("content") ?? text("text") ?? "")
        case .contentUnavailableView:
            ContentUnavailableView(text("title") ?? "Unavailable", systemImage: text("systemImage") ?? "tray")
        case .disclosureGroup, .controlGroup:
            VStack { children }
        case .slider:
            ProgressView(value: number("value"), total: number("max") ?? 1)
        case .button, .link, .menu, .toggle, .textField, .scrollView, .navigationStack, .navigationSplitView,
             .navigationLink, .navigationDestination, .picker, .svg, .tabView, .tab:
            Label("Open Hanlin", systemImage: "arrow.up.forward.app")
        case .chart, .barChart:
            VStack { children }
        case .circle:
            Circle().fill(.secondary)
        case .capsule:
            Capsule().fill(.secondary)
        case .rectangle:
            Rectangle().fill(.secondary)
        case .roundedRectangle:
            RoundedRectangle(cornerRadius: 12).fill(.secondary)
        case .presentation:
            EmptyView()
        }
    }

    @ViewBuilder
    private var children: some View {
        ForEach(Array(node.children.enumerated()), id: \.offset) { _, child in
            HanlinExtensionNodeView(node: child)
        }
    }

    private func text(_ key: String) -> String? {
        guard case let .string(value)? = node.properties[key] else { return nil }
        return value
    }

    private func number(_ key: String) -> Double? {
        switch node.properties[key] {
        case let .integer(value): Double(value)
        case let .number(value): value
        default: nil
        }
    }
}
