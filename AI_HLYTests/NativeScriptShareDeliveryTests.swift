import Foundation
import HanlinPlatformContracts
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
                    let queued = try #require(queue.receipt(for: id))
                    #expect(queued.status == .queued && queued.attempt == 0)
                    platform.dismissActiveApplication()
                }
                let deadline = ContinuousClock.now + .seconds(120)
                while try queue.receipt(for: id)?.status.isTerminal != true {
                    try #require(ContinuousClock.now < deadline, "Actual Share action did not produce a terminal receipt")
                    try await Task.sleep(for: .milliseconds(25))
                }
                let receipt = try #require(HanlinScriptExtensionStore().receipt(for: id))
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
