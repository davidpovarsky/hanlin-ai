import Foundation

public enum HanlinExpoError: LocalizedError, Sendable {
    case invalidApplicationRoot(String)
    case missingPreparedFile(String)
    case unsupportedRuntimeVersion(String)
    case unsupportedPlugin(String)
    case bundleLoadingFailed(String)
    case sessionAlreadyActive
    case bootstrapFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidApplicationRoot(let reason):
            "Invalid Expo application root: \(reason)"
        case .missingPreparedFile(let file):
            "Missing prepared file: \(file)"
        case .unsupportedRuntimeVersion(let reason):
            reason
        case .unsupportedPlugin(let reason):
            reason
        case .bundleLoadingFailed(let reason):
            "Failed to load Expo JS bundle: \(reason)"
        case .sessionAlreadyActive:
            "An Expo session is already active in Hanlin."
        case .bootstrapFailed(let reason):
            "Expo runtime bootstrap failed: \(reason)"
        }
    }
}
