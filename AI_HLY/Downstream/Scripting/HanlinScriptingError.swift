import Foundation

enum HanlinScriptingError: Error, Equatable, LocalizedError, Sendable {
    case invalidPackage(String)
    case unsupportedABI(String)
    case compilerArtifactMismatch
    case runtimeInitializationFailed
    case moduleEvaluationFailed(String)
    case exportedToolMissing(String)
    case invalidBridgeValue(String)
    case executionTimedOut
    case cancelled
    case resourceLimit(String)
    case unavailableProvider(String)

    var errorDescription: String? {
        switch self {
        case .invalidPackage:
            "The Script package is invalid."
        case .unsupportedABI:
            "The Script package requires an unsupported ABI."
        case .compilerArtifactMismatch:
            "The Script compiler artifact failed integrity verification."
        case .runtimeInitializationFailed:
            "The isolated Script runtime could not be initialized."
        case .moduleEvaluationFailed:
            "The Script entrypoint could not be evaluated."
        case .exportedToolMissing:
            "The requested Script tool is unavailable."
        case .invalidBridgeValue:
            "A Script value cannot cross the canonical value boundary."
        case .executionTimedOut:
            "The Script tool exceeded its execution deadline."
        case .cancelled:
            "The Script tool was cancelled."
        case .resourceLimit:
            "The Script tool exceeded a resource limit."
        case .unavailableProvider:
            "The Script provider is unavailable."
        }
    }

    var diagnosticCode: String {
        switch self {
        case .invalidPackage: "invalid_package"
        case .unsupportedABI: "unsupported_abi"
        case .compilerArtifactMismatch: "compiler_artifact_mismatch"
        case .runtimeInitializationFailed: "runtime_initialization_failed"
        case .moduleEvaluationFailed: "module_evaluation_failed"
        case .exportedToolMissing: "exported_tool_missing"
        case .invalidBridgeValue: "invalid_bridge_value"
        case .executionTimedOut: "execution_timed_out"
        case .cancelled: "cancelled"
        case .resourceLimit: "resource_limit"
        case .unavailableProvider: "unavailable_provider"
        }
    }
}
