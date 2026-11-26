import Foundation

enum HanlinComposerCapabilityError: LocalizedError {
    case unavailable(String), invalid(String), toolsUnsupported

    var errorDescription: String? {
        switch self {
        case .unavailable(let title): "The attached capability ‘\(title)’ is unavailable or changed. Select it again."
        case .invalid(let reason): reason
        case .toolsUnsupported: "Choose a model that supports tools to send these capability attachments."
        }
    }
}
