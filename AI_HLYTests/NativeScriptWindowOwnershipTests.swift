import Foundation
import HanlinNativeScriptCoreSupport
import HanlinNativeScriptRuntime
import Testing
@testable import AI_Hanlin

@MainActor
extension HanlinUnifiedHostServicesE2ETests {
    @Test func unrelatedAndLateWindowCleanupPreservesNativeScriptOwner() throws {
        let firstID = "window-owner-\(UUID().uuidString.lowercased())"
        let secondID = "window-successor-\(UUID().uuidString.lowercased())"
        HanlinNativeServicesHostProvider.setActiveContainer(
            appID: "miniapp-window-owner", dataRoot: "/window-one",
            stateDir: "/window-one/state", docsDir: "/window-one/docs",
            cacheDir: "/window-one/cache", sessionID: firstID)
        defer { _ = HanlinNativeServicesHostProvider.clearActiveContainer(forSessionID: firstID) }
        let firstBridge = try #require(HanlinNativeServicesBridge.activeSessionBridge())
        let firstProvider = try #require(HanlinNativeServicesBridge.legacyProvider())

        #expect(!HanlinNativeServicesHostProvider.clearActiveContainer(forSessionID: "unrelated-script-ui-window"))
        #expect(HanlinNativeServicesBridge.activeSessionBridge() === firstBridge)
        #expect(HanlinNativeServicesBridge.dataRootDirectory() == "/window-one")
        #expect(HanlinNativeServicesBridge.legacyProvider() === firstProvider)

        #expect(HanlinNativeServicesHostProvider.clearActiveContainer(forSessionID: firstID))
        HanlinNativeServicesHostProvider.setActiveContainer(
            appID: "miniapp-window-successor", dataRoot: "/window-two",
            stateDir: "/window-two/state", docsDir: "/window-two/docs",
            cacheDir: "/window-two/cache", sessionID: secondID)
        defer { _ = HanlinNativeServicesHostProvider.clearActiveContainer(forSessionID: secondID) }
        let secondBridge = try #require(HanlinNativeServicesBridge.activeSessionBridge())
        let secondProvider = try #require(HanlinNativeServicesBridge.legacyProvider())

        // A stale close callback from the former window must not revoke its successor.
        #expect(!HanlinNativeServicesHostProvider.clearActiveContainer(forSessionID: firstID))
        HanlinNativeServicesBridge.clearLegacyProvider(ifMatches: firstProvider)
        #expect(HanlinNativeServicesBridge.activeSessionBridge() === secondBridge)
        #expect(HanlinNativeServicesBridge.legacyProvider() === secondProvider)
        #expect(HanlinNativeServicesBridge.dataRootDirectory() == "/window-two")

        #expect(HanlinNativeServicesHostProvider.clearActiveContainer(forSessionID: secondID))
        #expect(HanlinNativeServicesBridge.activeSessionBridge() == nil)
        #expect(HanlinNativeServicesBridge.legacyProvider() == nil)
    }
}
