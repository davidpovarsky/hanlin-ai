#if os(macOS)
import Foundation
import JavaScriptCore
@testable import HanlinScriptWidgetOriginal
import Testing

@Suite("Original ScriptWidget pending Promise ownership")
struct HanlinOriginalPromiseLifetimeTests {
    @Test func originalPromiseRetainsPendingContinuationThroughGarbageCollection() throws {
        try withProbe("pending-gc") { probe in
            let pending = try probe.collectAndObserve("pending-after-gc")
            #expect(pending, "The original pending Promise lost its JavaScript continuation during garbage collection")
            probe.resolve("delivered")
            let values = try probe.settlements("after-resolution")
            #expect(values == ["original:delivered"], "The original native operation did not settle its actual JavaScript continuation")
            probe.resolve("duplicate")
            probe.reject("late rejection")
            #expect(try probe.settlements("after-duplicate-callbacks") == values)
            // Public GC can retain conservative stack/register roots. Record
            // this observation; assert actual context disposal after cleanup.
            _ = try probe.collectAndObserve("settled-after-gc")
        }
    }

    @Test func originalPromiseCancellationReleasesPendingContinuationAndDisposesContext() throws {
        try withProbe("cancel-pending") { probe in
            probe.native.cancel()
            _ = try probe.collectAndObserve("cancelled-after-gc")
            probe.resolve("late resolution")
            probe.reject("late rejection")
            let values = try probe.settlements("cancelled-after-late-callbacks")
            #expect(values.isEmpty,
                    "A cancelled original execution delivered a late JavaScript callback")
        }
    }

    private func withProbe(_ scenario: String, _ body: (OriginalPromiseProbe) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hanlin-original-promise-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let evidenceRoot = ProcessInfo.processInfo.environment["HANLIN_WIDGET_EVIDENCE_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory
        let evidence = evidenceRoot.appendingPathComponent("original-promise-" + scenario + "-" + UUID().uuidString + ".jsonl")
        try FileManager.default.createDirectory(at: evidenceRoot, withIntermediateDirectories: true)
        var rows: [[String: Any]] = []
        weak var releasedContext: JSContext?
        defer {
            let data = rows.compactMap { try? JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]) }
                .reduce(into: Data()) { $0.append($1); $0.append(0x0a) }
            do { try data.write(to: evidence, options: .atomic) }
            catch { Issue.record("Could not retain original Promise observations: \(error)") }
            print("Original Promise observations: \(evidence.path)")
        }
        try autoreleasepool {
            let probe = try OriginalPromiseProbe(root: root) { row in rows.append(row) }
            releasedContext = probe.context
            defer { probe.close() }
            try body(probe)
        }
        rows.append(["phase": "context-disposed", "disposed": releasedContext == nil,
                     "pid": ProcessInfo.processInfo.processIdentifier, "at": Date().timeIntervalSince1970])
        #expect(releasedContext == nil, "The original Promise probe retained its JavaScript context after explicit cleanup")
    }
}

/// Uses the shipping session, Promise and callback lane. Only the native
/// operation's completion timing is controlled; its JavaScript delivery is not.
private final class OriginalPromiseProbe {
    let context: JSContext
    let native: HanlinOriginalScriptWidgetSession
    private let operation = PendingOriginalOperation()
    private var capturedObject: JSManagedValue?
    private let record: ([String: Any]) -> Void

    init(root: URL, record: @escaping ([String: Any]) -> Void) throws {
        let context = try #require(JSContext())
        self.context = context
        self.record = record
        native = try HanlinOriginalScriptWidgetSession(context: context, root: root,
            identity: UUID().uuidString, preparedJavaScript: "async function $main() {}",
            files: [:], values: [:], environment: [:], isUserInitiatedAction: false)
        try native.onJavaScriptQueue {
            try autoreleasepool {
                let operation = self.operation
                let begin: @convention(block) () -> ScriptWidgetRuntimePromise = {
                    ScriptWidgetRuntimePromise { resolve, reject in
                        operation.resolve = resolve
                        operation.reject = reject
                    }
                }
                context.setObject(begin, forKeyedSubscript: "__beginOriginalPromise" as NSString)
                context.evaluateScript("globalThis.__originalSettlements = []; globalThis.__captured = {token:'original'};")
                capturedObject = JSManagedValue(value: try #require(context.objectForKeyedSubscript("__captured")))
                context.evaluateScript("""
                    (async function(captured) {
                      const value = await __beginOriginalPromise();
                      __originalSettlements.push(captured.token + ':' + value);
                    })(__captured);
                    delete globalThis.__captured;
                    """)
                #expect(context.exception == nil)
                #expect(operation.resolve != nil && operation.reject != nil)
                #expect(try #require(context.scriptWidgetRunningState).isCurrentExecution)
            }
        }
        recordRow("native-operation-pending", ["guardedResolvePresent": operation.resolve != nil,
                                              "guardedRejectPresent": operation.reject != nil])
    }

    func collectAndObserve(_ phase: String) throws -> Bool {
        let present = native.onJavaScriptQueue {
            autoreleasepool {
                JSGarbageCollect(context.jsGlobalContextRef)
                return capturedObject?.value != nil
            }
        }
        recordRow(phase, ["capturedContinuationPresent": present,
                          "executionActive": try native.onJavaScriptQueue { try #require(context.scriptWidgetRunningState).executionSession.isActive }])
        return present
    }

    func resolve(_ value: String) {
        native.onJavaScriptQueue { autoreleasepool { operation.resolve?.call(withArguments: [value]) } }
    }

    func reject(_ value: String) {
        native.onJavaScriptQueue { autoreleasepool { operation.reject?.call(withArguments: [value]) } }
    }

    func settlements(_ phase: String) throws -> [String] {
        // A synchronous read queued after the original async delivery drains
        // that same callback lane; it does not pump or replace the JS runtime.
        let values = try native.onJavaScriptQueue {
            try autoreleasepool { try #require(context.objectForKeyedSubscript("__originalSettlements")?.toArray() as? [String]) }
        }
        recordRow(phase, ["settlements": values])
        return values
    }

    func close() {
        native.cancel()
        native.onJavaScriptQueue {
            autoreleasepool {
                native.finish()
                operation.resolve = nil
                operation.reject = nil
                capturedObject = nil
                context.setObject(nil, forKeyedSubscript: "__beginOriginalPromise" as NSString)
                context.setObject(nil, forKeyedSubscript: "__originalSettlements" as NSString)
                context.exceptionHandler = nil
                JSGarbageCollect(context.jsGlobalContextRef)
            }
        }
    }

    private func recordRow(_ phase: String, _ fields: [String: Any]) {
        record(fields.merging(["phase": phase, "pid": ProcessInfo.processInfo.processIdentifier,
                               "at": Date().timeIntervalSince1970]) { _, value in value })
    }
}

private final class PendingOriginalOperation {
    var resolve: JSValue?
    var reject: JSValue?
}
#endif
