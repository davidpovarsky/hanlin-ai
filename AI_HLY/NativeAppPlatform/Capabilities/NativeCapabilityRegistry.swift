import Foundation
import UIKit

@MainActor
final class NativeCapabilityRegistry {
    static let shared = NativeCapabilityRegistry()

    private init() {}

    func status(for request: NativeCapabilityRequest) -> NativeCapabilityStatus {
        switch request.capability {
        case .network, .pasteboardRead, .pasteboardWrite, .translation:
            return .available
        default:
            return .notRequested
        }
    }

    func userFacingStatus(for request: NativeCapabilityRequest) -> String {
        switch status(for: request) {
        case .available: return "Available"
        case .notRequested: return "Not requested"
        case .allowed: return "Allowed"
        case .denied: return "Denied"
        case .unavailable: return "Unavailable"
        }
    }
}
