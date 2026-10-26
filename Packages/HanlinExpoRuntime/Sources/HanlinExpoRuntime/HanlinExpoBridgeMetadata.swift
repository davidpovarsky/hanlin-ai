import Foundation

public enum HanlinExpoBridgeMetadata {
    public static let runtimeVersion = HanlinGeneratedBridgeMetadata.runtimeVersion
    public static let bridgeVersion = HanlinGeneratedBridgeMetadata.bridgeVersion
    public static let inventoryIdentity = HanlinGeneratedBridgeMetadata.inventoryIdentity

    public static let nativeApiVersion = "9.1.2"
    public static let workletsVersion = "0.13.1"
    public static let nativeApiAbiIdentity = "rn0.88.0-hermes260318099.0.4"
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
        let required = versionComponents(requiredBridgeVersion)
        let installed = versionComponents(bridgeVersion)
        for (requiredPart, installedPart) in zip(required, installed) {
            if requiredPart != installedPart { return requiredPart < installedPart }
        }
        return true
    }

    private static func versionComponents(_ version: String) -> [Int] {
        let values = version.split(separator: ".").prefix(3).map { Int($0) ?? Int.max }
        return values + Array(repeating: 0, count: max(0, 3 - values.count))
    }
}
