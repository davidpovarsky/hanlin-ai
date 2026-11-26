import HanlinExtensionContracts
import HanlinLocalization
import ActivityKit
import AppIntents
import HanlinExpoWidgetNative
import HanlinPlatformContracts
import HanlinScriptExtensions
import HanlinScriptUI
import SwiftUI
import WidgetKit

public struct HanlinScriptPackageEntity: AppEntity {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("Widget instance", table: "HanlinAppIntents"))
    public static let defaultQuery = HanlinScriptPackageEntityQuery()
    public let id: String
    public let displayName: String
    public let identity: HanlinScriptExtensionIdentity
    public var displayRepresentation: DisplayRepresentation { .init(title: "\(displayName)") }

    public init(from selectable: HanlinSelectableWidgetEntity) {
        self.id = selectable.id
        self.displayName = selectable.displayName
        self.identity = selectable.identity
    }

    public init(id: String, displayName: String, identity: HanlinScriptExtensionIdentity) {
        self.id = id
        self.displayName = displayName
        self.identity = identity
    }
}

public struct HanlinScriptPackageEntityQuery: EnumerableEntityQuery, EntityStringQuery {
    public init() {}

    public func entities(for identifiers: [String]) async throws -> [HanlinScriptPackageEntity] {
        do {
            let store = try HanlinScriptExtensionStore()
            let snapshot = try store.load()
            let available = snapshot?.selectableWidgetEntities() ?? []
            let availableMap = Dictionary(uniqueKeysWithValues: available.map { ($0.id, $0) })
            var results: [HanlinScriptPackageEntity] = []
            for id in identifiers {
                let resolved = snapshot?.widgetEntityMigrations[id] ?? id
                if let entity = availableMap[resolved] {
                    results.append(HanlinScriptPackageEntity(from: entity))
                }
            }
            return results
        } catch {
            HanlinScriptExtensionStore.recordQueryDiagnostic(error: error, phase: .widgetExtensionEntityQuery)
            throw error
        }
    }

    public func suggestedEntities() async throws -> [HanlinScriptPackageEntity] {
        do {
            let store = try HanlinScriptExtensionStore()
            let snapshot = try store.load()
            return (snapshot?.selectableWidgetEntities() ?? []).map { HanlinScriptPackageEntity(from: $0) }
        } catch {
            HanlinScriptExtensionStore.recordQueryDiagnostic(error: error, phase: .widgetExtensionEntityQuery)
            throw error
        }
    }

    public func allEntities() async throws -> [HanlinScriptPackageEntity] {
        try await suggestedEntities()
    }

    public func entities(matching string: String) async throws -> [HanlinScriptPackageEntity] {
        let all = try await suggestedEntities()
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return all }
        return all.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
        }
    }
}

public struct HanlinWidgetConfigurationIntent: WidgetConfigurationIntent {
    public static let title = LocalizedStringResource("Widget instance", table: "HanlinAppIntents")
    public static let description = IntentDescription(LocalizedStringResource("Choose an installed instance. Placements using the same instance share state.", table: "HanlinAppIntents"))

    @Parameter(title: LocalizedStringResource("Widget instance", table: "HanlinAppIntents"))
    public var package: HanlinScriptPackageEntity?

    public init() {}

    public init(package: HanlinScriptPackageEntity?) {
        self.package = package
    }
}
public struct HanlinWidgetEntry: TimelineEntry {
    public init(date: Date, presentation: HanlinPreparedWidget) {
        self.date = date; self.presentation = presentation
    }

    public let date: Date
    public let presentation: HanlinPreparedWidget
}
public struct HanlinWidgetTimelineProvider: AppIntentTimelineProvider {
    public init() {}

    public func placeholder(in context: Context) -> HanlinWidgetEntry { .init(date: .now, presentation: .failure("Choose a widget instance")) }
    public func snapshot(for configuration: HanlinWidgetConfigurationIntent, in context: Context) async -> HanlinWidgetEntry { await prepare(configuration, family: context.family) }
    public func timeline(for configuration: HanlinWidgetConfigurationIntent, in context: Context) async -> Timeline<HanlinWidgetEntry> {
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
            } catch {
                if let diag = HanlinScriptExtensionStore.latestDiagnostic {
                    return HanlinPreparedWidget.failure("\(diag.userFacingHeadline) (\(diag.correlationID))")
                }
                return HanlinPreparedWidget.failure("Widget storage failed")
            }
        }.value
        return .init(date: .now, presentation: presentation)
    }
}
public struct HanlinScriptingWidget: Widget {
    public let kind: String

    /// WidgetKit requires a zero-argument initializer. It uses only this
    /// extension's declared host configuration; it never selects Hanlin's kind.
    public init() {
        do {
            self.kind = try HanlinExtensionHostConfiguration.load().requireWidgetKind()
        } catch {
            preconditionFailure("HanlinScriptingWidget requires HanlinExtensionHost.WidgetKind in the extension's Info.plist.")
        }
    }

    public init(kind: String) { self.kind = kind }
    public var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: HanlinWidgetConfigurationIntent.self, provider: HanlinWidgetTimelineProvider()) { entry in
            HanlinExtensionSnapshotView(presentation: entry.presentation)
                .modifier(PassiveLegacyWidgetURL(url: entry.presentation.passiveLegacyURL))
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName(Text("Hanlin Script", bundle: HanlinLocalization.bundle))
        .description(Text("Native widgets from installed packages. Create independent instances in Hanlin.", bundle: HanlinLocalization.bundle))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}
private struct PassiveLegacyWidgetURL: ViewModifier {
    let url: URL?
    @ViewBuilder func body(content: Content) -> some View {
        if let url { content.widgetURL(url) }
        else { content }
    }
}
public struct HanlinScriptingLiveActivityWidget: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: HanlinGenericLiveActivityAttributes.self) { context in
            HanlinLiveActivityLockScreenView(root: context.state.root, identity: context.attributes.actionIdentity)
                .padding()
                .activityBackgroundTint(Color.clear)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HanlinLiveActivityRegionView(root: context.state.root, region: .expandedLeading, identity: context.attributes.actionIdentity)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    HanlinLiveActivityRegionView(root: context.state.root, region: .expandedTrailing, identity: context.attributes.actionIdentity)
                }
                DynamicIslandExpandedRegion(.center) {
                    HanlinLiveActivityRegionView(root: context.state.root, region: .expandedCenter, identity: context.attributes.actionIdentity)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HanlinLiveActivityRegionView(root: context.state.root, region: .expandedBottom, identity: context.attributes.actionIdentity)
                }
            } compactLeading: {
                HanlinLiveActivityRegionView(root: context.state.root, region: .compactLeading, identity: context.attributes.actionIdentity)
            } compactTrailing: {
                HanlinLiveActivityRegionView(root: context.state.root, region: .compactTrailing, identity: context.attributes.actionIdentity)
            } minimal: {
                HanlinLiveActivityRegionView(root: context.state.root, region: .minimal, identity: context.attributes.actionIdentity)
            }
        }
    }
}

public struct HanlinLiveActivityLockScreenView: View {
    public init(root: HanlinScriptUINode, identity: HanlinScriptExtensionIdentity? = nil) {
        self.root = root; self.identity = identity
    }

    public let root: HanlinScriptUINode
    public let identity: HanlinScriptExtensionIdentity?

    public var body: some View {
        if let layout = try? HanlinLiveActivityUILayout(root: root) {
            HanlinExtensionNodeView(node: layout.content, identity: identity, invocationSource: .liveActivity)
        } else {
            HanlinExtensionNodeView(node: root, identity: identity, invocationSource: .liveActivity)
        }
    }
}

public struct HanlinLiveActivityRegionView: View {
    public init(root: HanlinScriptUINode, region: Region, identity: HanlinScriptExtensionIdentity? = nil) {
        self.root = root; self.region = region; self.identity = identity
    }

    public enum Region: Sendable, CaseIterable {
        case compactLeading
        case compactTrailing
        case minimal
        case expandedLeading
        case expandedTrailing
        case expandedCenter
        case expandedBottom
    }

    public let root: HanlinScriptUINode
    public let region: Region
    public let identity: HanlinScriptExtensionIdentity?

    @ViewBuilder
    public var body: some View {
        if let layout = try? HanlinLiveActivityUILayout(root: root), let node = node(in: layout) {
            HanlinExtensionNodeView(node: node, identity: identity, invocationSource: .liveActivity)
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

public struct HanlinExtensionSnapshotView: View {
    public init(presentation: HanlinPreparedWidget) { self.presentation = presentation }

    public let presentation: HanlinPreparedWidget
    @ViewBuilder public var body: some View {
        switch presentation {
        case let .legacy(snapshot): HanlinExtensionNodeView(node: snapshot.root, identity: snapshot.actionIdentity ?? snapshot.identity)
        case let .expo(node, context):
            HanlinExpoWidgetsDynamicView(node: node, context: context) { node, context in
                HanlinPreparedExpoNativeView(node: node, context: context)
            }
        case let .scriptwidget(node, context): HanlinScriptWidgetDynamicView(node: node, context: context)
        case let .failure(reason): ContentUnavailableView(hanlin: "Hanlin Widget", systemImage: "exclamationmark.triangle", description: Text(reason))
        }
    }
}
public struct HanlinPreparedExpoNativeView: View {
    public init(node: HanlinValue, context: HanlinWidgetActionContext) {
        self.node = node; self.context = context
    }

    public let node: HanlinValue
    public let context: HanlinWidgetActionContext
    @ViewBuilder public var body: some View {
        if let object = node.toAny() as? [String: Any] {
            let child = HanlinExpoWidgetNative.render(node: object, resources: context.resources) { target, role, label in
                if let intent = try? HanlinExpoWidgetsViewRenderer.hostActionIntent(target: target, context: context) {
                    return AnyView(SwiftUI.Button(role: role, intent: intent) { label })
                }
                guard let intent = try? HanlinExpoWidgetsViewRenderer.actionIntent(target: target, context: context) else {
                    return AnyView(label.disabled(true).accessibilityHint(Text("Widget action is unavailable", bundle: HanlinLocalization.bundle)))
                }
                return AnyView(SwiftUI.Button(role: role, intent: intent) { label })
            }
            AnyView(child)
        } else { Text("Invalid prepared Expo widget", bundle: HanlinLocalization.bundle) }
    }
}

public struct HanlinOriginalScriptWidgetLiveActivityWidget: Widget {
    public init() {}
    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: HanlinScriptWidgetLiveActivityAttributes.self) { context in
            HanlinOriginalScriptWidgetActivityView(attributes: context.attributes, state: context.state)
                .padding().activityBackgroundTint(Color.clear)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HanlinOriginalScriptWidgetActivityView(attributes: context.attributes, state: context.state, region: .expandedLeading)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    HanlinOriginalScriptWidgetActivityView(attributes: context.attributes, state: context.state, region: .expandedTrailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    HanlinOriginalScriptWidgetActivityView(attributes: context.attributes, state: context.state, region: .expandedCenter)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HanlinOriginalScriptWidgetActivityView(attributes: context.attributes, state: context.state, region: .expandedBottom)
                }
            } compactLeading: {
                HanlinOriginalScriptWidgetActivityView(attributes: context.attributes, state: context.state, region: .compactLeading)
            } compactTrailing: {
                HanlinOriginalScriptWidgetActivityView(attributes: context.attributes, state: context.state, region: .compactTrailing)
            } minimal: {
                HanlinOriginalScriptWidgetActivityView(attributes: context.attributes, state: context.state, region: .minimal)
            }
        }
    }
}

/// Uses the actual original ScriptWidget renderer for every island region.
public struct HanlinOriginalScriptWidgetActivityView: View {
    public enum Region: CaseIterable, Sendable {
        case expandedLeading, expandedTrailing, expandedCenter, expandedBottom
        case compactLeading, compactTrailing, minimal
    }
    public let attributes: HanlinScriptWidgetLiveActivityAttributes
    public let state: HanlinScriptWidgetLiveActivityAttributes.ContentState
    public let region: Region?
    public init(attributes: HanlinScriptWidgetLiveActivityAttributes,
                state: HanlinScriptWidgetLiveActivityAttributes.ContentState, region: Region? = nil) {
        self.attributes = attributes
        self.state = state
        self.region = region
    }
    @ViewBuilder public var body: some View {
        if let store = try? HanlinScriptExtensionStore(),
           let prepared = try? HanlinScriptWidgetLiveActivityPreparation.load(
                store: store, attributes: attributes, state: state),
           let node = node(in: prepared) {
            HanlinScriptWidgetElementView(node: node, context: prepared.context)
        } else if region == nil {
            Text(state.title)
        }
    }
    public func node(in prepared: HanlinScriptWidgetLiveActivitySnapshot) -> HanlinScriptWidgetPreparedNode? {
        guard let region else { return prepared.node }
        guard let island = prepared.dynamicIsland else { return nil }
        switch region {
        case .expandedLeading: return island.expandedLeading
        case .expandedTrailing: return island.expandedTrailing
        case .expandedCenter: return island.expandedCenter
        case .expandedBottom: return island.expandedBottom
        case .compactLeading: return island.compactLeading
        case .compactTrailing: return island.compactTrailing
        case .minimal: return island.minimal
        }
    }
}
