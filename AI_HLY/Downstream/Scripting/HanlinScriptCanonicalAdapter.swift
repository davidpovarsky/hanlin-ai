import CryptoKit
import Foundation
import HanlinPlatformContracts

@MainActor
enum HanlinScriptCanonicalAdapter {
    static func project(
        _ snapshots: [HanlinScriptProviderSnapshot]
    ) throws -> [HanlinCanonicalToolAuthority.ScriptSource] {
        try snapshots.map { snapshot in
            let descriptor = HanlinToolDescriptor(
                logicalID: HanlinLogicalToolID(
                    providerInstanceID: snapshot.providerInstanceID,
                    localToolID: snapshot.tool.id
                ),
                descriptorRevision: snapshot.descriptorRevision,
                owner: .package(snapshot.packageID),
                title: snapshot.tool.title,
                summary: snapshot.tool.summary,
                inputSchema: snapshot.tool.inputSchema,
                outputSchema: snapshot.tool.outputSchema,
                capabilities: snapshot.tool.requiredCapabilities,
                risk: snapshot.tool.risk,
                presentation: .init(compactStyle: .automatic)
            )
            let parametersData = try snapshot.tool.inputSchema.canonicalJSONData()
            guard let parameters = try JSONSerialization.jsonObject(
                with: parametersData
            ) as? [String: Any] else {
                throw HanlinScriptingError.invalidPackage("input_schema_projection")
            }
            let alias = preferredAlias(
                packageID: snapshot.packageID,
                localToolID: snapshot.tool.id,
                providerInstanceID: snapshot.providerInstanceID
            )
            let summary = snapshot.tool.summary.values[
                snapshot.tool.summary.fallbackLocale
            ] ?? snapshot.tool.id.rawValue
            return HanlinCanonicalToolAuthority.ScriptSource(
                descriptor: descriptor,
                preferredAlias: alias,
                modelSchema: [
                    "type": "function",
                    "function": [
                        "name": alias,
                        "description": summary,
                        "parameters": parameters
                    ]
                ],
                backendRoute: snapshot.route,
                presentationProfile: .generic(toolName: snapshot.tool.id.rawValue),
                resultTitle: snapshot.tool.title.values[
                    snapshot.tool.title.fallbackLocale
                ]
            )
        }
    }

    private static func preferredAlias(
        packageID: HanlinPackageID,
        localToolID: HanlinToolID,
        providerInstanceID: HanlinProviderInstanceID
    ) -> String {
        let base = "script__\(slug(packageID.rawValue))__\(slug(localToolID.rawValue))"
        guard base.count > 64 else { return base }
        let digest = SHA256.hash(data: Data(
            "\(providerInstanceID.rawValue)|\(localToolID.rawValue)".utf8
        )).prefix(4).map { String(format: "%02x", $0) }.joined()
        return "\(base.prefix(55))_\(digest)"
    }

    private static func slug(_ value: String) -> String {
        var result = value.lowercased().unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar)
                ? Character(String(scalar))
                : "_"
        }.reduce(into: "") { $0.append($1) }
        result = result.replacingOccurrences(
            of: "_+",
            with: "_",
            options: .regularExpression
        ).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return result.isEmpty ? "tool" : result
    }
}
