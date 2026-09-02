import Foundation

public enum HanlinNativeScriptError: Error, Equatable, LocalizedError, Sendable {
    case invalidApplicationRoot(String)
    case missingPreparedFile(String)
    case unsupportedNativePlugin(String)
    case sessionAlreadyActive
    case bootstrapFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidApplicationRoot(reason):
            "Invalid NativeScript application root: \(reason)"
        case let .missingPreparedFile(path):
            "Prepared NativeScript payload is missing \(path)."
        case let .unsupportedNativePlugin(message):
            "Unsupported NativeScript native plugin: \(message)"
        case .sessionAlreadyActive:
            "A NativeScript foreground session is already active."
        case let .bootstrapFailed(message):
            "NativeScript bootstrap failed: \(message)"
        }
    }
}
