import Foundation
import UIKit

public struct HanlinExpoNativeAPIMetadata: Sendable {
    public static let nativeApiVersion = "9.1.2"
    public static let workletsVersion = "0.13.1"
    public static let contractVersion = "1.0.0"
    public static let reactNativeVersion = "0.88.0"
    public static let nativeApiSupported = true
}

@MainActor
public final class HanlinExpoNativeAPIManager {
    public static func registerSession(sessionID: String, packageID: String, isGranted: Bool) {
        let context = HanlinExpoNativeAPISessionContext(
            sessionID: sessionID,
            packageID: packageID,
            isNativeAPIGranted: isGranted
        )
        HanlinExpoNativeAPIGate.registerActiveSessionContext(context)
    }

    public static func revokeSession(sessionID: String) {
        HanlinExpoNativeAPIGate.revokeSession(sessionID)
    }

    public static func isAuthorized() -> Bool {
        return HanlinExpoNativeAPIGate.isNativeAPIAuthorizedForCurrentSession()
    }

    public static func dependencyProvider() -> AnyObject {
        return HanlinExpoDependencyProvider.shared()
    }

    public static func thirdPartyFabricComponents() -> [String: AnyClass] {
        return HanlinExpoDependencyProvider.shared().thirdPartyFabricComponents()
    }
}
