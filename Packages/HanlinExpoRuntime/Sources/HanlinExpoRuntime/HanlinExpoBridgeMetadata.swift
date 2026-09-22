import Foundation

public enum HanlinExpoBridgeMetadata {
    public static let runtimeVersion = HanlinGeneratedBridgeMetadata.runtimeVersion
    public static let bridgeVersion = HanlinGeneratedBridgeMetadata.bridgeVersion
    public static let inventoryIdentity = HanlinGeneratedBridgeMetadata.inventoryIdentity

    public static var dictionary: [String: String] {
        [
            "runtimeVersion": runtimeVersion,
            "bridgeVersion": bridgeVersion,
            "inventoryIdentity": inventoryIdentity,
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
