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
#if os(macOS)
import AppKit
#endif

private typealias Store = HanlinScriptExtensions.HanlinScriptExtensionStore
private typealias Snapshot = HanlinScriptExtensions.HanlinScriptExtensionSnapshot
private typealias Identity = HanlinScriptExtensions.HanlinScriptExtensionIdentity
private typealias Widget = HanlinScriptExtensions.HanlinScriptWidgetSnapshot

@Suite("Pass 3 installed widget programs, actions and transactions")
struct HanlinDualWidgetEnginesTests {
    @Test func sameSourceActionTargetAcrossInstalledPackagesAndVariantsIsIsolated() async throws {
        let first = try await InstalledFixture("Hanlin-Expo-Widget-Counter.hanlinExpo", installationID: "installed.first", packageID: "package.first")
        defer { first.remove() }
        let second = try await InstalledFixture("Hanlin-Expo-Widget-Counter.hanlinExpo", installationID: "installed.second", packageID: "package.second")
        defer { second.remove() }
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = Store(root: root)
        var templates: [Widget] = []
        for fixture in [first, second] {
            let (program, _) = try fixture.store.loadProgram(for: fixture.template)
            let artifact = try store.storeArtifact(data: JSONEncoder().encode(program), installedPackageID: fixture.identity.installedPackageID, generation: fixture.identity.generation)
            templates.append(.init(identity: fixture.identity, displayName: fixture.template.displayName, validUntil: .distantFuture, engine: .expo,
                payload: .expo(.init(layout: "", layoutRef: artifact.ref, layoutSHA256: artifact.sha256)), root: fixture.template.root))
        }
        let installedIDs: Set<HanlinInstalledPackageID> = [first.identity.installedPackageID, second.identity.installedPackageID]
        try store.publishWidgetTemplates(templates, intentEntities: [], translationApps: [], installedPackageIDs: installedIDs)
        let instances = try #require(try store.load()?.widgetInstances)
        let firstBase = try #require(instances.first { $0.identity == first.identity })
        let secondBase = try #require(instances.first { $0.identity == second.identity })
        let a1 = try store.createWidgetInstance(from: firstBase.entityID, displayName: "A1")
        let a2 = try store.createWidgetInstance(from: firstBase.entityID, displayName: "A2")
        for (instance, taps) in [(a1, 1), (a2, 2), (secondBase, 3)] {
            guard case let .expo(_, context) = HanlinWidgetPreparation.prepare(store: store, entityID: instance.entityID, family: "systemMedium") else { Issue.record("Independent installed instance failed preparation"); return }
            for _ in 0..<taps { _ = try HanlinWidgetActionExecutor.perform(.init(context: context, actionID: "increment"), store: store) }
        }
        try store.publishWidgetTemplates(templates, intentEntities: [], translationApps: [], installedPackageIDs: installedIDs)
        let reopened = try #require(try Store(root: root).load())
        for (instance, expected) in [(a1, Int64(8)), (a2, Int64(9)), (secondBase, Int64(10))] {
            #expect(reopened.widgetStates.first { $0.identity == instance.identity }?.values["count"] == .integer(expected))
            #expect(reopened.widgetInstances.contains(instance))
        }
        #expect(reopened.widgetStates.first { $0.identity == firstBase.identity } == nil)
    }
    @Test func installedProgramPreparationAndActionMeasurements() async throws {
        let names = ["Hanlin-Expo-Widget-Counter.hanlinExpo", "Hanlin-Expo-Widget-Visuals.hanlinExpo", "Hanlin-ScriptWidget-Dashboard.scripting", "Hanlin-ScriptWidget-Actions.scripting", "Hanlin-Widget-Legacy-Regression.scripting"]
        func milliseconds(since start: ContinuousClock.Instant) -> Double {
            let elapsed = start.duration(to: .now).components
            return Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15
        }
        var records: [[String: Any]] = []
        for name in names {
            let installedAt = ContinuousClock.now
            let fixture = try await InstalledFixture(name)
            defer { fixture.remove() }
            let installMS = milliseconds(since: installedAt)
            var preparationMS: [Double] = []
            for _ in 0..<3 {
                let start = ContinuousClock.now
                let presentation = HanlinWidgetPreparation.prepare(store: Store(root: fixture.extensionRoot), entityID: fixture.entityID, family: "systemMedium")
                preparationMS.append(milliseconds(since: start))
                if case let .failure(reason) = presentation { Issue.record("Measured preparation failed: \(reason)") }
            }
            var record: [String: Any] = ["archive": name, "archiveSHA256": sha(try Data(contentsOf: fixtureURL(name))),
                "engine": fixture.template.engine.rawValue, "family": "systemMedium", "installCompilePublishMS": installMS,
                "preparationFirstThenRepeatMS": preparationMS]
            if name.contains("Counter") || name.contains("Actions") {
                let context = try fixture.context()
                let action = name.contains("Counter") ? "increment" : "sync"
                let start = ContinuousClock.now
                _ = try HanlinWidgetActionExecutor.perform(.init(context: context, actionID: action), store: fixture.store)
                record["sourceActionCommitMS"] = milliseconds(since: start)
                record["sourceAction"] = action
                record["programSHA256"] = context.artifactSHA256
                #expect(try fixture.values()[name.contains("Counter") ? "count" : "syncCount"] == .integer(name.contains("Counter") ? 8 : 1))
            }
            records.append(record)
        }
        try recordEvidence(name: "native-program-measurements", values: ["scope": "macOS shared installed-program execution; five isolated temporary installations, not five configured OS widgets",
            "vmLifecycle": "New JavaScriptCore context per preparation/action. Repeated samples do not reuse a VM.",
            "memoryPeak": "NOT_MEASURED", "deviceOrWidgetKitLatency": "NOT_MEASURED", "measurements": records])
    }
    #if os(macOS)
    @Test func originalScriptWidgetHTTPUsesBoundedRealTransport() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let portFile = root.appending(path: "port")
        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        server.arguments = ["python3", "-u", "-c", #"""
            import http.server, json, pathlib, sys, time
            class Handler(http.server.BaseHTTPRequestHandler):
                def log_message(self, *args): pass
                def handle_request(self):
                    if self.path == '/slow': time.sleep(0.5)
                    if self.path == '/redirect':
                        self.send_response(302); self.send_header('Location', 'file:///etc/hosts'); self.end_headers(); return
                    if self.path == '/large':
                        self.send_response(200); self.send_header('Content-Length', str(1024*1024+1)); self.end_headers(); return
                    body = self.rfile.read(int(self.headers.get('Content-Length', '0'))).decode()
                    data = bytes([0, 127, 255]) if self.path == '/binary' else json.dumps({'method': self.command, 'body': body, 'header': self.headers.get('X-Widget'), 'type': self.headers.get('Content-Type')}).encode()
                    self.send_response(503 if self.path == '/status' else 200)
                    self.send_header('Content-Type', 'application/json'); self.send_header('Retry-After', '3'); self.send_header('Content-Length', str(len(data))); self.end_headers()
                    try: self.wfile.write(data)
                    except (BrokenPipeError, ConnectionResetError): pass
                do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = handle_request
            server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
            pathlib.Path(sys.argv[1]).write_text(str(server.server_port))
            server.serve_forever()
            """#, portFile.path]
        server.standardOutput = FileHandle.nullDevice
        server.standardError = FileHandle.nullDevice
        try server.run()
        defer { if server.isRunning { server.terminate(); server.waitUntilExit() } }
        let startDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !FileManager.default.fileExists(atPath: portFile.path), server.isRunning, ContinuousClock.now < startDeadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        let port = try String(contentsOf: portFile, encoding: .utf8)
        let base = "http://127.0.0.1:\(port)"
        func execute(_ source: String) throws -> HanlinScriptWidgetExecution {
            let program = HanlinWidgetProgram(engine: .scriptwidget,
                sourceSHA256: String(repeating: "a", count: 64), compilerSHA256: String(repeating: "b", count: 64),
                javaScript: "async function $main() { const base = '\(base)'; \(source); $render(ScriptWidget.createElement('text', {}, 'Transport verified')); }",
                actions: [], families: ["systemMedium"])
            return try HanlinScriptWidgetRuntime.shared.run(program: program, values: [:], environment: [:])
        }
        let verbs = try execute(#"""
            for (const method of ['get', 'post', 'put', 'patch']) {
              const result = JSON.parse(await $http[method](base + '/echo', {headers:{'X-Widget':'source'}, body:method === 'get' ? undefined : {count:7}}));
              if (result.method !== method.toUpperCase() || result.header !== 'source') throw Error('HTTP method/header lost');
              if (method !== 'get' && (JSON.parse(result.body).count !== 7 || result.type !== 'application/json')) throw Error('JSON body lost');
              $storage.set(method, result.method);
            }
            let rejected = false;
            try { await $fetch(base + '/echo'); } catch (_) { rejected = true; }
            if (!rejected) throw Error('Fifth request exceeded budget');
            """#)
        #expect(verbs.values["post"] == .string("POST"))
        let response = try execute(#"""
            const deleted = JSON.parse(await $http.delete(base + '/echo', {body:'raw source'}));
            if (deleted.method !== 'DELETE' || deleted.body !== 'raw source') throw Error('DELETE body lost');
            const status = await $http.getResponse(base + '/status');
            if (status.status !== 503 || status.headers['retry-after'] !== '3' || JSON.parse(status.body).method !== 'GET') throw Error('Response metadata lost');
            const bytes = await $fetch(base + '/binary', {responseType:'base64'});
            if (bytes !== 'AH//') throw Error('Binary response lost');
            $storage.set('status', status.status);
            """#)
        #expect(response.values["status"] == .integer(503))
        let limits = try execute(#"""
            for (const [path, params] of [['/large', {}], ['/redirect', {}], ['/slow', {timeoutInterval:0.05}]]) {
              let rejected = false;
              try { await $http.get(base + path, params); } catch (_) { rejected = true; }
              if (!rejected) throw Error('Unsafe or over-budget transport accepted: ' + path);
            }
            let rejected = false;
            try { await $fetch('file:///etc/hosts'); } catch (_) { rejected = true; }
            if (!rejected) throw Error('File transport accepted');
            """#)
        #expect(limits.node.children == [.value(.string("Transport verified"))])
    }
    #endif
    @Test func passiveLegacyNavigationCannotCoverNativeOrNestedButtons() throws {
        let identity = Identity(installedPackageID: try .init(validating: "installed.legacy-link"), packageID: try .init(validating: "package.legacy-link"), generation: 1, entrypointID: "widget")
        let url = try #require(URL(string: "hanlin://scripts/legacy-link"))
        let passive = Widget(identity: identity, displayName: "Legacy link", validUntil: .distantFuture, root: .init(kind: .text), deepLink: url)
        #expect(HanlinPreparedWidget.legacy(passive).passiveLegacyURL == url)
        let interactive = Widget(identity: identity, displayName: "Legacy action", validUntil: .distantFuture,
            root: .init(kind: .vStack, children: [.init(kind: .button)]), deepLink: url)
        #expect(HanlinPreparedWidget.legacy(interactive).passiveLegacyURL == nil)
        let context = HanlinWidgetActionContext(identity: identity, engine: .expo, artifactSHA256: String(repeating: "a", count: 64), family: "systemMedium")
        #expect(HanlinPreparedWidget.expo(node: .object([:]), context: context).passiveLegacyURL == nil)
        #expect(HanlinPreparedWidget.scriptwidget(node: .init(tag: "button", props: [:], children: []), context: context).passiveLegacyURL == nil)
        #expect(HanlinPreparedWidget.failure("Missing widget").passiveLegacyURL == nil)
    }
    @Test func timelinePreparationCommitsOriginalTypedStorageAcrossColdReads() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = Store(root: root)
        let identity = Identity(installedPackageID: try .init(validating: "installed.timeline"), packageID: try .init(validating: "package.timeline"), generation: 1, entrypointID: "widget")
        let program = HanlinWidgetProgram(engine: .scriptwidget, sourceSHA256: String(repeating: "a", count: 64), compilerSHA256: String(repeating: "b", count: 64), javaScript: """
            async function $main() {
              const count = ($storage.get('count') || 0) + 1;
              $storage.set('count', count);
              $storage.set('temporary', true);
              $storage.remove('temporary');
              $render(ScriptWidget.createElement('text', {}, String(count)));
            }
            """, actions: [], families: ["systemMedium"])
        let artifact = try store.storeArtifact(data: JSONEncoder().encode(program), installedPackageID: identity.installedPackageID, generation: 1)
        let widget = Widget(identity: identity, displayName: "Timeline storage", validUntil: .distantFuture, engine: .scriptwidget,
            payload: .scriptwidget(.init(script: "", scriptRef: artifact.ref, scriptSHA256: artifact.sha256)), root: .init(kind: .text))
        try store.publishWidgetTemplates([widget], intentEntities: [], translationApps: [], installedPackageIDs: [identity.installedPackageID])
        let instance = try #require(try store.load()?.widgetInstances.first)
        for expected in [1, 2] {
            let reopened = Store(root: root)
            guard case let .scriptwidget(node, _) = HanlinWidgetPreparation.prepare(store: reopened, entityID: instance.entityID, family: "systemMedium") else { Issue.record("Timeline storage preparation failed"); return }
            #expect(node.children == [.value(.string(String(expected)))])
            let state = try #require(try reopened.load()?.widgetStates.first)
            #expect(state.values["count"] == .integer(Int64(expected)))
            #expect(state.values["temporary"] == nil)
            #expect(state.revision == UInt64(expected))
        }
    }
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
        guard case let .object(payload)? = result.values["payload"] else { Issue.record("Verified JSON file did not retain an object value"); return }
        #expect(payload["count"] == .integer(9))
    }
    @Test(arguments: ["Hanlin-Expo-Widget-Counter.hanlinExpo", "Hanlin-Expo-Widget-Visuals.hanlinExpo", "Hanlin-ScriptWidget-Dashboard.scripting", "Hanlin-ScriptWidget-Actions.scripting", "Hanlin-Widget-Legacy-Regression.scripting", "Hanlin-Mixed-Native-Widget.hanlinExpo", "Hanlin-Widget-Invalid-Cases.hanlinExpo"])
    func realArchiveImport(name: String) throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let staged = try HanlinPackageCenter().stageAndInspect(sourceURL: fixtureURL(name), stagingParent: root)
        let preview = try HanlinScriptAnalyzer(inventory: inventory).analyze(staged)
        let expected = !name.contains("Invalid") && !name.contains("Mixed")
        #expect(preview.canInstall == expected, "\(preview.findings)")
        try recordEvidence(name: "analysis-\(name)", values: [
            "scope": "Real shared analyzer; not a native UI assertion",
            "archive": name, "archiveSHA256": sha(try Data(contentsOf: fixtureURL(name))),
            "canInstall": preview.canInstall, "findings": String(describing: preview.findings)
        ])
        if expected {
            let entry = try #require(preview.entrypoints.first)
            #expect(preview.entrypoints.count == 1)
            #expect(entry.kind == .widget)
            #expect(entry.widgetEngine?.rawValue == (name.contains("Legacy") ? "legacy" : name.contains("ScriptWidget") ? "scriptwidget" : "expo"))
            let encoded = try JSONEncoder().encode(entry)
            #expect(try JSONDecoder().decode(HanlinPackageEntrypointDescriptor.self, from: encoded).widgetEngine == entry.widgetEngine)
        }
    }

    @Test(arguments: ["Hanlin-Expo-Widget-Counter.hanlinExpo", "Hanlin-Expo-Widget-Visuals.hanlinExpo", "Hanlin-ScriptWidget-Dashboard.scripting", "Hanlin-ScriptWidget-Actions.scripting", "Hanlin-Widget-Legacy-Regression.scripting"])
    func installAndVerifiedLoader(name: String) async throws {
        let fixture = try await InstalledFixture(name)
        defer { fixture.remove() }
        let snapshot = try #require(try fixture.store.load())
        let widget = try #require(snapshot.widgets.first)
        if widget.engine == .legacy {
            guard case let .legacy(prepared) = HanlinWidgetPreparation.prepare(store: fixture.store, entityID: fixture.entityID, family: "systemMedium") else { Issue.record("Installed legacy archive failed to prepare"); return }
            #expect(prepared.root.properties["text"] == .string("Legacy HanlinScriptUINode Tree"))
        } else {
            let (program, _) = try fixture.store.loadProgram(for: widget)
            #expect(program.engine == widget.engine)
            switch HanlinWidgetPreparation.prepare(store: fixture.store, entityID: fixture.entityID, family: "systemMedium") {
            case .expo, .scriptwidget: break
            default: Issue.record("The actual installed program failed to prepare")
            }
        }
        #expect(widget.identity.generation == 1)
        #expect(try await fixture.installed.snapshots().first?.entrypoints.first?.widgetEngine == widget.engine)
        let reopened = Store(root: fixture.extensionRoot)
        #expect(try reopened.load() == snapshot)
        var evidence: [String: Any] = [
            "scope": "Actual shared atomic installation and preparation; not SpringBoard placement",
            "archive": name, "archiveSHA256": sha(try Data(contentsOf: fixtureURL(name))),
            "familyPrepared": "systemMedium", "entityID": fixture.entityID,
            "installedWidget": try JSONSerialization.jsonObject(with: JSONEncoder().encode(widget))
        ]
        if widget.engine != .legacy {
            let (program, _) = try fixture.store.loadProgram(for: widget)
            evidence["sourceSHA256"] = program.sourceSHA256
            evidence["compilerSHA256"] = program.compilerSHA256
            evidence["compiledJavaScriptSHA256"] = sha(Data(program.javaScript.utf8))
            evidence["upstreamCommit"] = program.upstreamCommit
            evidence["declaredFamilies"] = program.families
        }
        try recordEvidence(name: "installed-\(name)", values: evidence)
        #if os(macOS)
        let presentation = HanlinWidgetPreparation.prepare(store: fixture.store, entityID: fixture.entityID, family: "systemMedium")
        if let png = try await installedNativeRaster(presentation) {
            if let directory = ProcessInfo.processInfo.environment["HANLIN_WIDGET_EVIDENCE_DIR"] {
                try png.write(to: URL(filePath: directory).appending(path: "installed-\(name)-native.png"), options: .atomic)
            }
        }
        #endif
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
#if os(macOS)
@MainActor private func installedNativeRaster(_ presentation: HanlinPreparedWidget) throws -> Data? {
    let view: AnyView
    switch presentation {
    case let .legacy(widget): view = AnyView(HanlinExtensionNodeView(node: widget.root))
    case let .scriptwidget(node, context): view = AnyView(HanlinScriptWidgetDynamicView(node: node, context: context))
    case .expo: return nil // Exact Expo native product is covered by the iOS renderer target.
    case .failure: Issue.record("Installed fixture failed native preparation"); return nil
    }
    let renderer = ImageRenderer(content: view.frame(width: 360, height: 320).environment(\.colorScheme, .light))
    renderer.scale = 1
    let image = try #require(renderer.cgImage)
    #expect(image.width == 360 && image.height == 320)
    return try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
}
#endif
private func recordEvidence(name: String, values: [String: Any]) throws {
    guard let directory = ProcessInfo.processInfo.environment["HANLIN_WIDGET_EVIDENCE_DIR"] else { return }
    let root = URL(filePath: directory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys])
        .write(to: root.appending(path: "\(name).json"), options: .atomic)
}
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
    init(_ name: String, installationID: String = "installed.widget", packageID packageName: String = "package.widget") async throws {
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
        let id = try HanlinInstalledPackageID(validating: installationID)
        let packageID = try HanlinPackageID(validating: packageName)
        let plan = HanlinInstallPlan(installedPackageID: id, packageID: packageID, version: try .init(validating: "1.0.0"), sourceDigest: preview.source.contentSHA256, entrypoints: entries, requestedCapabilities: preview.requestedCapabilities, manifest: staged.manifest)
        let record = try await installed.install(plan: plan, artifactDirectory: artifactRoot, artifactManifest: manifest)
        let entry = try #require(entries.first)
        identity = .init(installedPackageID: id, packageID: packageID, generation: record.activeGeneration, entrypointID: entry.id)
        let engine = try #require(entry.widgetEngine)
        if engine == .legacy {
            let node = try JSONDecoder().decode(HanlinScriptUINode.self, from: Data(contentsOf: artifactRoot.appending(path: entry.sourcePath)))
            template = .init(identity: identity, displayName: staged.manifest.name, validUntil: .distantFuture, engine: engine, payload: .legacy(node), root: node)
        } else {
            let bytes = try #require(programs[entry.sourcePath])
            let artifact = try store.storeArtifact(data: bytes, installedPackageID: id, generation: record.activeGeneration)
            let payload: HanlinScriptExtensions.HanlinWidgetPayload = engine == .expo ? .expo(.init(layout: "", layoutRef: artifact.ref, layoutSHA256: artifact.sha256)) : .scriptwidget(.init(script: "", scriptRef: artifact.ref, scriptSHA256: artifact.sha256))
            template = .init(identity: identity, displayName: staged.manifest.name, validUntil: .distantFuture, engine: engine, payload: payload, root: .init(kind: .text))
        }
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
