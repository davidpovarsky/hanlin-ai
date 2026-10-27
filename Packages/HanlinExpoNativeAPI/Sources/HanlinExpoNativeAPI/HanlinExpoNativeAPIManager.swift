import Foundation
import UIKit
import HanlinExpoNativeAPICore

public struct HanlinExpoNativeAPIMetadata: Sendable {
    public static let nativeApiVersion = "9.1.2"
    public static let workletsVersion = "0.13.1"
    public static let contractVersion = "1.0.0"
    public static let reactNativeVersion = "0.88.0"
    public static let nativeApiSupported = true
}

@MainActor
public final class HanlinExpoNativeAPIManager {
    public static func resolveBundledMetadataPath() -> String? {
        #if targetEnvironment(simulator)
        #if arch(x86_64)
        let name = "metadata.ios-sim.x86_64"
        #else
        let name = "metadata.ios-sim.arm64"
        #endif
        #else
        let name = "metadata.ios.arm64"
        #endif
        if let url = Bundle.module.url(forResource: name, withExtension: "nsmd", subdirectory: "metadata") ??
                     Bundle.module.url(forResource: name, withExtension: "nsmd") {
            return url.path
        }
        return nil
    }

    public static func registerSession(
        sessionID: String,
        packageID: String,
        isGranted: Bool,
        generation: UInt64 = 0
    ) {
        if let metaPath = resolveBundledMetadataPath() {
            HanlinExpoNativeAPIGate.setBundledMetadataPathOverride(metaPath)
        }
        let context = HanlinExpoNativeAPISessionContext(
            sessionID: sessionID,
            packageID: packageID,
            isNativeAPIGranted: isGranted,
            generation: generation
        )
        HanlinExpoNativeAPIGate.registerActiveSessionContext(context)
    }

    public static func bindRuntime(_ runtimePointer: UnsafeMutableRawPointer?, forSessionID sessionID: String) {
        HanlinExpoNativeAPIGate.bindRuntime(runtimePointer, forSessionID: sessionID)
    }

    public static func revokeSession(sessionID: String) {
        HanlinExpoNativeAPIGate.revokeSession(sessionID)
    }

    public static func revokeActiveSession() {
        HanlinExpoNativeAPIGate.revokeActiveSession()
    }

    public static func isAuthorized() -> Bool {
        return HanlinExpoNativeAPIGate.isNativeAPIAuthorizedForCurrentSession()
    }

    public static func isAuthorized(forRuntime runtimePointer: UnsafeMutableRawPointer?) -> Bool {
        return HanlinExpoNativeAPIGate.isNativeAPIAuthorized(forRuntime: runtimePointer)
    }

    public static func dependencyProvider() -> AnyObject {
        return HanlinExpoDependencyProvider.shared()
    }

    public static func thirdPartyFabricComponents() -> [String: AnyClass] {
        return HanlinExpoDependencyProvider.shared().thirdPartyFabricComponents()
    }
}
