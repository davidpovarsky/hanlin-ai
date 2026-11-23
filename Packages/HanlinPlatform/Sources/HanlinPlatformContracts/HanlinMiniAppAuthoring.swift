import Foundation

/// Compiler and package diagnostics shared by the authoring tools, importer and repair sheet.
/// Locations are one-based UTF-16 TypeScript positions. Missing locations stay absent.
public struct HanlinMiniAppAuthoringDiagnostic: Codable, Hashable, Identifiable, Sendable {
    public let code: String
    public let category: String
    public let message: String
    public let file: String?
    public let line: Int?
    public let column: Int?
    public let endLine: Int?
    public let endColumn: Int?
    public let remediation: String?

    public var id: String {
        [code, category, file ?? "", String(line ?? 0), String(column ?? 0), message].joined(separator: ":")
    }

    public init(code: String, category: String, message: String, file: String? = nil,
                line: Int? = nil, column: Int? = nil, endLine: Int? = nil,
                endColumn: Int? = nil, remediation: String? = nil) {
        self.code = code
        self.category = category
        self.message = message
        self.file = file
        self.line = line
        self.column = column
        self.endLine = endLine
        self.endColumn = endColumn
        self.remediation = remediation
    }
}

public struct HanlinMiniAppAuthoringSDK: Codable, Hashable, Sendable {
    public let packageVersions: [String: String]
    public let manifestSHA256: String?
    public let compilerVersion: String?

    public init(packageVersions: [String: String], manifestSHA256: String? = nil,
                compilerVersion: String? = nil) {
        self.packageVersions = packageVersions
        self.manifestSHA256 = manifestSHA256
        self.compilerVersion = compilerVersion
    }
}


/// Exact effective compiler policy. Consuming original dependency declarations is
/// distinct from rechecking the internals of those declaration packages.
public struct HanlinMiniAppTypecheckConfiguration: Codable, Hashable, Sendable {
    public let strict: Bool
    public let skipLibCheck: Bool
    public let dependencyDeclarationsChecked: Bool
    public init(strict: Bool, skipLibCheck: Bool, dependencyDeclarationsChecked: Bool) {
        self.strict = strict
        self.skipLibCheck = skipLibCheck
        self.dependencyDeclarationsChecked = dependencyDeclarationsChecked
    }
}

/// This records a compiler/package operation, never a claim that a native UI ran or installed.
/// The durable Node executionID permits reading full output without truncating diagnostics.
public struct HanlinMiniAppAuthoringReport: Codable, Hashable, Sendable {
    public let schemaVersion: Int
    public let engine: String
    public let operation: String
    public let succeeded: Bool
    public let diagnostics: [HanlinMiniAppAuthoringDiagnostic]
    public let sourceRoot: String?
    public let preparedPackagePath: String?
    public let archivePath: String?
    public let sdk: HanlinMiniAppAuthoringSDK?
    public let executionID: String?
    public let typecheck: HanlinMiniAppTypecheckConfiguration?

    public init(schemaVersion: Int = 1, engine: String, operation: String, succeeded: Bool,
                diagnostics: [HanlinMiniAppAuthoringDiagnostic], sourceRoot: String? = nil,
                preparedPackagePath: String? = nil, archivePath: String? = nil,
                sdk: HanlinMiniAppAuthoringSDK? = nil, executionID: String? = nil,
                typecheck: HanlinMiniAppTypecheckConfiguration? = nil) {
        self.schemaVersion = schemaVersion
        self.engine = engine
        self.operation = operation
        self.succeeded = succeeded
        self.diagnostics = diagnostics
        self.sourceRoot = sourceRoot
        self.preparedPackagePath = preparedPackagePath
        self.archivePath = archivePath
        self.sdk = sdk
        self.executionID = executionID
        self.typecheck = typecheck
    }

    public func withArchive(at path: String) -> Self {
        .init(schemaVersion: schemaVersion, engine: engine, operation: operation,
              succeeded: succeeded, diagnostics: diagnostics, sourceRoot: sourceRoot,
              preparedPackagePath: preparedPackagePath, archivePath: path, sdk: sdk,
              executionID: executionID, typecheck: typecheck)
    }
}

/// Source payload accepted by write_miniapp. Exactly one of content or base64 is supplied.
public struct HanlinMiniAppSourceFile: Codable, Hashable, Sendable {
    public let path: String
    public let content: String?
    public let base64: String?
    public init(path: String, content: String? = nil, base64: String? = nil) {
        self.path = path
        self.content = content
        self.base64 = base64
    }
}

public struct HanlinMiniAppSourceWriteReport: Codable, Hashable, Sendable {
    public let schemaVersion: Int
    public let succeeded: Bool
    public let projectPath: String
    public let sourceRoot: String
    public let writtenFiles: [String]
    public init(projectPath: String, sourceRoot: String, writtenFiles: [String]) {
        self.schemaVersion = 1
        self.succeeded = true
        self.projectPath = projectPath
        self.sourceRoot = sourceRoot
        self.writtenFiles = writtenFiles
    }
}
