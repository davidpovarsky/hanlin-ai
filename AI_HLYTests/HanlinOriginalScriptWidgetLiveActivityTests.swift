import Foundation
#if os(iOS)
import ActivityKit
#endif
import Testing
import HanlinPlatformContracts
import HanlinScriptContracts
@testable import HanlinScriptExtensions

struct HanlinOriginalScriptWidgetLiveActivityTests {
    private func fixture() throws -> (URL, HanlinScriptExtensionStore, HanlinWidgetInstance) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hanlin-native-island-" + UUID().uuidString)
        let store = HanlinScriptExtensionStore(root: root)
        let identity = HanlinScriptExtensionIdentity(
            installedPackageID: try .init(validating: "installed.original-island"),
            packageID: try .init(validating: "package.original-island"), generation: 1, entrypointID: "island")
        let source = """
        async function $main() {
          const prior = $storage.get('count') || 0;
          if (__hanlinAction === 'increment') $storage.set('count', prior + 1);
          const count = $storage.get('count') || 0;
          const text = value => ScriptWidget.createElement('text', {}, [String(value)]);
          $render(text('Count ' + count));
          $dynamic_island({
            expanded: {leading: text('L' + count), trailing: text('T' + count),
                       center: text('C' + count), bottom: text('B' + count)},
            compactLeading: text('l' + count), compactTrailing: text('t' + count), minimal: text('m' + count)
          });
        }
        """
        let program = HanlinWidgetProgram(engine: .scriptwidget,
            sourceSHA256: String(repeating: "a", count: 64), compilerSHA256: String(repeating: "b", count: 64),
            javaScript: source, actions: [.init(id: "increment", kind: .function, handler: "increment")],
            families: ["systemMedium"])
        let artifact = try store.storeArtifact(data: JSONEncoder().encode(program),
            installedPackageID: identity.installedPackageID, generation: identity.generation)
        let template = HanlinScriptWidgetSnapshot(identity: identity, displayName: "Original island",
            family: "systemMedium", validUntil: .distantFuture, engine: .scriptwidget,
            payload: .scriptwidget(.init(script: "", scriptRef: artifact.ref, scriptSHA256: artifact.sha256)),
            root: .init(kind: .text))
        try store.publishWidgetTemplates([template], intentEntities: [], translationApps: [],
            installedPackageIDs: [identity.installedPackageID])
        return (root, store, try #require(try store.load()?.widgetInstances.first))
    }

    @Test func originalRegionsPersistOutsideActivityContentAndActionsProduceFreshSnapshots() throws {
        let (root, store, instance) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try HanlinScriptWidgetLiveActivityPreparation.prepare(store: store,
            entityID: instance.entityID, family: "systemMedium", values: ["count": .number(2)],
            revision: 1, title: "Original")
        let prepared = try HanlinScriptWidgetLiveActivityPreparation.load(
            store: store, attributes: first.attributes, state: first.state)
        let island = try #require(prepared.dynamicIsland)
        let pairs: [(HanlinScriptWidgetPreparedNode?, String)] = [
            (island.expandedLeading, "L2"), (island.expandedTrailing, "T2"),
            (island.expandedCenter, "C2"), (island.expandedBottom, "B2"),
            (island.compactLeading, "l2"), (island.compactTrailing, "t2"), (island.minimal, "m2")
        ]
        for (node, expected) in pairs {
            #expect(try #require(node).children == [.value(.string(expected))])
        }
        #expect(prepared.node.children == [.value(.string("Count 2"))])
        #expect(try JSONEncoder().encode(first.state).count < 4_096)
        #expect(!String(decoding: try JSONEncoder().encode(first.state), as: UTF8.self).contains("expandedLeading"))

        let receipt = try HanlinWidgetActionExecutor.perform(
            .init(context: prepared.context, actionID: "increment", nonce: "native-island-button"), store: store)
        #expect(receipt.applied)
        let second = try HanlinScriptWidgetLiveActivityPreparation.prepare(store: store,
            entityID: instance.entityID, family: "systemMedium", revision: 2, title: "Original")
        let updated = try HanlinScriptWidgetLiveActivityPreparation.load(
            store: store, attributes: second.attributes, state: second.state)
        #expect(updated.node.children == [.value(.string("Count 3"))])
        #expect(second.state.snapshotSHA256 != first.state.snapshotSHA256)
        let retained = try HanlinScriptWidgetLiveActivityPreparation.load(
            store: store, attributes: first.attributes, state: first.state)
        #expect(retained.node == prepared.node)
    }

    @Test func removedWidgetCannotProduceANewLiveActivitySnapshot() throws {
        let (root, store, instance) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.invalidateWidgetActions(installedPackageID: instance.identity.installedPackageID)
        #expect(throws: HanlinWidgetActionError.inactiveInstance) {
            try HanlinScriptWidgetLiveActivityPreparation.prepare(store: store,
                entityID: instance.entityID, family: "systemMedium", revision: 1, title: "Original")
        }
    }

#if os(iOS)
    @Test @MainActor
    func actualActivityKitStartsUpdatesAndEndsTheOriginalProgram() async throws {
        let (temporaryRoot, temporaryStore, originalInstance) = try fixture()
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let originalSnapshot = try #require(try temporaryStore.load())
        let originalTemplate = try #require(originalSnapshot.widgets.first)
        let (program, _) = try temporaryStore.loadProgram(for: originalTemplate)
        let store = try HanlinScriptExtensionStore()
        let installedID = try HanlinInstalledPackageID(validating: "installed.activity-" + UUID().uuidString.lowercased())
        let identity = HanlinScriptExtensionIdentity(installedPackageID: installedID,
            packageID: originalInstance.identity.packageID, generation: 1, entrypointID: "island")
        let instance = HanlinWidgetInstance(identity: identity, engine: .scriptwidget, displayName: "Original system activity")
        let artifact = try store.storeArtifact(data: JSONEncoder().encode(program), installedPackageID: installedID, generation: 1)
        let template = HanlinScriptWidgetSnapshot(identity: identity, displayName: instance.displayName,
            family: "systemMedium", validUntil: .distantFuture, engine: .scriptwidget,
            payload: .scriptwidget(.init(script: "", scriptRef: artifact.ref, scriptSHA256: artifact.sha256)),
            root: .init(kind: .text))
        try store.update { current in
            let current = current ?? HanlinScriptExtensionSnapshot(schemaVersion: 2, generatedAt: .now)
            return current.replacing(widgets: current.widgets + [template], instances: current.widgetInstances + [instance])
        }
        defer {
            _ = try? store.update { current in
                guard let current else { throw HanlinWidgetActionError.inactiveInstance }
                return current.replacing(
                    widgets: current.widgets.filter { $0.identity.installedPackageID != installedID },
                    instances: current.widgetInstances.filter { $0.identity.installedPackageID != installedID },
                    states: current.widgetStates.filter { $0.identity.installedPackageID != installedID })
            }
        }
        #expect(ActivityAuthorizationInfo().areActivitiesEnabled)
        let systemID = try await HanlinScriptWidgetLiveActivityController.start(store: store,
            entityID: instance.entityID, family: "systemMedium", title: "Original system activity", values: ["count": .number(4)])
        do {
            let activity = try #require(Activity<HanlinScriptWidgetLiveActivityAttributes>.activities.first { $0.id == systemID })
            #expect(activity.attributes.identity == identity)
            #expect(HanlinScriptWidgetLiveActivityController.activityIDs(installedPackageID: installedID.rawValue).contains(systemID))
            let updated = try await HanlinScriptWidgetLiveActivityController.update(store: store,
                systemActivityID: systemID, installedPackageID: installedID.rawValue, values: ["count": .number(9)])
            #expect(updated)
            #expect(activity.content.state.revision == 2)
            let rendered = try HanlinScriptWidgetLiveActivityPreparation.load(
                store: store, attributes: activity.attributes, state: activity.content.state)
            #expect(rendered.node.children == [.value(.string("Count 9"))])
            #expect(rendered.dynamicIsland?.minimal?.children == [.value(.string("m9"))])
            let ended = try await HanlinScriptWidgetLiveActivityController.end(store: store,
                systemActivityID: systemID, installedPackageID: installedID.rawValue, dismissAfterSeconds: 0)
            #expect(ended)
        } catch {
            _ = try? await HanlinScriptWidgetLiveActivityController.end(store: store,
                systemActivityID: systemID, installedPackageID: installedID.rawValue, dismissAfterSeconds: 0)
            throw error
        }
    }
#endif
}
