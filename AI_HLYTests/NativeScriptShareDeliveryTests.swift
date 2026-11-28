import Foundation
import HanlinNativeScriptRuntime
import HanlinPlatformContracts
import HanlinScriptCompiler
import HanlinScriptExtensions
import HanlinScriptStore
import Testing
import UniformTypeIdentifiers
@testable import AI_Hanlin

extension HanlinUnifiedHostServicesE2ETests {
    @MainActor
    @Test func actualOwnedShareDispatchWaitsForTheVMAndPreservesResultsAcrossTwoSessions() async throws {
        let suffix = UUID().uuidString.lowercased()
        let appID = "hanlin.share-test-\(suffix)"
        let directory = FileManager.default.temporaryDirectory.appending(path: "share-action-\(suffix)")
        let source = directory.appending(path: "Package")
        let app = source.appending(path: "nativescript/app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manifest: [String: Any] = ["name": "Share Delivery \(suffix)", "version": "1.0.0",
            "entry": "nativescript/app/bundle.mjs", "runInApp": true, "hanlinRuntime": "hanlin-nativescript",
            "hanlinAppID": appID, "capabilities": ["inter-app.share", "node", "python", "javascript"],
            "actions": [["id": "share.capture", "capability": "inter-app.share",
                "handler": "nativescript/app/bundle.mjs", "title": "Capture shared items"]]]
        try JSONSerialization.data(withJSONObject: manifest).write(to: source.appending(path: "script.json"))
        try Data(#"{"name":"share-delivery-test","type":"module","main":"bundle.mjs","hanlinRuntime":"hanlin-nativescript","dependencies":{"@nativescript/core":"9.1.0"}}"#.utf8)
            .write(to: app.appending(path: "package.json"))
        try Data(#"""
        import { createHostServices } from '@hanlin/host-services';
        const host = createHostServices();
        const bridge = HanlinNativeServicesBridge.activeSessionBridge();
        bridge.registerRequestHandlerCapabilityHandler('share.capture', 'inter-app.share', (caller, json, reply) => {
          (async () => {
            const input = JSON.parse(json);
            const results = [];
            for (const [kind, source] of [['node', "console.log('SHARE_NODE')"],
              ['typeScript', "const n: number = 42; console.log('SHARE_TS_' + n)"],
              ['localPython', "print('SHARE_PY')"], ['javaScriptCore', '21 * 2'], ['shell', 'pwd']]) {
              results.push(await host.executeRuntime(kind, source));
            }
            reply(JSON.stringify({caller, input, results}), null);
          })().catch(error => reply(null, String(error)));
        });
        """#.utf8).write(to: app.appending(path: "bundle.mjs"))
        let archive = directory.appending(path: "share-action.scripting")
        try HanlinScriptingPackageExporter().exportPackage(at: source, to: archive)
        let platform = HanlinScriptingPlatform.shared
        await platform.importPackage(from: archive)
        let preview = try #require(platform.preview)
        #expect(preview.canInstall)
        await platform.installPreview()
        let installed = try #require(platform.installedPackages.first(where: { $0.appID.rawValue == appID }))
        let installedID = installed.record.installedPackageID
        do {
            let target = try #require(platform.shareActionTargets.first(where: { $0.appID.rawValue == appID }))
            let group = try #require(FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.itorah.chavrusachat"))
            let inbox = try HanlinShareInboxStore(container: group)
            let queue = try HanlinScriptExtensionStore()
            // Failure-only scalar observation. Do not retain a native session,
            // serialize shared text/results, or replace the original thrown error.
            @MainActor
            func recordShareWaitFailure(_ originalError: any Error, iteration: Int, batchID: UUID) {
                func bounded(_ value: String) -> String {
                    String(decoding: value.utf8.prefix(256), as: UTF8.self)
                }
                let current = platform.installedPackages.first {
                    $0.record.installedPackageID == installedID
                }?.record
                let activeApp = platform.activeApplicationID
                let nativeSession = HanlinNativeScriptSession.activeSessionIdentifier
                let windowRuntime = HanlinNativeScriptWindowSession.activeRuntimeSessionIdentifier
                var fields: [String: Any] = [
                    "schemaVersion": 1,
                    "test": "actualOwnedShareDispatchWaitsForTheVMAndPreservesResultsAcrossTwoSessions",
                    "sourceFile": #fileID, "phase": "terminal-receipt-wait",
                    "processID": ProcessInfo.processInfo.processIdentifier,
                    "observedAt": Date().timeIntervalSince1970,
                    "processUptime": ProcessInfo.processInfo.systemUptime,
                    "iteration": iteration, "batchID": batchID.uuidString.lowercased(),
                    "appID": bounded(appID), "installedID": bounded(installedID.rawValue),
                    "installedGeneration": String(installed.record.activeGeneration),
                    "installedSourceDigest": bounded(installed.record.sourceDigest),
                    "installedArtifactDigest": bounded(installed.record.artifactDigest),
                    "currentInstallationPresent": current != nil,
                    "activeApplicationPresent": activeApp != nil,
                    "activeApplicationID": bounded(activeApp?.rawValue ?? ""),
                    "activeNativeControllerPresent": platform.activeNativeScriptController != nil,
                    "nativeSessionPresent": nativeSession != nil,
                    "nativeSessionID": bounded(nativeSession ?? ""),
                    "windowRuntimePresent": windowRuntime != nil,
                    "windowRuntimeID": bounded(windowRuntime ?? ""),
                    "pendingInPlatform": platform.pendingResumeCommands.contains { $0.id == batchID },
                    "originalErrorType": bounded(String(reflecting: type(of: originalError)))
                ]
                if let current {
                    fields["currentGeneration"] = String(current.activeGeneration)
                    fields["currentSourceDigest"] = bounded(current.sourceDigest)
                    fields["currentArtifactDigest"] = bounded(current.artifactDigest)
                }
                // One existing per-ID API read; its existing store-lock policy
                // is unchanged. This is a sequential snapshot, not an atomic
                // claim that a process-global VM belongs to this invocation.
                do {
                    let observed = try queue.receipt(for: batchID)
                    fields["receiptPresent"] = observed != nil
                    if let observed {
                        fields["receiptInvocationID"] = observed.invocationID.uuidString.lowercased()
                        fields["receiptStatus"] = observed.status.rawValue
                        fields["receiptAttempt"] = observed.attempt
                        fields["receiptUpdatedAt"] = observed.updatedAt.timeIntervalSince1970
                        fields["receiptFailure"] = observed.failure?.rawValue ?? ""
                        fields["receiptCancellationRequested"] = observed.cancellationRequested
                        fields["receiptLeaseID"] = observed.leaseID?.uuidString.lowercased() ?? ""
                        if let expiry = observed.leaseExpiresAt { fields["receiptLeaseExpiresAt"] = expiry.timeIntervalSince1970 }
                        fields["receiptHasResult"] = observed.value != nil
                    }
                } catch {
                    fields["receiptReadErrorType"] = bounded(String(reflecting: type(of: error)))
                }
                guard let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]),
                      data.count <= 16_384 else {
                    print("HANLIN_SHARE_WAIT_FAILURE encoding_unavailable iteration=\(iteration) batch=\(batchID.uuidString.lowercased())")
                    return
                }
                print("HANLIN_SHARE_WAIT_FAILURE " + String(decoding: data, as: UTF8.self))
            }

            var batchIDs: [UUID] = []
            defer {
                for id in batchIDs {
                    try? FileManager.default.removeItem(at: inbox.directory.appending(path: "Batches/\(id.uuidString.lowercased())"))
                }
            }
            await platform.launch(installedID)
            #expect(platform.activeApplicationID == installedID)
            let fullText = String(repeating: "טקסט מלא🙂\n", count: 2000)
            for iteration in 0..<2 {
                let id = try inbox.begin()
                batchIDs.append(id)
                let provider = NSItemProvider(object: fullText as NSString)
                let item: HanlinShareItem = await withCheckedContinuation { continuation in
                    HanlinShareItemLoader.load(provider, store: inbox, batchID: id, ordinal: 0) {
                        continuation.resume(returning: $0)
                    }
                }
                _ = try inbox.commit(id, items: [item])
                try await platform.submitShareBatch(id, to: target)
                if iteration == 0 {
                    // Same-package foreground VM still owns the isolate. Share
                    // actions are deliberately headless, so remain unstarted.
                    try await Task.sleep(for: .milliseconds(100))
                    let queued = try #require(try queue.receipt(for: id))
                    #expect(queued.status == .queued && queued.attempt == 0)
                    platform.dismissActiveApplication()
                }
                let deadline = ContinuousClock.now + .seconds(120)
                do {
                    while try queue.receipt(for: id)?.status.isTerminal != true {
                        try #require(ContinuousClock.now < deadline, "Actual Share action did not produce a terminal receipt")
                        try await Task.sleep(for: .milliseconds(25))
                    }
                } catch {
                    recordShareWaitFailure(error, iteration: iteration, batchID: id)
                    throw error
                }
                let receipt = try #require(try HanlinScriptExtensionStore().receipt(for: id))
                #expect(receipt.status == .succeeded && receipt.attempt == 1)
                guard case .object(let result) = receipt.value,
                      case .object(let input) = result["input"], case .array(let items) = input["items"],
                      case .object(let shared) = items.first, case .array(let results) = result["results"] else {
                    Issue.record("Actual registered JavaScript action result was lost"); break
                }
                #expect(result["caller"] == .string("hanlin.host"))
                #expect(shared["text"] == .string(fullText))
                #expect(results.count == 5)
                for value in results {
                    guard case .object(let runtime) = value else { Issue.record("Missing runtime receipt"); continue }
                    #expect(runtime["exitCode"] == .integer(0))
                    #expect(runtime["wasCancelled"] == .bool(false))
                }
                // Identical batch cannot execute a second time after its real
                // result moved into Receipts; another target cannot replace it.
                try await platform.submitShareBatch(id, to: target)
                #expect(try queue.receipt(for: id) == receipt)
            }
            await platform.setEnabled(false, for: installedID)
            await #expect(throws: (any Error).self) {
                try await platform.submitShareBatch(UUID(), to: target)
            }
            await platform.uninstall(installedID)
        } catch {
            platform.dismissActiveApplication()
            await platform.uninstall(installedID)
            throw error
        }
    }
}
