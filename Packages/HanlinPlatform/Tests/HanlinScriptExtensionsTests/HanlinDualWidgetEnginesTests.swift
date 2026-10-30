import CryptoKit
import Foundation
import HanlinPlatformContracts
import HanlinScriptCompiler
import HanlinScriptContracts
import HanlinScriptStore
import HanlinScriptUI
import HanlinLegacyWidgetStoreFixture
@testable import HanlinScriptExtensions
import Testing
import SwiftUI

private typealias Store = HanlinScriptExtensions.HanlinScriptExtensionStore
private typealias Snapshot = HanlinScriptExtensions.HanlinScriptExtensionSnapshot
private typealias Identity = HanlinScriptExtensions.HanlinScriptExtensionIdentity
private typealias Widget = HanlinScriptExtensions.HanlinScriptWidgetSnapshot

@Suite("Pass 3 installed widget programs, actions and transactions")
struct HanlinDualWidgetEnginesTests {
    @Test func originalScriptWidgetImportedHelpersAndVerifiedFileStorage() throws {
        let program = HanlinWidgetProgram(engine: .scriptwidget,
            sourceSHA256: String(repeating: "a", count: 64), compilerSHA256: String(repeating: "b", count: 64),
            javaScript: """
              async function $main() {
                if (!$import('helper.js')) throw Error('helper not found');
                if ($storage.getString('missing') !== '') throw Error('upstream string default');
                if (!$storage.compareAndSetString('mode', '', 'verified')) throw Error('CAS failed');
                $storage.setJSON('payload', $file.readJSON('payload.json'));
                $render(ScriptWidget.createElement('text', {}, helper($storage.getString('mode'))));
              }
              """, actions: [], families: ["systemMedium"],
            resources: ["payload.json": Data(#"{"count":9}"#.utf8)],
            imports: ["helper.js": "function helper(value) { return 'Imported ' + value; }"])
        let result = try HanlinScriptWidgetRuntime.shared.run(program: program, values: [:], environment: [:])
        #expect(result.node.tag == "text")
        #expect(result.node.children == [.value(.string("Imported verified"))])
        #expect(result.values["mode"] == .string("verified"))
        #expect(result.values["payload"]?.toAny() as? [String: Int] == ["count": 9])
    }
    @Test(arguments: ["Hanlin-Expo-Widget-Counter.hanlinExpo", "Hanlin-Expo-Widget-Visuals.hanlinExpo", "Hanlin-ScriptWidget-Dashboard.scripting", "Hanlin-ScriptWidget-Actions.scripting", "Hanlin-Widget-Legacy-Regression.scripting", "Hanlin-Mixed-Native-Widget.hanlinExpo", "Hanlin-Widget-Invalid-Cases.hanlinExpo"])
    func realArchiveImport(name: String) throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let staged = try HanlinPackageCenter().stageAndInspect(sourceURL: fixtureURL(name), stagingParent: root)
        let preview = try HanlinScriptAnalyzer(inventory: inventory).analyze(staged)
        let expected = !name.contains("Invalid") && !name.contains("Mixed")
        #expect(preview.canInstall == expected, "\(preview.findings)")
        if expected {
            let entry = try #require(preview.entrypoints.first)
            #expect(preview.entrypoints.count == 1)
            #expect(entry.kind == .widget)
            #expect(entry.widgetEngine?.rawValue == (name.contains("Legacy") ? "legacy" : name.contains("ScriptWidget") ? "scriptwidget" : "expo"))
            let encoded = try JSONEncoder().encode(entry)
            #expect(try JSONDecoder().decode(HanlinPackageEntrypointDescriptor.self, from: encoded).widgetEngine == entry.widgetEngine)
        }
    }

    @Test(arguments: ["Hanlin-Expo-Widget-Counter.hanlinExpo", "Hanlin-ScriptWidget-Actions.scripting"])
    func installAndVerifiedLoader(name: String) async throws {
        let fixture = try await InstalledFixture(name)
        defer { fixture.remove() }
        let snapshot = try #require(try fixture.store.load())
        let widget = try #require(snapshot.widgets.first)
        let (program, _) = try fixture.store.loadProgram(for: widget)
        #expect(program.engine == widget.engine)
        #expect(widget.identity.generation == 1)
        #expect(try await fixture.installed.snapshots().first?.entrypoints.first?.widgetEngine == widget.engine)
        let reopened = Store(root: fixture.extensionRoot)
        #expect(try reopened.load() == snapshot)
    }

    @MainActor @Test
    func emittedExpoIntentCarriesVerifiedIdentityAndCallsSource() async throws {
        let fixture = try await InstalledFixture("Hanlin-Expo-Widget-Counter.hanlinExpo")
        defer { fixture.remove() }
        let context = try fixture.context()
        // This factory is the exact path called by the original native renderer's
        // injected Button builder. Actual SpringBoard tapping is a separate UI gate.
        let intent = try HanlinExpoWidgetsViewRenderer.actionIntent(target: "increment", context: context)
        let command = try JSONDecoder().decode(HanlinWidgetActionCommand.self, from: Data(intent.commandJSON.utf8))
        #expect(command.context.engine == .expo)
        #expect(command.context.identity == fixture.identity)
        #expect(command.context.artifactSHA256 == context.artifactSHA256)
        _ = try HanlinWidgetActionExecutor.perform(command, store: fixture.store)
        #expect(try fixture.values()["count"] == .integer(8))
        _ = try HanlinWidgetActionExecutor.perform(.init(context: context, actionID: "decrement"), store: fixture.store)
        #expect(try fixture.values()["count"] == .integer(7))
        _ = try HanlinWidgetActionExecutor.perform(.init(context: context, actionID: "status"), store: fixture.store)
        #expect(try fixture.values()["status"] == .string("Source callback ran"))
        #expect(try fixture.values()["trace"] == .string("status-handler"))
        #expect(try fixture.values()["count"] == .integer(7))
    }

    @Test func userCreatedInstancesAndHostRefreshPreserveState() async throws {
        let fixture = try await InstalledFixture("Hanlin-Expo-Widget-Counter.hanlinExpo")
        defer { fixture.remove() }
        let base = try #require(try fixture.store.load()?.widgetInstances.first)
        let a1 = try fixture.store.createWidgetInstance(from: base.entityID, displayName: "A1")
        let a2 = try fixture.store.createWidgetInstance(from: base.entityID, displayName: "A2")
        #expect(a1.entityID != a2.entityID)
        let context = try fixture.context(entityID: a1.entityID)
        _ = try HanlinWidgetActionExecutor.perform(.init(context: context, actionID: "increment"), store: fixture.store)
        try fixture.republish()
        let reopened = Store(root: fixture.extensionRoot)
        let state = try #require(try reopened.load())
        #expect(state.widgetInstances.contains(a1))
        #expect(state.widgetInstances.contains(a2))
        #expect(state.widgetStates.first { $0.identity == a1.identity }?.values["count"] == .integer(8))
        #expect(state.widgetStates.first { $0.identity == a2.identity } == nil)
        guard case let .expo(node, _) = HanlinWidgetPreparation.prepare(store: reopened, entityID: a2.entityID, family: "systemMedium") else { Issue.record("A2 failed to prepare"); return }
        #expect(String(decoding: try node.jsonValue().canonicalJSONData(), as: UTF8.self).contains("\"7\""))
    }

    @Test func scriptWidgetNamedActionsAndBooleanSetValue() async throws {
        let fixture = try await InstalledFixture("Hanlin-ScriptWidget-Actions.scripting")
        defer { fixture.remove() }
        let context = try fixture.context()
        _ = try HanlinWidgetActionExecutor.perform(.init(context: context, actionID: "sync"), store: fixture.store)
        _ = try HanlinWidgetActionExecutor.perform(.init(context: context, actionID: "named"), store: fixture.store)
        #expect(try fixture.values()["syncCount"] == .integer(1))
        #expect(try fixture.values()["status"] == .string("Named source function ran"))
        for value in [true, true, false, false] {
            _ = try HanlinWidgetActionExecutor.perform(.init(context: context, actionID: "backup", desiredValue: value), store: fixture.store)
            #expect(try fixture.values()["backup"] == .bool(value))
            guard case let .scriptwidget(node, _) = HanlinWidgetPreparation.prepare(store: fixture.store, entityID: fixture.entityID, family: "systemMedium") else { Issue.record("Toggle preparation failed"); return }
            #expect(find(node, tag: "toggle")?.props["on"] == .bool(value))
        }
        try fixture.republish()
        #expect(try fixture.values()["backup"] == .bool(false))
    }

    @Test func staleUndeclaredDisabledAndUninstalledActionsRejectBeforeMutation() async throws {
        let fixture = try await InstalledFixture("Hanlin-Expo-Widget-Counter.hanlinExpo")
        defer { fixture.remove() }
        let context = try fixture.context()
        let identity = Identity(installedPackageID: fixture.identity.installedPackageID, packageID: fixture.identity.packageID,
            generation: 2, entrypointID: fixture.identity.entrypointID)
        let stale = HanlinWidgetActionContext(identity: identity, engine: .expo, artifactSHA256: context.artifactSHA256, family: context.family)
        let before = try fixture.store.load()
        #expect(throws: HanlinWidgetActionError.self) { try HanlinWidgetActionExecutor.perform(.init(context: stale, actionID: "increment"), store: fixture.store) }
        #expect(throws: HanlinWidgetActionError.undeclaredAction) { try HanlinWidgetActionExecutor.perform(.init(context: context, actionID: "not-declared"), store: fixture.store) }
        #expect(try fixture.store.load() == before)
        try fixture.store.invalidateWidgetActions(installedPackageID: fixture.identity.installedPackageID)
        #expect(throws: HanlinWidgetActionError.inactiveInstance) { try HanlinWidgetActionExecutor.perform(.init(context: context, actionID: "increment"), store: fixture.store) }
        _ = try fixture.store.publishWidgetTemplates([], intentEntities: [], translationApps: [], installedPackageIDs: [])
        #expect(throws: HanlinWidgetActionError.inactiveInstance) { try HanlinWidgetActionExecutor.perform(.init(context: context, actionID: "increment"), store: fixture.store) }
    }

    @Test func concurrentSourceActionsReplayAndHostPublication() async throws {
        let fixture = try await InstalledFixture("Hanlin-Expo-Widget-Counter.hanlinExpo")
        defer { fixture.remove() }
        let context = try fixture.context()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<12 {
                group.addTask { _ = try HanlinWidgetActionExecutor.perform(.init(context: context, actionID: "increment", nonce: "tap-\(index)"), store: fixture.store) }
            }
            group.addTask { try fixture.republish() }
            try await group.waitForAll()
        }
        let snapshot = try #require(try fixture.store.load())
        let state = try #require(snapshot.widgetStates.first)
        #expect(state.revision == 12)
        #expect(state.values["count"] == .integer(19))
        let replay = try HanlinWidgetActionExecutor.perform(.init(context: context, actionID: "increment", nonce: "tap-0"), store: fixture.store)
        #expect(!replay.applied)
        #expect(replay.revision == 12)
        #expect(try fixture.values()["count"] == .integer(19))
    }

    @Test func actionAndPublicationPreserveUnrelatedCollections() async throws {
        let fixture = try await InstalledFixture("Hanlin-Expo-Widget-Counter.hanlinExpo")
        defer { fixture.remove() }
        let node = HanlinScriptUINode(kind: .text, properties: ["text": .string("Live")])
        let activity = HanlinScriptExtensions.HanlinScriptLiveActivityDescriptor(identity: fixture.identity, activityID: "live", title: "Live", state: .bool(true), root: node)
        let entity = HanlinScriptExtensions.HanlinScriptIntentEntityRecord(identity: fixture.identity, id: "intent", displayName: "Intent")
        let translation = HanlinScriptExtensions.HanlinScriptTranslationUISnapshot(identity: fixture.identity, appID: "translation", displayName: "Translation", entrypointID: "translation")
        try fixture.store.update { current in
            let current = try #require(current)
            return .init(schemaVersion: 2, generatedAt: .now, widgets: current.widgets, intentEntities: [entity], liveActivities: [activity], translationApps: [translation], widgetInstances: current.widgetInstances)
        }
        _ = try HanlinWidgetActionExecutor.perform(.init(context: fixture.context(), actionID: "increment"), store: fixture.store)
        _ = try fixture.store.publishWidgetTemplates([fixture.template], intentEntities: [entity], translationApps: [translation], installedPackageIDs: [fixture.identity.installedPackageID])
        let after = try #require(try fixture.store.load())
        #expect(after.liveActivities == [activity]); #expect(after.intentEntities == [entity]); #expect(after.translationApps == [translation])
        #expect(after.widgetStates.first?.values["count"] == .integer(8))
    }

    @Test func checkedArtifactsRejectTamperTraversalOtherGenerationAndSymlink() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = Store(root: root), id = try HanlinInstalledPackageID(validating: "installed.test")
        let artifact = try store.storeArtifact(data: Data("program".utf8), installedPackageID: id, generation: 1)
        #expect(try store.loadVerifiedArtifact(ref: artifact.ref, sha256: artifact.sha256, installedPackageID: id, generation: 1) == Data("program".utf8))
        for ref in ["../outside", "/tmp/outside", artifact.ref + "/../" + artifact.sha256] {
            #expect(throws: HanlinScriptExtensions.HanlinScriptExtensionStoreError.invalidArtifactReference) { try store.loadVerifiedArtifact(ref: ref, sha256: artifact.sha256, installedPackageID: id, generation: 1) }
        }
        #expect(throws: HanlinScriptExtensions.HanlinScriptExtensionStoreError.invalidArtifactReference) { try store.loadVerifiedArtifact(ref: artifact.ref, sha256: artifact.sha256, installedPackageID: id, generation: 2) }
        let url = root.appending(path: artifact.ref)
        try Data("tampered".utf8).write(to: url)
        #expect(throws: HanlinScriptExtensions.HanlinScriptExtensionStoreError.integrityMismatch) { try store.loadVerifiedArtifact(ref: artifact.ref, sha256: artifact.sha256, installedPackageID: id, generation: 1) }
        try FileManager.default.removeItem(at: url)
        let outside = root.appending(path: "outside")
        try Data("program".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: outside)
        #expect(throws: HanlinScriptExtensions.HanlinScriptExtensionStoreError.invalidArtifactReference) { try store.loadVerifiedArtifact(ref: artifact.ref, sha256: artifact.sha256, installedPackageID: id, generation: 1) }
    }

    @Test func actualHistoricalV1EncoderAndDowngradeReader() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let old = HanlinLegacyWidgetStoreFixture.HanlinScriptExtensionStore(root: root)
        let identity = HanlinLegacyWidgetStoreFixture.HanlinScriptExtensionIdentity(installedPackageID: try .init(validating: "installed.old"), packageID: try .init(validating: "package.old"), generation: 3, entrypointID: "widget")
        let legacy = HanlinLegacyWidgetStoreFixture.HanlinScriptExtensionSnapshot(generatedAt: Date(timeIntervalSince1970: 12), widgets: [.init(identity: identity, displayName: "Old widget", validUntil: Date(timeIntervalSince1970: 120), root: .init(kind: .text, properties: ["text": .string("Legacy bytes")]))])
        try old.save(legacy)
        let store = Store(root: root), migrated = try #require(try store.load())
        #expect(migrated.widgets.first?.engine == .legacy)
        #expect(migrated.widgets.first?.identity.variantID == "default")
        let v2 = Snapshot(schemaVersion: 2, generatedAt: Date(timeIntervalSince1970: 13), widgets: migrated.widgets)
        try store.save(v2)
        #expect(try old.load()?.widgets.first?.root == legacy.widgets.first?.root)
        try old.save(legacy)
        #expect(try store.loadWithRecovery().recovery == .legacyWriterDetected)
        #expect(try store.load()?.schemaVersion == 1)
        try store.save(v2)
        #expect(try store.load()?.schemaVersion == 2)
    }

    @Test func interruptedShadowPublicationRestoresExactCommittedRevision() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = Store(root: root)
        let before = Snapshot(schemaVersion: 2, generatedAt: Date(timeIntervalSince1970: 1))
        let next = Snapshot(schemaVersion: 2, generatedAt: Date(timeIntervalSince1970: 2))
        try store.save(before)
        let marker = try Data(contentsOf: root.appending(path: "commit.json"))
        let shadow = try Data(contentsOf: root.appending(path: "snapshot-v1.json"))
        try store.save(next)
        let candidate = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appending(path: "commit.json")))
        let pending: [String: Any] = ["candidate": candidate, "previousShadowHash": sha(shadow)]
        try JSONSerialization.data(withJSONObject: pending).write(to: root.appending(path: "pending.json"))
        try marker.write(to: root.appending(path: "commit.json"))
        let recovered = try store.loadWithRecovery()
        #expect(recovered.recovery == .interruptedPublication)
        #expect(recovered.snapshot == before)
        #expect(try Data(contentsOf: root.appending(path: "snapshot-v1.json")) == shadow)
        try store.save(next)
        #expect(try store.load() == next)
    }

    @Test func corruptCommittedV2NeverFallsBackToGoodV1() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = Store(root: root)
        try store.save(.init(schemaVersion: 2, generatedAt: .now))
        let marker = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: root.appending(path: "commit.json"))) as? [String: Any])
        let hash = try #require(marker["snapshotHash"] as? String)
        try Data("broken".utf8).write(to: root.appending(path: "Revisions/\(hash).json"))
        #expect(throws: HanlinScriptExtensions.HanlinScriptExtensionStoreError.integrityMismatch) { try store.load() }
    }

    @Test func unconfiguredAndWrongFamilyNeverSelectAnotherWidget() async throws {
        let fixture = try await InstalledFixture("Hanlin-Expo-Widget-Counter.hanlinExpo")
        defer { fixture.remove() }
        for (id, family) in [("", "systemMedium"), ("other", "systemMedium"), (fixture.entityID, "accessoryInline")] {
            guard case .failure = HanlinWidgetPreparation.prepare(store: fixture.store, entityID: id, family: family) else { Issue.record("Invalid selection rendered content"); continue }
        }
    }
}

private let inventory = HanlinCompatibilityInventory(baselineID: "widget-tests", baselineDigest: String(repeating: "a", count: 64), symbols: [])
private func temporary() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appending(path: "hanlin-widget-pass3-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}
private func fixtureURL(_ name: String) -> URL {
    URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../../../Fixtures/Widgets/\(name)").standardizedFileURL
}
private func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
private func find(_ node: HanlinScriptWidgetPreparedNode, tag: String) -> HanlinScriptWidgetPreparedNode? {
    if node.tag == tag { return node }
    for child in node.children { if case let .element(child) = child, let match = find(child, tag: tag) { return match } }
    return nil
}
private struct ForbiddenScriptingCompiler: HanlinTrustedCompilerClient {
    func compile(_ project: HanlinVirtualTypeScriptProject) async throws -> HanlinTrustedCompilerResult { throw HanlinWidgetProgramError.unsupportedImport }
}
private struct InstalledFixture: Sendable {
    let root: URL
    let extensionRoot: URL
    let store: Store
    let installed: HanlinAtomicScriptStore
    let identity: Identity
    let template: Widget
    var entityID: String { HanlinWidgetInstance(identity: identity, engine: template.engine, displayName: "Default").entityID }
    init(_ name: String) async throws {
        root = try temporary()
        extensionRoot = root.appending(path: "Extensions")
        store = Store(root: extensionRoot)
        installed = try HanlinAtomicScriptStore(root: root.appending(path: "Installed"))
        let staged = try HanlinPackageCenter().stageAndInspect(sourceURL: fixtureURL(name), stagingParent: root)
        let preview = try HanlinScriptAnalyzer(inventory: inventory).analyze(staged)
        #expect(preview.canInstall, "\(preview.findings)")
        let programs = try HanlinWidgetPackagePreparation.programs(packageRoot: staged.packageRoot, preview: preview)
        let compiled = HanlinScriptingBundle(manifest: .init(compilerVersion: "Widget-ABI-1", compilerIntegrity: preview.source.contentSHA256, compilerOptionsHash: String(repeating: "b", count: 64), baselineID: inventory.baselineID, baselineDigest: inventory.baselineDigest, hanlinABIVersion: "1", packageContentDigest: preview.source.contentSHA256, cacheFingerprint: preview.source.contentSHA256, files: []), modules: [], diagnostics: [])
        let bundler = HanlinScriptingBundler(baseline: inventory, abiVersion: "1", scriptingDeclarations: [], compiler: ForbiddenScriptingCompiler())
        let artifactRoot = root.appending(path: "Artifact")
        let manifest = try bundler.writeInstallArtifact(compiled, packageRoot: staged.packageRoot, to: artifactRoot, preparedWidgetPrograms: programs)
        let entries = HanlinWidgetPackagePreparation.installedEntrypoints(preview: preview, artifactDigest: manifest.cacheFingerprint)
        let id = try HanlinInstalledPackageID(validating: "installed.widget")
        let packageID = try HanlinPackageID(validating: "package.widget")
        let plan = HanlinInstallPlan(installedPackageID: id, packageID: packageID, version: try .init(validating: "1.0.0"), sourceDigest: preview.source.contentSHA256, entrypoints: entries, requestedCapabilities: preview.requestedCapabilities, manifest: staged.manifest)
        let record = try await installed.install(plan: plan, artifactDirectory: artifactRoot, artifactManifest: manifest)
        let entry = try #require(entries.first)
        identity = .init(installedPackageID: id, packageID: packageID, generation: record.activeGeneration, entrypointID: entry.id)
        let bytes = try #require(programs[entry.sourcePath])
        let artifact = try store.storeArtifact(data: bytes, installedPackageID: id, generation: record.activeGeneration)
        let engine = try #require(entry.widgetEngine)
        let payload: HanlinScriptExtensions.HanlinWidgetPayload = engine == .expo ? .expo(.init(layout: "", layoutRef: artifact.ref, layoutSHA256: artifact.sha256)) : .scriptwidget(.init(script: "", scriptRef: artifact.ref, scriptSHA256: artifact.sha256))
        template = .init(identity: identity, displayName: staged.manifest.name, validUntil: .distantFuture, engine: engine, payload: payload, root: .init(kind: .text))
        try republish()
    }
    func republish() throws { try store.publishWidgetTemplates([template], intentEntities: [], translationApps: [], installedPackageIDs: [identity.installedPackageID]) }
    func remove() { try? FileManager.default.removeItem(at: root) }
    func values() throws -> [String: HanlinValue] { try store.load()?.widgetStates.first?.values ?? [:] }
    func context(entityID: String? = nil) throws -> HanlinWidgetActionContext {
        switch HanlinWidgetPreparation.prepare(store: store, entityID: entityID ?? self.entityID, family: "systemMedium") {
        case let .expo(_, context), let .scriptwidget(_, context): return context
        case let .failure(reason): throw HanlinScriptWidgetError(reason)
        case .legacy: throw HanlinWidgetProgramError.invalidProgram
        }
    }
}
