import ActivityKit
import AppIntents
import HanlinExpoWidgetNative
import HanlinPlatformContracts
import HanlinScriptExtensions
import HanlinScriptUI
import SwiftUI
import WidgetKit

@main
struct HanlinScriptingWidgetBundle: WidgetBundle {
    var body: some Widget { HanlinScriptingWidget(); HanlinScriptingLiveActivityWidget() }
}
struct HanlinScriptPackageEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Widget instance")
    static let defaultQuery = HanlinScriptPackageEntityQuery()
    let id: String
    let displayName: String
    let identity: HanlinScriptExtensionIdentity
    var displayRepresentation: DisplayRepresentation { .init(title: "\(displayName)") }
}
struct HanlinScriptPackageEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [HanlinScriptPackageEntity] {
        let snapshot = try HanlinScriptExtensionStore().load()
        let resolved = Set(identifiers.map { snapshot?.widgetEntityMigrations[$0] ?? $0 })
        return availableEntities(snapshot).filter { resolved.contains($0.id) }
    }
    func suggestedEntities() async throws -> [HanlinScriptPackageEntity] { availableEntities(try HanlinScriptExtensionStore().load()) }
    private func availableEntities(_ snapshot: HanlinScriptExtensionSnapshot?) -> [HanlinScriptPackageEntity] {
        guard let snapshot else { return [] }
        var seen: Set<String> = []
        return snapshot.widgets.compactMap { widget in
            guard !snapshot.inactiveWidgetInstallations.contains(widget.identity.installedPackageID.rawValue) else { return nil }
            let instance = HanlinWidgetInstance(identity: widget.identity, engine: widget.engine, displayName: widget.displayName)
            guard seen.insert(instance.entityID).inserted else { return nil }
            return .init(id: instance.entityID, displayName: "\(widget.displayName) · \(widget.engine.rawValue) · \(widget.identity.installedPackageID.rawValue)", identity: widget.identity)
        }
    }
}
struct HanlinWidgetConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Widget instance"
    static let description = IntentDescription("Choose an installed instance. Placements using the same instance share state.")
    @Parameter(title: "Widget instance") var package: HanlinScriptPackageEntity?
}
struct HanlinWidgetEntry: TimelineEntry {
    let date: Date
    let presentation: HanlinPreparedWidget
}
struct HanlinWidgetTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> HanlinWidgetEntry { .init(date: .now, presentation: .failure("Choose a widget instance")) }
    func snapshot(for configuration: HanlinWidgetConfigurationIntent, in context: Context) async -> HanlinWidgetEntry { await prepare(configuration, family: context.family) }
    func timeline(for configuration: HanlinWidgetConfigurationIntent, in context: Context) async -> Timeline<HanlinWidgetEntry> {
        let entry = await prepare(configuration, family: context.family)
        return Timeline(entries: [entry], policy: .after(entry.date.addingTimeInterval(900)))
    }
    private func prepare(_ configuration: HanlinWidgetConfigurationIntent, family: WidgetFamily) async -> HanlinWidgetEntry {
        guard let id = configuration.package?.id else { return .init(date: .now, presentation: .failure("Choose a widget instance")) }
        let familyName: String
        switch family {
        case .systemSmall: familyName = "systemSmall"
        case .systemMedium: familyName = "systemMedium"
        case .systemLarge: familyName = "systemLarge"
        case .systemExtraLarge: familyName = "systemExtraLarge"
        default: return .init(date: .now, presentation: .failure("Unsupported widget family"))
        }
        let presentation = await Task.detached(priority: .userInitiated) {
            do {
                let store = try HanlinScriptExtensionStore()
                let snapshot = try store.load()
                let resolved = snapshot?.widgetEntityMigrations[id] ?? id
                return HanlinWidgetPreparation.prepare(store: store, entityID: resolved, family: familyName)
            } catch { return HanlinPreparedWidget.failure("Widget storage failed: \(error)") }
        }.value
        return .init(date: .now, presentation: presentation)
    }
}
struct HanlinScriptingWidget: Widget {
    let kind = HanlinWidgetActionExecutor.widgetKind
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: HanlinWidgetConfigurationIntent.self, provider: HanlinWidgetTimelineProvider()) { entry in
            HanlinExtensionSnapshotView(presentation: entry.presentation).containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Hanlin Script")
        .description("Native widgets from installed packages. Create independent instances in Hanlin.")
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
    let presentation: HanlinPreparedWidget
    @ViewBuilder var body: some View {
        switch presentation {
        case let .legacy(snapshot): HanlinExtensionNodeView(node: snapshot.root, identity: snapshot.actionIdentity ?? snapshot.identity)
        case let .expo(node, context):
            HanlinExpoWidgetsDynamicView(node: node, context: context) { node, context in
                HanlinPreparedExpoNativeView(node: node, context: context)
            }
        case let .scriptwidget(node, context): HanlinScriptWidgetDynamicView(node: node, context: context)
        case let .failure(reason): ContentUnavailableView("Hanlin Widget", systemImage: "exclamationmark.triangle", description: Text(reason))
        }
    }
}
private struct HanlinPreparedExpoNativeView: View {
    let node: HanlinValue
    let context: HanlinWidgetActionContext
    @ViewBuilder var body: some View {
        if let object = node.toAny() as? [String: Any] {
            let child = HanlinExpoWidgetNative.render(node: object) { target, role, label in
                guard let intent = try? HanlinExpoWidgetsViewRenderer.actionIntent(target: target, context: context) else {
                    return AnyView(label.disabled(true).accessibilityHint("Widget action is unavailable"))
                }
                return AnyView(SwiftUI.Button(role: role, intent: intent) { label })
            }
            AnyView(child)
        } else { Text("Invalid prepared Expo widget") }
    }
}
