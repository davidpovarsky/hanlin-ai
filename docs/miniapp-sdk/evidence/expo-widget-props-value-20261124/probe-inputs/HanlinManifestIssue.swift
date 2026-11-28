public enum HanlinManifestIssueCode: String, Codable, Hashable, Sendable {
    case unsupportedManifestVersion
    case unsupportedAPIVersion
    case missingEntryPoint
    case unsafeEntryPoint
    case missingExecutionContext
    case duplicateExecutionContext
    case duplicateEntryPoint
    case duplicateRoute
    case duplicateAction
    case duplicateTool
    case duplicateSkill
    case duplicateCapability
    case duplicateDependency
    case invalidAuthor
    case missingDistributionMode
    case duplicateDistributionMode
    case invalidIntegrity
    case invalidSchema
    case invalidRuntime
    case unsupportedScriptABI
    case invalidCompiler
    case missingScriptTool
}

public struct HanlinManifestIssue: Codable, Hashable, Sendable {
    public let code: HanlinManifestIssueCode
    public let path: String
    public let message: String

    public init(code: HanlinManifestIssueCode, path: String, message: String) {
        self.code = code
        self.path = path
        self.message = message
    }
}
