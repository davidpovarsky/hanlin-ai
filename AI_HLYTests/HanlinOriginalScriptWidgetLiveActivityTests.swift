import Foundation
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
}
