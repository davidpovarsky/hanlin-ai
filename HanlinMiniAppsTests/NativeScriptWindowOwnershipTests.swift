import Foundation
import XCTest
@testable import HanlinMiniApps

@MainActor
final class NativeScriptWindowOwnershipTests: XCTestCase {
    func testUnrelatedAndLateWindowCleanupPreservesNativeScriptOwner() throws {
        let firstID = "window-owner-\(UUID().uuidString.lowercased())"
        let secondID = "window-successor-\(UUID().uuidString.lowercased())"
        HanlinNativeServicesHostProvider.setActiveContainer(
            appID: firstID, dataRoot: "/window-one",
            stateDir: "/window-one/state", docsDir: "/window-one/docs",
            cacheDir: "/window-one/cache", sessionID: firstID)
        defer { _ = HanlinNativeServicesHostProvider.clearActiveContainer(forSessionID: firstID) }
        let firstBridge = try XCTUnwrap(HanlinNativeServicesBridge.activeSessionBridge())
        let firstProvider = try XCTUnwrap(HanlinNativeServicesBridge.legacyProvider())
        let firstRoot = try XCTUnwrap(firstBridge.dataRootDirectory())
        defer { removeOwnedTestContainer(dataRoot: firstRoot, appID: firstID) }

        XCTAssertFalse(HanlinNativeServicesHostProvider.clearActiveContainer(forSessionID: "unrelated-script-ui-window"))
        XCTAssertTrue(HanlinNativeServicesBridge.activeSessionBridge() === firstBridge)
        XCTAssertEqual(HanlinNativeServicesBridge.dataRootDirectory(), firstRoot)
        XCTAssertEqual(HanlinNativeServicesHostProvider.activeDataRoot, "/window-one")
        XCTAssertTrue(HanlinNativeServicesBridge.legacyProvider() === firstProvider)

        XCTAssertTrue(HanlinNativeServicesHostProvider.clearActiveContainer(forSessionID: firstID))
        HanlinNativeServicesHostProvider.setActiveContainer(
            appID: secondID, dataRoot: "/window-two",
            stateDir: "/window-two/state", docsDir: "/window-two/docs",
            cacheDir: "/window-two/cache", sessionID: secondID)
        defer { _ = HanlinNativeServicesHostProvider.clearActiveContainer(forSessionID: secondID) }
        let secondBridge = try XCTUnwrap(HanlinNativeServicesBridge.activeSessionBridge())
        let secondProvider = try XCTUnwrap(HanlinNativeServicesBridge.legacyProvider())
        let secondRoot = try XCTUnwrap(secondBridge.dataRootDirectory())
        defer { removeOwnedTestContainer(dataRoot: secondRoot, appID: secondID) }
        XCTAssertNotEqual(firstRoot, secondRoot)

        // A stale close callback must not revoke its successor's bridge or paths.
        XCTAssertFalse(HanlinNativeServicesHostProvider.clearActiveContainer(forSessionID: firstID))
        HanlinNativeServicesBridge.clearLegacyProvider(ifMatches: firstProvider)
        XCTAssertTrue(HanlinNativeServicesBridge.activeSessionBridge() === secondBridge)
        XCTAssertTrue(HanlinNativeServicesBridge.legacyProvider() === secondProvider)
        XCTAssertEqual(HanlinNativeServicesBridge.dataRootDirectory(), secondRoot)
        XCTAssertEqual(HanlinNativeServicesHostProvider.activeDataRoot, "/window-two")

        XCTAssertTrue(HanlinNativeServicesHostProvider.clearActiveContainer(forSessionID: secondID))
        XCTAssertNil(HanlinNativeServicesBridge.activeSessionBridge())
        XCTAssertNil(HanlinNativeServicesBridge.legacyProvider())
    }

    private func removeOwnedTestContainer(dataRoot: String, appID: String) {
        let directory = URL(fileURLWithPath: dataRoot).deletingLastPathComponent()
        guard directory.lastPathComponent == appID else { return }
        try? FileManager.default.removeItem(at: directory)
    }
}
