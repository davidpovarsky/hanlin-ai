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
        var seen: Set<String> = []
        return snapshot?.widgets.compactMap {
            let id = Self.id($0.identity)
            guard seen.insert(id).inserted else { return nil }
            return HanlinScriptPackageEntity(
                id: id,
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
        .init(date: .now, snapshot: selectedSnapshot(configuration, family: context.family))
    }

    func timeline(
        for configuration: HanlinWidgetConfigurationIntent,
        in context: Context
    ) async -> Timeline<HanlinWidgetEntry> {
        let selected = selectedSnapshot(configuration, family: context.family)
        let refresh = max(selected?.validUntil ?? Date.now.addingTimeInterval(900), .now)
        return Timeline(entries: [.init(date: .now, snapshot: selected)], policy: .after(refresh))
    }

    private func selectedSnapshot(
        _ configuration: HanlinWidgetConfigurationIntent,
        family: WidgetFamily
    ) -> HanlinScriptWidgetSnapshot? {
        guard let snapshots = try? HanlinScriptExtensionStore().load()?.widgets else { return nil }
        let familyName = switch family {
        case .systemSmall: "systemSmall"
        case .systemMedium: "systemMedium"
        case .systemLarge: "systemLarge"
        case .systemExtraLarge: "systemExtraLarge"
        case .accessoryCircular: "accessoryCircular"
        case .accessoryRectangular: "accessoryRectangular"
        case .accessoryInline: "accessoryInline"
        @unknown default: "systemMedium"
        }
        if let selected = configuration.package {
            return snapshots.first {
                HanlinScriptPackageEntityQuery.id($0.identity) == selected.id && $0.family == familyName
            }
        }
        return snapshots.first { $0.family == familyName }
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
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}

struct HanlinScriptingLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HanlinGenericLiveActivityAttributes.self) { context in
            HanlinLiveActivityLockScreenView(root: context.state.root)
                .padding()
                .activityBackgroundTint(Color.clear)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HanlinLiveActivityRegionView(root: context.state.root, region: .expandedLeading)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    HanlinLiveActivityRegionView(root: context.state.root, region: .expandedTrailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    HanlinLiveActivityRegionView(root: context.state.root, region: .expandedCenter)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HanlinLiveActivityRegionView(root: context.state.root, region: .expandedBottom)
                }
            } compactLeading: {
                HanlinLiveActivityRegionView(root: context.state.root, region: .compactLeading)
            } compactTrailing: {
                HanlinLiveActivityRegionView(root: context.state.root, region: .compactTrailing)
            } minimal: {
                HanlinLiveActivityRegionView(root: context.state.root, region: .minimal)
            }
        }
    }
}

private struct HanlinLiveActivityLockScreenView: View {
    let root: HanlinScriptUINode

    var body: some View {
        if let layout = try? HanlinLiveActivityUILayout(root: root) {
            HanlinExtensionNodeView(node: layout.content)
        } else {
            HanlinExtensionNodeView(node: root)
        }
    }
}

private struct HanlinLiveActivityRegionView: View {
    enum Region {
        case compactLeading
        case compactTrailing
        case minimal
        case expandedLeading
        case expandedTrailing
        case expandedCenter
        case expandedBottom
    }

    let root: HanlinScriptUINode
    let region: Region

    @ViewBuilder
    var body: some View {
        if let layout = try? HanlinLiveActivityUILayout(root: root), let node = node(in: layout) {
            HanlinExtensionNodeView(node: node)
        } else {
            EmptyView()
        }
    }

    private func node(in layout: HanlinLiveActivityUILayout) -> HanlinScriptUINode? {
        switch region {
        case .compactLeading: layout.compactLeading
        case .compactTrailing: layout.compactTrailing
        case .minimal: layout.minimal
        case .expandedLeading: layout.expandedLeading
        case .expandedTrailing: layout.expandedTrailing
        case .expandedCenter: layout.expandedCenter
        case .expandedBottom: layout.expandedBottom
        }
    }
}

private struct HanlinExtensionSnapshotView: View {
    let snapshot: HanlinScriptWidgetSnapshot?

    var body: some View {
        if let snapshot {
            HanlinExtensionNodeView(
                node: snapshot.root,
                identity: snapshot.actionIdentity ?? snapshot.identity
            )
        } else {
            ContentUnavailableView("Choose a Script Package", systemImage: "curlybraces.square")
        }
    }
}
