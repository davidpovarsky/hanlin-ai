import Foundation
import HanlinPlatformContracts

public enum HanlinExpoBridgeMetadata {
    public static let runtimeVersion = HanlinExpoHostVersions.runtimeVersion
    public static let bridgeVersion = HanlinGeneratedBridgeMetadata.bridgeVersion
    public static let inventoryIdentity = HanlinGeneratedBridgeMetadata.inventoryIdentity

    public static let nativeApiVersion = HanlinExpoHostVersions.nativeApiVersion
    public static let workletsVersion = HanlinExpoHostVersions.workletsVersion
    public static let nativeApiAbiIdentity = HanlinExpoHostVersions.nativeApiAbiIdentity
    public static let nativeApiSupported = true
    public static let nativeApiMetadataIdentity = "nsmd-ios27-v1"

    public static var dictionary: [String: Any] {
        [
            "runtimeVersion": runtimeVersion,
            "bridgeVersion": bridgeVersion,
            "inventoryIdentity": inventoryIdentity,
            "nativeApiVersion": nativeApiVersion,
            "workletsVersion": workletsVersion,
            "nativeApiAbiIdentity": nativeApiAbiIdentity,
            "nativeApiSupported": nativeApiSupported,
            "nativeApiMetadataIdentity": nativeApiMetadataIdentity,
        ]
    }

    static func supports(requiredBridgeVersion: String) -> Bool {
        HanlinPreparedRuntimeVersion.supportsMinimum(requiredBridgeVersion, installed: bridgeVersion, requireSameMajor: false)
    }
}
