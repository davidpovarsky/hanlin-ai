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

    static func project(declaration: HanlinPlatformContracts.HanlinCapabilityDeclaration) -> NativeCapabilityProjectionResult {
        let rawID = declaration.id.rawValue
        let reason = declaration.reason.preferredValue(forLocale: "en")
        let optional = declaration.optional

        switch rawID {
        case "network", "network.fetch":
            var domain: String? = nil
            if case let .object(dict) = declaration.constraints,
               let domainVal = dict["domain"],
               case let .string(d) = domainVal {
                domain = d
            }
            return .supported(NativeCapabilityRequest(.network, domain: domain, reason: reason, optional: optional))
        case "pasteboard.read", "pasteboard":
            return .supported(NativeCapabilityRequest(.pasteboardRead, reason: reason, optional: optional))
        case "pasteboard.write":
            return .supported(NativeCapabilityRequest(.pasteboardWrite, reason: reason, optional: optional))
        case "contacts.read", "contacts":
            return .supported(NativeCapabilityRequest(.contactsRead, reason: reason, optional: optional))
        case "contacts.write":
            return .supported(NativeCapabilityRequest(.contactsWrite, reason: reason, optional: optional))
        case "calendar.read", "calendar":
            return .supported(NativeCapabilityRequest(.calendarRead, reason: reason, optional: optional))
        case "calendar.write":
            return .supported(NativeCapabilityRequest(.calendarWrite, reason: reason, optional: optional))
        case "files.read", "filesystem.read", "fileSystem.read", "storage.read":
            return .supported(NativeCapabilityRequest(.filesRead, reason: reason, optional: optional))
        case "files.write", "filesystem.write", "fileSystem.write", "storage.write":
            return .supported(NativeCapabilityRequest(.filesWrite, reason: reason, optional: optional))
        case "location":
            return .supported(NativeCapabilityRequest(.location, reason: reason, optional: optional))
        case "notifications":
            return .supported(NativeCapabilityRequest(.notifications, reason: reason, optional: optional))
        case "health.read", "health":
            return .supported(NativeCapabilityRequest(.healthRead, reason: reason, optional: optional))
        case "camera":
            return .supported(NativeCapabilityRequest(.camera, reason: reason, optional: optional))
        case "microphone", "audio.record", "audioRecording":
            return .supported(NativeCapabilityRequest(.microphone, reason: reason, optional: optional))
        case "speech":
            return .supported(NativeCapabilityRequest(.speech, reason: reason, optional: optional))
        case "translation":
            return .supported(NativeCapabilityRequest(.translation, reason: reason, optional: optional))
        default:
            return .unsupported(
                NativeCapabilityDiagnostic(
                    capabilityID: rawID,
                    reason: "No corresponding native capability handler supported in host environment"
                )
            )
        }
    }
}

struct NativeCapabilityDiagnostic: Hashable, CustomStringConvertible, Sendable {
    let capabilityID: String
    let reason: String

    var description: String {
        "Canonical capability '\(capabilityID)' is unsupported by host: \(reason)"
    }
}

enum NativeCapabilityProjectionResult: Hashable, Sendable {
    case supported(NativeCapabilityRequest)
    case unsupported(NativeCapabilityDiagnostic)
}

struct NativeCapabilityProjection: Hashable, Sendable {
    let supportedRequests: [NativeCapabilityRequest]
    let diagnostics: [NativeCapabilityDiagnostic]

    init(declarations: [HanlinPlatformContracts.HanlinCapabilityDeclaration]) {
        var supported: [NativeCapabilityRequest] = []
        var diags: [NativeCapabilityDiagnostic] = []
        for decl in declarations {
            switch NativeCapabilityRequest.project(declaration: decl) {
            case let .supported(req):
                supported.append(req)
            case let .unsupported(diag):
                diags.append(diag)
            }
        }
        self.supportedRequests = supported
        self.diagnostics = diags
    }

    init(supportedRequests: [NativeCapabilityRequest] = [], diagnostics: [NativeCapabilityDiagnostic] = []) {
        self.supportedRequests = supportedRequests
        self.diagnostics = diagnostics
    }

    var hasUnsupportedCapabilities: Bool {
        !diagnostics.isEmpty
    }
}

enum NativeCapabilityStatus: String, Codable, Hashable {
    case available
    case notRequested
    case allowed
    case denied
    case unavailable
}
