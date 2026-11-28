import Foundation
import HanlinNativeScriptCoreSupport
import HanlinNativeScriptRuntime
import HanlinPlatformContracts
import Testing
@testable import AI_Hanlin

@MainActor
extension HanlinUnifiedHostServicesE2ETests {
    @Test func onlyTheStartedNativeScriptSessionRestoresItsExactPreviousEnvironment() throws {
        let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let existing = "HANLIN_ENV_EXISTING_" + nonce, added = "HANLIN_ENV_ADDED_" + nonce
        let original = "original שלום🙂"
        setenv(existing, original, 1); unsetenv(added)
        defer { unsetenv(existing); unsetenv(added) }
        let first = try environmentFixture(source: "console.log('ACTUAL_ENV_OWNER_READY')")
        defer { try? FileManager.default.removeItem(at: first) }
        let adapter = NativeScriptHostServicesAdapter(appID: try HanlinAppID(validating: "env-owner-\(nonce.lowercased())"), grantedCapabilities: [])
        HanlinNativeServicesBridge.register(adapter, forSessionID: adapter.sessionID)
        defer { HanlinNativeServicesBridge.unregisterProvider(forSessionID: adapter.sessionID) }
        let active = try HanlinNativeScriptSession(applicationRoot: first, environment: [existing: "active", added: "owned"], sessionID: adapter.sessionID)
        defer { active.shutdown() }
        try active.start()
        #expect(environmentValue(existing) == "active" && environmentValue(added) == "owned")
        let dormant = try HanlinNativeScriptSession(applicationRoot: first, environment: [existing: "dormant", added: "wrong"])
        #expect(throws: HanlinNativeScriptError.self) { try dormant.start() }
        dormant.shutdown()
        #expect(environmentValue(existing) == "active" && environmentValue(added) == "owned")
        active.shutdown()
        #expect(environmentValue(existing) == original && environmentValue(added) == nil)
        // Shutdown remains idempotent and cannot erase a subsequently changed
        // Host value after this session has already relinquished ownership.
        setenv(existing, "host-after-shutdown", 1)
        active.shutdown()
        #expect(environmentValue(existing) == "host-after-shutdown")
    }

    @Test func failedNativeScriptBootstrapRollsBackEnvironmentWithoutKeepingAFalseOwner() throws {
        let key = "HANLIN_ENV_FAILURE_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        setenv(key, "before", 1)
        defer { unsetenv(key) }
        let root = try environmentFixture(source: "throw new Error('EXPECTED_ENV_BOOTSTRAP_FAILURE')")
        defer { try? FileManager.default.removeItem(at: root) }
        let adapter = NativeScriptHostServicesAdapter(appID: try HanlinAppID(validating: "env-failure-\(UUID().uuidString.lowercased())"), grantedCapabilities: [])
        HanlinNativeServicesBridge.register(adapter, forSessionID: adapter.sessionID)
        defer { HanlinNativeServicesBridge.unregisterProvider(forSessionID: adapter.sessionID) }
        let session = try HanlinNativeScriptSession(applicationRoot: root, environment: [key: "during"], sessionID: adapter.sessionID)
        #expect(throws: HanlinNativeScriptError.self) { try session.start() }
        #expect(!session.isActive && environmentValue(key) == "before")
        session.shutdown()
        #expect(environmentValue(key) == "before")
        let invalid = try HanlinNativeScriptSession(applicationRoot: root, environment: ["invalid=key": "value", key: "must not replace"])
        #expect(throws: HanlinNativeScriptError.self) { try invalid.start() }
        #expect(environmentValue(key) == "before" && !invalid.isActive)
    }

    private func environmentValue(_ key: String) -> String? { getenv(key).map { String(cString: $0) } }

    private func environmentFixture(source: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "ns-env-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try Data(#"{"name":"env-fixture","type":"module","main":"bundle.mjs","hanlinRuntime":"hanlin-nativescript"}"#.utf8)
            .write(to: root.appending(path: "package.json"))
        try Data(source.utf8).write(to: root.appending(path: "bundle.mjs"))
        return root
    }
}
