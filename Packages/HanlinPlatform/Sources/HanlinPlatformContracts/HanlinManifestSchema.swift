import Foundation

public enum HanlinManifestSchema {
    public static let resourceName = "HanlinAppManifest.schema"
    public static let resourceExtension = "json"

    public static func data() throws -> Data {
        guard let url = Bundle.module.url(
            forResource: resourceName,
            withExtension: resourceExtension
        ) else {
            throw HanlinContractError.invalidSchema(
                reason: "bundled Hanlin application manifest schema is missing"
            )
        }
        return try Data(contentsOf: url)
    }
}
