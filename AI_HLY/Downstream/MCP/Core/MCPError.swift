import Foundation

enum MCPError: LocalizedError, Sendable {
    case featureDisabled
    case runtimeUnavailable(String)
    case invalidPackageSpec
    case invalidServerID
    case serverNotFound
    case toolNotFound
    case incompatiblePackage([String])
    case invalidHostResponse
    case requestFailed(Int, String)
    case startupTimedOut
    case resultTooLarge
    case archiveTooLarge
    case unsafeArchivePath
    case secretUnavailable

    var errorDescription: String? {
        switch self {
        case .featureDisabled: "MCP servers are disabled."
        case .runtimeUnavailable(let reason): "The embedded MCP runtime is unavailable: \(reason)"
        case .invalidPackageSpec: "The package name, version, or archive URL is invalid."
        case .invalidServerID: "The MCP server identifier is invalid."
        case .serverNotFound: "The MCP server is not installed."
        case .toolNotFound: "The selected MCP tool is no longer available."
        case .incompatiblePackage(let reasons): "This package is not compatible: \(reasons.joined(separator: "; "))"
        case .invalidHostResponse: "The embedded Node host returned an invalid response."
        case .requestFailed(let status, let message): "MCP host request failed (\(status)): \(message)"
        case .startupTimedOut: "The embedded Node host did not start in time."
        case .resultTooLarge: "The MCP tool result exceeded the allowed size."
        case .archiveTooLarge: "The package archive exceeds the allowed size."
        case .unsafeArchivePath: "The archive contains an unsafe path."
        case .secretUnavailable: "A required secret could not be read from Keychain."
        }
    }
}
