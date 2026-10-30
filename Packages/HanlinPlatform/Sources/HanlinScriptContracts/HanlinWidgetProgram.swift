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

    public init(engine: HanlinWidgetEngine, sourceSHA256: String, compilerSHA256: String,
                javaScript: String, actions: [HanlinWidgetActionDeclaration], families: [String], resources: [String: Data] = [:]) {
        self.abiVersion = Self.abiVersion
        self.engine = engine
        upstreamCommit = engine == .expo ? Self.expoCommit : Self.scriptWidgetCommit
        self.sourceSHA256 = sourceSHA256
        self.compilerSHA256 = compilerSHA256
        self.javaScript = javaScript
        self.actions = actions
        self.families = families
        self.resources = resources
    }

    public func validate(engine expected: HanlinWidgetEngine) throws {
        guard abiVersion == Self.abiVersion, engine == expected, engine != .legacy,
              upstreamCommit == (engine == .expo ? Self.expoCommit : Self.scriptWidgetCommit),
              Self.isSHA256(sourceSHA256), Self.isSHA256(compilerSHA256),
              javaScript.utf8.count <= 2 * 1_024 * 1_024, !javaScript.isEmpty,
              !families.isEmpty, Set(families).count == families.count,
              families.allSatisfy(Self.supportedFamilies.contains),
              Set(actions.map(\.id)).count == actions.count,
              actions.allSatisfy({ !$0.id.isEmpty && $0.id.utf8.count <= 256 }),
              actions.allSatisfy({ action in
                  switch action.kind {
                  case .function: return action.handler?.isEmpty == false
                  case .setValue: return action.stateKey?.isEmpty == false
                  case .expoCallback: return engine == .expo
                  case .reload: return true
                  }
              }),
              resources.values.reduce(0, { $0 + $1.count }) <= 1_024 * 1_024 else {
            throw HanlinWidgetProgramError.invalidProgram
        }
    }

    public static let supportedFamilies = ["systemSmall", "systemMedium", "systemLarge", "systemExtraLarge"]
    public static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}

public struct HanlinWidgetActionDeclaration: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case expoCallback, function, setValue, reload }
    public let id: String
    public let kind: Kind
    public let handler: String?
    public let stateKey: String?

    public init(id: String, kind: Kind, handler: String? = nil, stateKey: String? = nil) {
        self.id = id
        self.kind = kind
        self.handler = handler
        self.stateKey = stateKey
    }
}

public enum HanlinWidgetProgramError: Error, Sendable {
    case invalidProgram, invalidSource, unsupportedImport, missingCompiler, compilationFailed(String)
}
