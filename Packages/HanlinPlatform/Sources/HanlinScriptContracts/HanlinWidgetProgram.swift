import Foundation
import HanlinPlatformContracts

/// Immutable install-time output. Source formats are declared by metadata, never
/// guessed by looking for '<' in JavaScript strings.
public struct HanlinWidgetProgram: Codable, Hashable, Sendable {
    public static let abiVersion: UInt32 = 1
    public static let expoCommit = "917a61b581baeb852aa4fe331da2c1395d824351"
    public static let scriptWidgetCommit = "68f04194f00222558c44d5a832e7617a96f62574"

    public let abiVersion: UInt32
    public let engine: HanlinWidgetEngine
    public let upstreamCommit: String
    public let sourceSHA256: String
    public let compilerSHA256: String
    public let javaScript: String
    public let actions: [HanlinWidgetActionDeclaration]
    public let families: [String]
    public let resources: [String: Data]
    public let imports: [String: String]

    public init(engine: HanlinWidgetEngine, sourceSHA256: String, compilerSHA256: String,
                javaScript: String, actions: [HanlinWidgetActionDeclaration], families: [String], resources: [String: Data] = [:], imports: [String: String] = [:]) {
        self.abiVersion = Self.abiVersion
        self.engine = engine
        upstreamCommit = engine == .expo ? Self.expoCommit : Self.scriptWidgetCommit
        self.sourceSHA256 = sourceSHA256
        self.compilerSHA256 = compilerSHA256
        self.javaScript = javaScript
        self.actions = actions
        self.families = families
        self.resources = resources
        self.imports = imports
    }

    public func validate(engine expected: HanlinWidgetEngine) throws {
        guard abiVersion == Self.abiVersion, engine == expected, engine != .legacy,
              upstreamCommit == (engine == .expo ? Self.expoCommit : Self.scriptWidgetCommit),
              Self.isSHA256(sourceSHA256), Self.isSHA256(compilerSHA256),
              !javaScript.isEmpty,
              !families.isEmpty, Set(families).count == families.count,
              families.allSatisfy(Self.supportedFamilies.contains),
              Set(actions.map(\.id)).count == actions.count,
              actions.allSatisfy({ !$0.id.isEmpty && $0.id.utf8.count <= 256 }),
              actions.allSatisfy({ action in
                  guard action.kind == .hostAction || action.hostAction == nil else { return false }
                  switch action.kind {
                  case .function: return action.handler?.isEmpty == false
                  case .setValue: return action.stateKey?.isEmpty == false
                  case .expoCallback: return engine == .expo
                  case .reload: return true
                  case .hostAction:
                      guard action.handler == nil, action.stateKey == nil,
                            let target = action.hostAction else { return false }
                      return !target.entrypointID.isEmpty && target.entrypointID.utf8.count <= 128
                          && (try? HanlinActionID(validating: target.actionName)) != nil
                  }
              }) else {
            throw HanlinWidgetProgramError.invalidProgram
        }
    }

    public static let supportedFamilies = ["systemSmall", "systemMedium", "systemLarge", "systemExtraLarge"]
    public static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}

public struct HanlinWidgetActionDeclaration: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case expoCallback, function, setValue, reload, hostAction }
    public let id: String
    public let kind: Kind
    public let handler: String?
    public let stateKey: String?
    public let hostAction: HanlinWidgetHostAction?

    public init(id: String, kind: Kind, handler: String? = nil, stateKey: String? = nil,
                hostAction: HanlinWidgetHostAction? = nil) {
        self.id = id
        self.kind = kind
        self.handler = handler
        self.stateKey = stateKey
        self.hostAction = hostAction
    }
}

public enum HanlinWidgetProgramError: Error, Sendable {
    case invalidProgram, invalidSource, unsupportedImport, missingCompiler, compilationFailed(String)
}


/// A declared package action continued by the owning foreground Host.
/// Parameters use ordinary manifest JSON, not the internal tagged value wire.
public struct HanlinWidgetHostAction: Codable, Hashable, Sendable {
    public let entrypointID: String
    public let actionName: String
    public let parameters: HanlinJSONValue?

    public init(entrypointID: String, actionName: String, parameters: HanlinJSONValue? = nil) {
        self.entrypointID = entrypointID
        self.actionName = actionName
        self.parameters = parameters
    }

    private enum CodingKeys: String, CodingKey { case entrypointID, actionName, parameters }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entrypointID = try container.decode(String.self, forKey: .entrypointID)
        actionName = try container.decode(String.self, forKey: .actionName)
        // decodeIfPresent would erase an explicitly authored JSON null.
        parameters = container.contains(.parameters)
            ? try container.decode(ManifestJSONValue.self, forKey: .parameters).value : nil
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(entrypointID, forKey: .entrypointID)
        try container.encode(actionName, forKey: .actionName)
        if let parameters {
            try container.encode(ManifestJSONValue(parameters), forKey: .parameters)
        }
    }
}
