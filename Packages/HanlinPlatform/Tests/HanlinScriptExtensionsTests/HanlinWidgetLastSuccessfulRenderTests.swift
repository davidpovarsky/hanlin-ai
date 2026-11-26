import Foundation
import HanlinPlatformContracts
import HanlinScriptContracts
import HanlinScriptUI
@testable import HanlinScriptExtensions
import Testing

@Suite("Prepared widget last successful render", .serialized)
struct HanlinWidgetLastSuccessfulRenderTests {
    @Test(arguments: [HanlinPlatformContracts.HanlinWidgetEngine.expo, .scriptwidget])
    func failedRefreshRetainsVerifiedRenderAndDoesNotCommitStagedState(engine: HanlinPlatformContracts.HanlinWidgetEngine) throws {
        let fixture = try RenderFixture(engine: engine)
        defer { fixture.remove() }
        let first = fixture.prepare()
        let expected = try #require(first.cachedNode)
        let successful = try #require(try fixture.store.load())
        #expect(successful.widgetLastSuccessfulRenders.count == 1)
        try fixture.failNextRender()
        let before = try #require(try fixture.store.load())
        let fallback = fixture.prepare()
        #expect(fallback.cachedNode == expected)
        #expect(try fixture.store.load() == before, "Failed refresh must not commit staged script state or refresh its success timestamp")
        #expect(try fixture.store.load()?.widgetStates.first?.values["staged"] == nil)
        try fixture.store.publishWidgetTemplates([fixture.widget], intentEntities: [], translationApps: [],
            installedPackageIDs: [fixture.widget.identity.installedPackageID])
        #expect(try fixture.store.load()?.widgetLastSuccessfulRenders == successful.widgetLastSuccessfulRenders)
        #expect(fixture.prepare().cachedNode == expected, "Host republish must retain the last successful render")
    }

    enum Invalidation: CaseIterable, Sendable {
        case settings, inactive, removed, generation, program, family, expired
    }

    @Test(arguments: Invalidation.allCases)
    func fallbackNeverRestoresRevokedOrMismatchedContent(invalidation: Invalidation) throws {
        let fixture = try RenderFixture(engine: .scriptwidget)
        defer { fixture.remove() }
        _ = try #require(fixture.prepare().cachedNode)
        try fixture.failNextRender()
        try fixture.invalidate(invalidation)
        let output = fixture.prepare(family: invalidation == .family ? "systemLarge" : "systemMedium")
        guard case .failure = output else {
            Issue.record("Last successful render crossed a current authority or settings boundary: \(invalidation)")
            return
        }
    }

    @Test func corruptRenderBytesAreRejectedAndUninstallDropsCacheReferences() throws {
        let fixture = try RenderFixture(engine: .scriptwidget)
        defer { fixture.remove() }
        _ = try #require(fixture.prepare().cachedNode)
        let record = try #require(try fixture.store.load()?.widgetLastSuccessfulRenders.first)
        try Data("corrupt render".utf8).write(to: fixture.store.root.appending(path: record.renderRef))
        try fixture.failNextRender()
        guard case .failure = fixture.prepare() else {
            Issue.record("Corrupt cached render was accepted")
            return
        }
        try fixture.store.publishWidgetTemplates([], intentEntities: [], translationApps: [], installedPackageIDs: [])
        #expect(try fixture.store.load()?.widgetLastSuccessfulRenders.isEmpty == true)
    }

    @Test func precedingSnapshotWithoutRenderMetadataDecodesAndCopiesPreserveMetadata() throws {
        let fixture = try RenderFixture(engine: .expo)
        defer { fixture.remove() }
        _ = try #require(fixture.prepare().cachedNode)
        let snapshot = try #require(try fixture.store.load())
        let data = try JSONEncoder().encode(snapshot)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "widgetLastSuccessfulRenders")
        let preceding = try JSONDecoder().decode(HanlinScriptExtensionSnapshot.self,
            from: JSONSerialization.data(withJSONObject: object))
        #expect(preceding.widgetLastSuccessfulRenders.isEmpty)
        #expect(snapshot.replacing(states: []).widgetLastSuccessfulRenders == snapshot.widgetLastSuccessfulRenders)
        #expect(try JSONDecoder().decode(HanlinScriptExtensionSnapshot.self, from: data) == snapshot)
    }
}

private extension HanlinPreparedWidget {
    var cachedNode: HanlinCachedWidgetNode? {
        switch self {
        case let .expo(node, _): .expo(node)
        case let .scriptwidget(node, _): .scriptwidget(node)
        case .legacy, .failure: nil
        }
    }
}

private struct RenderFixture {
    let store: HanlinScriptExtensionStore
    let widget: HanlinScriptWidgetSnapshot
    let program: HanlinWidgetProgram
    var entityID: String {
        HanlinWidgetInstance(identity: widget.identity, engine: widget.engine, displayName: "Default").entityID
    }

    init(engine: HanlinPlatformContracts.HanlinWidgetEngine) throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Hanlin-LKG-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = .init(root: root)
        let identity = HanlinScriptExtensionIdentity(installedPackageID: try .init(validating: "installed.lkg"),
            packageID: try .init(validating: "package.lkg"), generation: 1, entrypointID: "widget")
        let source = engine == .expo
            ? "function(props) { if (props.fail) throw new Error('refresh unavailable'); return {type:'TextView',props:{children:'Last success'}}; }"
            : "async function $main() { if ($storage.get('fail')) { $storage.set('staged',true); throw new Error('refresh unavailable'); } $render(ScriptWidget.createElement('text', {}, 'Last success')); }"
        program = .init(engine: engine, sourceSHA256: String(repeating: "a", count: 64),
            compilerSHA256: String(repeating: "b", count: 64), javaScript: source,
            actions: [], families: ["systemMedium"])
        let artifact = try store.storeArtifact(data: JSONEncoder().encode(program),
            installedPackageID: identity.installedPackageID, generation: identity.generation)
        let payload: HanlinWidgetPayload = engine == .expo
            ? .expo(.init(layout: "", layoutRef: artifact.ref, layoutSHA256: artifact.sha256))
            : .scriptwidget(.init(script: "", scriptRef: artifact.ref, scriptSHA256: artifact.sha256))
        widget = .init(identity: identity, displayName: "Last good render", validUntil: .distantFuture,
            engine: engine, payload: payload, root: .init(kind: .text))
        try store.publishWidgetTemplates([widget], intentEntities: [], translationApps: [],
            installedPackageIDs: [identity.installedPackageID])
    }

    func remove() { try? FileManager.default.removeItem(at: store.root) }

    func prepare(family: String = "systemMedium") -> HanlinPreparedWidget {
        HanlinWidgetPreparation.prepare(store: store, entityID: entityID, family: family)
    }

    func failNextRender() throws {
        let (_, digest) = try store.loadProgram(for: widget)
        try store.update { snapshot in
            let snapshot = try #require(snapshot)
            return snapshot.replacing(states: [.init(identity: widget.identity, engine: widget.engine,
                artifactSHA256: digest, revision: 1, values: ["fail": .bool(true)])])
        }
    }

    func invalidate(_ kind: HanlinWidgetLastSuccessfulRenderTests.Invalidation) throws {
        try store.update { value in
            let snapshot = try #require(value)
            switch kind {
            case .settings:
                let current = try #require(snapshot.widgetInstances.first)
                return snapshot.replacing(instances: [.init(identity: current.identity, engine: current.engine,
                    displayName: current.displayName, settings: ["location": .string("changed")])])
            case .inactive:
                return snapshot.replacing(inactiveInstallations: [widget.identity.installedPackageID.rawValue])
            case .removed:
                return snapshot.replacing(widgets: [], instances: [])
            case .generation:
                let identity = HanlinScriptExtensionIdentity(installedPackageID: widget.identity.installedPackageID,
                    packageID: widget.identity.packageID, generation: 2, entrypointID: widget.identity.entrypointID)
                let replacement = HanlinScriptWidgetSnapshot(identity: identity, displayName: widget.displayName,
                    validUntil: .distantFuture, engine: widget.engine, payload: widget.payload, root: widget.root)
                return snapshot.replacing(widgets: [replacement],
                    instances: [.init(identity: identity, engine: widget.engine, displayName: "Default")])
            case .program:
                let changed = HanlinWidgetProgram(engine: program.engine, sourceSHA256: program.sourceSHA256,
                    compilerSHA256: program.compilerSHA256, javaScript: program.javaScript + "\n// new program",
                    actions: program.actions, families: program.families)
                let artifact = try store.storeArtifact(data: JSONEncoder().encode(changed),
                    installedPackageID: widget.identity.installedPackageID, generation: widget.identity.generation)
                let replacement = HanlinScriptWidgetSnapshot(identity: widget.identity, displayName: widget.displayName,
                    validUntil: .distantFuture, engine: widget.engine,
                    payload: .scriptwidget(.init(script: "", scriptRef: artifact.ref, scriptSHA256: artifact.sha256)), root: widget.root)
                return snapshot.replacing(widgets: [replacement], states: [.init(identity: widget.identity, engine: widget.engine,
                    artifactSHA256: artifact.sha256, revision: 1, values: ["fail": .bool(true)])])
            case .family: return snapshot
            case .expired:
                return snapshot.replacing(widgets: [.init(identity: widget.identity, displayName: widget.displayName,
                    validUntil: .distantPast, engine: widget.engine, payload: widget.payload, root: widget.root)])
            }
        }
    }
}
