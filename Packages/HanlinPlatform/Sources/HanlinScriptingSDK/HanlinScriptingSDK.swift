import CryptoKit
import Foundation
import HanlinScriptContracts

public struct HanlinScriptingDeclarationEvidence: Codable, Hashable, Sendable {
    public let category: String
    public let declarationFile: String
    public let line: Int
    public let signatureHash: String
}

public struct HanlinScriptingRuntimeRegistration: Codable, Hashable, Sendable {
    public let symbol: String
    public let state: HanlinCompatibilityState
    public let operation: String
    public let capability: String?
    public let contexts: [String]
    public let declarationEvidence: [HanlinScriptingDeclarationEvidence]
}

public struct HanlinScriptingSDKMetadata: Codable, Hashable, Sendable {
    public let schemaVersion: UInt32
    public let baselineID: String
    public let baselineDigest: String
    public let typescriptVersion: String
    public let module: String
    public let records: [HanlinScriptingRuntimeRegistration]
}

public enum HanlinScriptingSDKError: Error, Equatable, Sendable {
    case missingResource(String)
    case invalidManifest
    case integrityMismatch(String)
    case invalidMetadata
}

public enum HanlinScriptingSDK {
    public static func declarations() throws -> Data {
        try verifiedResource(fileName: "scripting-foundation.d.ts")
    }

    public static func metadata() throws -> HanlinScriptingSDKMetadata {
        let data = try verifiedResource(fileName: "runtime-registration.json")
        let value = try JSONDecoder().decode(HanlinScriptingSDKMetadata.self, from: data)
        guard value.schemaVersion == 1,
              value.typescriptVersion == "7.0.2",
              value.module == "scripting",
              Set(value.records.map(\.symbol)).count == value.records.count
        else { throw HanlinScriptingSDKError.invalidMetadata }
        return value
    }

    public static func manifestData() throws -> Data {
        guard let url = Bundle.module.url(forResource: "manifest", withExtension: "json") else {
            throw HanlinScriptingSDKError.missingResource("manifest.json")
        }
        return try Data(contentsOf: url)
    }

    private static func verifiedResource(fileName: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: fileName, withExtension: nil) else {
            throw HanlinScriptingSDKError.missingResource(fileName)
        }
        let manifest = try JSONDecoder().decode(
            Manifest.self,
            from: manifestData()
        )
        guard manifest.schemaVersion == 1,
              let expected = manifest.files[fileName]
        else { throw HanlinScriptingSDKError.invalidManifest }
        let data = try Data(contentsOf: url)
        guard sha256(data) == expected else {
            throw HanlinScriptingSDKError.integrityMismatch(fileName)
        }
        return data
    }

    private struct Manifest: Codable {
        let schemaVersion: UInt32
        let baselineID: String
        let files: [String: String]
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
