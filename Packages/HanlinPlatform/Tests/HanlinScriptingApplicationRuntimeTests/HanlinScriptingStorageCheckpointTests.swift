import Foundation
import HanlinPlatformContracts
import Testing
@testable import HanlinScriptingApplicationRuntime

@MainActor
@Suite("Actual ScriptUI owners during a product storage checkpoint", .serialized)
struct HanlinScriptingStorageCheckpointTests {
    @Test("An embedded chat session blocks its store until native disposal completes")
    func embeddedOwnerAndCheckpointAdmission() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = try makeSession(root: root, embedded: true)
        #expect(throws: HanlinScriptingStorageCheckpointError.busy) {
            try HanlinScriptingApplicationSession.beginStorageCheckpoint(dataRoot: root.appending(path: "MiniApps"))
        }
        session.dispose()
        let token = try await checkpointAfterDisposal(root)
        defer { HanlinScriptingApplicationSession.endStorageCheckpoint(token) }
        #expect(throws: HanlinScriptingStorageCheckpointError.busy) { try makeSession(root: root) }
        HanlinScriptingApplicationSession.endStorageCheckpoint(UUID())
        #expect(throws: HanlinScriptingStorageCheckpointError.busy) { try makeSession(root: root) }
        HanlinScriptingApplicationSession.endStorageCheckpoint(token)
        let reopened = try makeSession(root: root)
        reopened.dispose()
        let drained = try await checkpointAfterDisposal(root)
        HanlinScriptingApplicationSession.endStorageCheckpoint(drained)
    }

    @Test("An unrelated isolated store cannot block or bypass a production checkpoint")
    func separateRoots() async throws {
        let first = temporaryRoot(), other = temporaryRoot()
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: other)
        }
        let token = try HanlinScriptingApplicationSession.beginStorageCheckpoint(dataRoot: first.appending(path: "MiniApps"))
        defer { HanlinScriptingApplicationSession.endStorageCheckpoint(token) }
        let session = try makeSession(root: other)
        #expect(throws: HanlinScriptingStorageCheckpointError.busy) { try makeSession(root: first) }
        session.dispose()
        let otherToken = try await checkpointAfterDisposal(other)
        HanlinScriptingApplicationSession.endStorageCheckpoint(otherToken)
    }

    @Test("A failed initializer cancels its owners before the same store becomes available")
    func failedSessionCleanup() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: (any Error).self) {
            try HanlinScriptingApplicationSession(
                installedPackageID: .init(validating: "checkpoint-failed"),
                program: "throw new Error('intentional initialization failure')",
                filename: "failed.js", storageAllowed: true, runtimeRoot: root)
        }
        let token = try await checkpointAfterDisposal(root)
        HanlinScriptingApplicationSession.endStorageCheckpoint(token)
        let session = try makeSession(root: root)
        session.dispose()
        let drained = try await checkpointAfterDisposal(root)
        HanlinScriptingApplicationSession.endStorageCheckpoint(drained)
    }

    private func makeSession(root: URL, embedded: Bool = false) throws -> HanlinScriptingApplicationSession {
        try HanlinScriptingApplicationSession(
            installedPackageID: .init(validating: "checkpoint-session"),
            canonicalAppID: .init(validating: "checkpoint-app"),
            program: "Storage.set('saved', 'kept'); Navigation.present({element:createElement(Text,null,'ready')});",
            filename: "checkpoint.js",
            entrypointContext: embedded ? .embeddedResult(handler: "render", payloadJSON: "{}", resultReference: nil, ownerID: "owner") : .application,
            storageAllowed: true, runtimeRoot: root)
    }

    private func checkpointAfterDisposal(_ root: URL) async throws -> UUID {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        repeat {
            if let token = try? HanlinScriptingApplicationSession.beginStorageCheckpoint(dataRoot: root.appending(path: "MiniApps")) {
                return token
            }
            try await Task.sleep(for: .milliseconds(5))
        } while ContinuousClock.now < deadline
        Issue.record("Actual native storage owners did not drain before the deadline.")
        throw HanlinScriptingStorageCheckpointError.busy
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "checkpoint-\(UUID().uuidString)", directoryHint: .isDirectory)
    }
}
