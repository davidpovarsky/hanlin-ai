import Foundation
import HanlinScriptContracts
import HanlinScriptExtensions
import HanlinWidgetCompiler
import Testing

#if os(macOS)
/// Real loopback transport with observable arrival and disconnection. The
/// harness deadline only prevents a broken regression from stranding a test.
final class ScriptWidgetTransportTestServer: @unchecked Sendable {
    let root: URL
    let base: String
    private let process: Process

    init() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Hanlin-Transport-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-u", "-c", #"""
            import http.server, json, pathlib, socket, sys, time
            root = pathlib.Path(sys.argv[1])
            class Handler(http.server.BaseHTTPRequestHandler):
                def log_message(self, *args): pass
                def handle_request(self):
                    if self.path.startswith('/signal/'):
                        (root / ('started-' + self.path.rsplit('/', 1)[1])).touch()
                    if self.path.startswith('/hold/'):
                        name = self.path.rsplit('/', 1)[1]
                        (root / ('started-' + name)).touch()
                        self.connection.settimeout(0.05)
                        end = time.monotonic() + 10
                        while time.monotonic() < end:
                            try:
                                if not self.connection.recv(1, socket.MSG_PEEK):
                                    (root / ('cancelled-' + name)).touch()
                                    return
                            except socket.timeout: pass
                            except (BrokenPipeError, ConnectionResetError):
                                (root / ('cancelled-' + name)).touch()
                                return
                        self.connection.settimeout(None)
                    if self.path == '/slow': time.sleep(0.5)
                    if self.path == '/long': time.sleep(5.25)
                    if self.path == '/parallel': time.sleep(0.15)
                    if self.path == '/redirect':
                        self.send_response(302); self.send_header('Location', 'file:///etc/hosts'); self.end_headers(); return
                    body = self.rfile.read(int(self.headers.get('Content-Length', '0'))).decode()
                    if self.path == '/large': data = b'R' * (2*1024*1024+1)
                    elif self.path == '/binary': data = bytes([0, 127, 255])
                    else: data = json.dumps({'method': self.command, 'body': body, 'header': self.headers.get('X-Widget'), 'type': self.headers.get('Content-Type')}).encode()
                    self.send_response(503 if self.path == '/status' else 200)
                    self.send_header('Content-Type', 'application/json'); self.send_header('Retry-After', '3'); self.send_header('Content-Length', str(len(data))); self.end_headers()
                    try: self.wfile.write(data)
                    except (BrokenPipeError, ConnectionResetError): pass
                do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = handle_request
            server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
            (root / 'port').write_text(str(server.server_port))
            server.serve_forever()
            """#, root.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let portFile = root.appending(path: "port")
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while !FileManager.default.fileExists(atPath: portFile.path), process.isRunning, ContinuousClock.now < deadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
            let port = try String(contentsOf: portFile, encoding: .utf8)
            self.base = "http://127.0.0.1:\(port)"
            self.root = root
            self.process = process
        } catch {
            if process.isRunning { process.terminate(); process.waitUntilExit() }
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    deinit {
        if process.isRunning { process.terminate(); process.waitUntilExit() }
        try? FileManager.default.removeItem(at: root)
    }

    func program(_ source: String) -> HanlinWidgetProgram {
        .init(engine: .scriptwidget,
            sourceSHA256: String(repeating: "a", count: 64), compilerSHA256: String(repeating: "b", count: 64),
            javaScript: "async function $main() { const base = '\(base)'; \(source); $render(ScriptWidget.createElement('text', {}, 'Transport verified')); }",
            actions: [], families: ["systemMedium"])
    }

    func waitForEvent(_ event: String) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !FileManager.default.fileExists(atPath: root.appending(path: event).path) {
            guard ContinuousClock.now < deadline else {
                throw NSError(domain: "ScriptWidgetTransportTest", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Transport event was not observed: \(event)"])
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private struct ScriptWidgetCancellationFixture: Sendable {
    let store: HanlinScriptExtensionStore
    let entityID: String

    init(server: ScriptWidgetTransportTestServer, source: String) throws {
        let store = HanlinScriptExtensionStore(root: server.root.appending(path: "store", directoryHint: .isDirectory))
        let identity = HanlinScriptExtensionIdentity(installedPackageID: try .init(validating: "installed.cancellation"),
            packageID: try .init(validating: "package.cancellation"), generation: 1, entrypointID: "widget")
        let program = server.program(source)
        let artifact = try store.storeArtifact(data: JSONEncoder().encode(program), installedPackageID: identity.installedPackageID, generation: 1)
        let widget = HanlinScriptWidgetSnapshot(identity: identity, displayName: "Cancellation",
            validUntil: .distantFuture, engine: .scriptwidget,
            payload: .scriptwidget(.init(script: "", scriptRef: artifact.ref, scriptSHA256: artifact.sha256)),
            root: .init(kind: .text))
        try store.publishWidgetTemplates([widget], intentEntities: [], translationApps: [], installedPackageIDs: [identity.installedPackageID])
        self.entityID = try #require(try store.load()?.widgetInstances.first?.entityID)
        self.store = store
    }
}

extension HanlinDualWidgetEnginesTests {
    @Test func scriptWidgetDefaultLifetimeAllowsHTTPBeyondFiveSeconds() throws {
        let server = try ScriptWidgetTransportTestServer()
        let result = try HanlinScriptWidgetRuntime.shared.run(
            program: server.program("""
                if ($runtime.limits.executionMilliseconds !== null || $runtime.limits.systemDataQueries !== null) throw Error('Runtime advertises a host ceiling');
                await $fetch(base + '/long'); $storage.set('completed', true);
                """),
            values: [:], environment: [:])
        #expect(result.values["completed"] == .bool(true))
        #expect(result.node.children == [.value(.string("Transport verified"))])
    }

    @Test func scriptWidgetCallerDeadlineCancelsRealTransport() async throws {
        let server = try ScriptWidgetTransportTestServer()
        let control = HanlinScriptWidgetExecutionControl(deadline: .now.advanced(by: .seconds(1)))
        defer { control.cancel() }
        let program = server.program("await $fetch(base + '/hold/deadline');")
        do {
            _ = try await control.perform {
                try HanlinScriptWidgetRuntime.shared.run(program: program, values: [:], environment: [:], executionControl: control)
            }
            Issue.record("A caller deadline completed pending HTTP")
        } catch let reason as HanlinScriptWidgetExecutionControl.Interruption {
            #expect(reason == .deadlineExceeded)
        }
        try await server.waitForEvent("started-deadline")
        try await server.waitForEvent("cancelled-deadline")
    }

    @Test func scriptWidgetTaskCancellationStopsTransportWithoutCommittingStorage() async throws {
        let server = try ScriptWidgetTransportTestServer()
        let fixture = try ScriptWidgetCancellationFixture(server: server,
            source: "$storage.set('staged', true); await $fetch(base + '/hold/task');")
        let control = HanlinScriptWidgetExecutionControl()
        let worker = Task {
            try await control.perform {
                HanlinWidgetPreparation.prepare(store: fixture.store, entityID: fixture.entityID,
                    family: "systemMedium", executionControl: control)
            }
        }
        do { try await server.waitForEvent("started-task") }
        catch { control.cancel(); _ = try? await worker.value; throw error }
        worker.cancel()
        do {
            _ = try await worker.value
            Issue.record("Cancelled owner returned a prepared widget")
        } catch let reason as HanlinScriptWidgetExecutionControl.Interruption {
            #expect(reason == .cancelled)
        }
        try await server.waitForEvent("cancelled-task")
        #expect(try fixture.store.load()?.widgetStates.isEmpty == true,
            "Cancelled execution committed staged script storage")
    }

    @Test func scriptWidgetCancellationRejectsQueuedPreparationBeforeSideEffects() async throws {
        let server = try ScriptWidgetTransportTestServer()
        let fixture = try ScriptWidgetCancellationFixture(server: server,
            source: "$storage.set('staged', true); await $fetch(base + '/signal/queued');")
        let control = HanlinScriptWidgetExecutionControl()
        let queued = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let worker = Task {
            try await control.perform {
                queued.signal()
                release.wait()
                return HanlinWidgetPreparation.prepare(store: fixture.store, entityID: fixture.entityID,
                    family: "systemMedium", executionControl: control)
            }
        }
        // A worker is waiting for its owner to release queued work. Cancelling
        // that owner must still be observed at the synchronous preparation boundary.
        let admitted = await Task.detached { queued.wait(timeout: .now() + 3) == .success }.value
        #expect(admitted, "Preparation worker did not enter the queue")
        worker.cancel()
        release.signal()
        do {
            _ = try await worker.value
            Issue.record("Cancelled queued preparation ran")
        } catch let reason as HanlinScriptWidgetExecutionControl.Interruption {
            #expect(reason == .cancelled)
        }
        #expect(try fixture.store.load()?.widgetStates.isEmpty == true)
        #expect(!FileManager.default.fileExists(atPath: server.root.appending(path: "started-queued").path))
    }

    @Test func scriptWidgetDeadlineInterruptsCompilerGuardedSynchronousLoop() async throws {
        let server = try ScriptWidgetTransportTestServer()
        let source = """
            export default function render() {
              $http.get('\(server.base)/signal/loop').then(function () {}, function () {});
              try { while (true) {} }
              catch (_) { while (true) {} }
            }
            """
        let program = try HanlinWidgetCompiler.preparePresentation(
            .init(engine: .scriptwidget, sourcePath: "native/loop.tsx", sourceFormat: "tsx"),
            files: ["native/loop.tsx": Data(source.utf8)])
        let control = HanlinScriptWidgetExecutionControl(deadline: .now.advanced(by: .milliseconds(500)))
        // An independent test cleanup prevents a broken deadline scheduler from
        // stranding the suite. It produces .cancelled, which cannot pass this test.
        let cleanup = Task.detached {
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            control.cancel()
        }
        defer { cleanup.cancel(); control.cancel() }
        do {
            _ = try await control.perform {
                try HanlinScriptWidgetRuntime.shared.run(program: program, values: [:], environment: [:], executionControl: control)
            }
            Issue.record("An infinite guarded loop completed")
        } catch let reason as HanlinScriptWidgetExecutionControl.Interruption {
            #expect(reason == .deadlineExceeded)
        }
        try await server.waitForEvent("started-loop")
    }
}
#endif
