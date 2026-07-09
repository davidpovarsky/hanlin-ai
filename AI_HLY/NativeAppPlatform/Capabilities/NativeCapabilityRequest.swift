import Foundation

enum NativeCapabilityID: String, Codable, Hashable, CaseIterable {
    case network
    case pasteboardRead
    case pasteboardWrite
    case contactsRead
    case contactsWrite
    case calendarRead
    case calendarWrite
    case filesRead
    case filesWrite
    case location
    case notifications
    case healthRead
    case camera
    case microphone
    case speech
    case translation

    var title: String {
        switch self {
        case .network: return "Network"
        case .pasteboardRead: return "Read Clipboard"
        case .pasteboardWrite: return "Write Clipboard"
        case .contactsRead: return "Read Contacts"
        case .contactsWrite: return "Write Contacts"
        case .calendarRead: return "Read Calendar"
        case .calendarWrite: return "Write Calendar"
        case .filesRead: return "Read Files"
        case .filesWrite: return "Write Files"
        case .location: return "Location"
        case .notifications: return "Notifications"
        case .healthRead: return "Health"
        case .camera: return "Camera"
        case .microphone: return "Microphone"
        case .speech: return "Speech"
        case .translation: return "Translation"
        }
    }
}

struct NativeCapabilityRequest: Identifiable, Hashable, Codable {
    var id: String { [capability.rawValue, domain, optional ? "optional" : "required"].compactMap { $0 }.joined(separator: ":") }
    let capability: NativeCapabilityID
    let domain: String?
    let reason: String
    let optional: Bool

    init(_ capability: NativeCapabilityID, domain: String? = nil, reason: String, optional: Bool = false) {
        self.capability = capability
        self.domain = domain
        self.reason = reason
        self.optional = optional
    }

    static func network(domain: String, reason: String, optional: Bool = false) -> NativeCapabilityRequest {
        NativeCapabilityRequest(.network, domain: domain, reason: reason, optional: optional)
    }

    static func pasteboardRead(reason: String, optional: Bool = false) -> NativeCapabilityRequest {
        NativeCapabilityRequest(.pasteboardRead, reason: reason, optional: optional)
    }

    static func pasteboardWrite(reason: String, optional: Bool = false) -> NativeCapabilityRequest {
        NativeCapabilityRequest(.pasteboardWrite, reason: reason, optional: optional)
    }
}

enum NativeCapabilityStatus: String, Codable, Hashable {
    case available
    case notRequested
    case allowed
    case denied
    case unavailable
}
