import CryptoKit
import Foundation
import HanlinPlatformContracts

/// A system surface uses an original native widget renderer. Its source and
/// state are independent of the foreground application and WidgetKit instances.
public struct HanlinNativePresentationMetadata: Codable, Hashable, Sendable {
    public let engine: HanlinWidgetEngine
    public let sourcePath: String
    public let sourceFormat: String
    public let actions: [HanlinWidgetActionDeclaration]
    public let input: HanlinNativePresentationInput?

    public init(engine: HanlinWidgetEngine, sourcePath: String, sourceFormat: String,
                actions: [HanlinWidgetActionDeclaration] = [], input: HanlinNativePresentationInput? = nil) {
        self.engine = engine
        self.sourcePath = sourcePath
        self.sourceFormat = sourceFormat
        self.actions = actions
        self.input = input
    }

    private enum CodingKeys: String, CodingKey { case engine, sourcePath, sourceFormat, actions, input }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        engine = try values.decode(HanlinWidgetEngine.self, forKey: .engine)
        sourcePath = try values.decode(String.self, forKey: .sourcePath)
        sourceFormat = try values.decode(String.self, forKey: .sourceFormat)
        actions = try values.decodeIfPresent([HanlinWidgetActionDeclaration].self, forKey: .actions) ?? []
        input = try values.decodeIfPresent(HanlinNativePresentationInput.self, forKey: .input)
    }

    public static func declarations(in manifest: HanlinScriptingManifest) throws -> [String: Self] {
        guard let field = manifest.unknownFields["nativePresentations"] else { return [:] }
        return try JSONDecoder().decode([String: Self].self, from: field.canonicalJSONData())
    }

    public static func artifactPath(for entrypointID: String) -> String {
        let digest = SHA256.hash(data: Data(entrypointID.utf8)).map { String(format: "%02x", $0) }.joined()
        return "presentations/\(digest).json"
    }
}

public struct HanlinNativePresentationInput: Codable, Hashable, Sendable {
    public let title: String
    public let placeholder: String?
    public let submitTitle: String
    public init(title: String, placeholder: String? = nil, submitTitle: String) {
        self.title = title
        self.placeholder = placeholder
        self.submitTitle = submitTitle
    }
}
