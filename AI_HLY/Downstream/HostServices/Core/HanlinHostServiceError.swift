import Foundation
import HanlinPlatformContracts

enum HanlinHostServiceError: Error, Sendable, LocalizedError {
    case runtimeDisabledByUser(RuntimeKind)
    case capabilityNotGranted(String)
    case systemAuthorizationDenied(String)
    case systemCapabilityUnavailable(String)
    case runtimeUnavailable(RuntimeKind)
    case runtimeRestartRequired(RuntimeKind)
    case invalidCallerContext(String)
    case pathOutOfScope(String)
    case sqliteFailure(String)
    case cancelled
    case timeout(Duration)
    case unsupportedByPlatform(String)
    case quotaExceeded(String)
    case invalidRequest(String)
    
    var errorDescription: String? {
        switch self {
        case .runtimeDisabledByUser(let kind):
            return "Runtime disabled by user: \(kind)"
        case .capabilityNotGranted(let cap):
            return "Capability not granted: \(cap)"
        case .systemAuthorizationDenied(let service):
            return "System authorization denied for: \(service)"
        case .systemCapabilityUnavailable(let service):
            return "System capability unavailable: \(service)"
        case .runtimeUnavailable(let kind):
            return "Runtime unavailable: \(kind)"
        case .runtimeRestartRequired(let kind):
            return "Runtime restart required: \(kind)"
        case .invalidCallerContext(let msg):
            return "Invalid caller context: \(msg)"
        case .pathOutOfScope(let path):
            return "Path out of scope: \(path)"
        case .sqliteFailure(let msg):
            return "SQLite failure: \(msg)"
        case .cancelled:
            return "Operation cancelled"
        case .timeout(let duration):
            return "Operation timed out after \(duration)"
        case .unsupportedByPlatform(let msg):
            return "Unsupported by platform: \(msg)"
        case .quotaExceeded(let msg):
            return "Quota exceeded: \(msg)"
        case .invalidRequest(let msg):
            return "Invalid request: \(msg)"
        }
    }
}
