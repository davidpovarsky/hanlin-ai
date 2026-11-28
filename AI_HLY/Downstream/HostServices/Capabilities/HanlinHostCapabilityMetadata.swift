import Foundation
import HanlinPlatformContracts

public struct HanlinHostCapabilityMetadata: Sendable {
    public let id: String
    public let displayName: String
    public let risk: HanlinRiskLevel
    public let requiresSystemAuthorization: Bool
    public let systemAuthorizationDescription: String?
    
    public init(id: String, displayName: String, risk: HanlinRiskLevel, requiresSystemAuthorization: Bool = false, systemAuthorizationDescription: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.risk = risk
        self.requiresSystemAuthorization = requiresSystemAuthorization
        self.systemAuthorizationDescription = systemAuthorizationDescription
    }
    
    public static let allKnown: [HanlinHostCapabilityMetadata] = [
        // Runtimes
        .init(id: "runtime.node", displayName: "Node.js Runtime", risk: .privileged),
        .init(id: "runtime.typescript", displayName: "TypeScript Runtime", risk: .write),
        .init(id: "runtime.python", displayName: "Python Runtime", risk: .privileged),
        .init(id: "runtime.javascript", displayName: "JavaScript Runtime", risk: .write),
        .init(id: "runtime.shell", displayName: "Shell Execution", risk: .privileged),
        
        // Data
        .init(id: "storage", displayName: "Local Storage", risk: .write),
        .init(id: "files", displayName: "File System", risk: .destructive),
        .init(id: "sqlite", displayName: "SQLite Database", risk: .write),
        .init(id: "shared-data", displayName: "Shared Data", risk: .sensitiveRead),
        
        // System & Network
        .init(id: "network", displayName: "Network Access", risk: .write),
        
        // Permissions Requiring System Authorization
        .init(id: "location", displayName: "Location Services", risk: .sensitiveRead, requiresSystemAuthorization: true, systemAuthorizationDescription: "Access your current location"),
        .init(id: "calendar", displayName: "Calendar", risk: .sensitiveRead, requiresSystemAuthorization: true, systemAuthorizationDescription: "Access your calendar events"),
        .init(id: "reminders", displayName: "Reminders", risk: .write, requiresSystemAuthorization: true, systemAuthorizationDescription: "Access your reminders"),
        .init(id: "health", displayName: "Health Data", risk: .sensitiveRead, requiresSystemAuthorization: true, systemAuthorizationDescription: "Access your health data"),
        .init(id: "notifications", displayName: "Notifications", risk: .passive, requiresSystemAuthorization: true, systemAuthorizationDescription: "Send notifications"),
        .init(id: "photos", displayName: "Photos Library", risk: .sensitiveRead, requiresSystemAuthorization: true, systemAuthorizationDescription: "Access your photos"),
        .init(id: "camera", displayName: "Camera", risk: .sensitiveRead, requiresSystemAuthorization: true, systemAuthorizationDescription: "Access the camera"),
        .init(id: "microphone", displayName: "Microphone", risk: .sensitiveRead, requiresSystemAuthorization: true, systemAuthorizationDescription: "Access the microphone"),
        .init(id: "contacts", displayName: "Contacts", risk: .sensitiveRead, requiresSystemAuthorization: true, systemAuthorizationDescription: "Access your contacts"),
        .init(id: "speech-recognition", displayName: "Speech Recognition", risk: .sensitiveRead, requiresSystemAuthorization: true, systemAuthorizationDescription: "Recognize speech"),
        .init(id: "local-authentication", displayName: "Local Authentication", risk: .sensitiveRead, requiresSystemAuthorization: true, systemAuthorizationDescription: "Authenticate using biometrics"),
        
        // Other System Capabilities
        .init(id: "pasteboard", displayName: "Pasteboard", risk: .read),
        .init(id: "open-url", displayName: "Open URLs", risk: .passive),
        .init(id: "assistant", displayName: "Assistant Services", risk: .write),
        .init(id: "live-activity", displayName: "Live Activities", risk: .passive),
        .init(id: "dialog", displayName: "User Dialogs", risk: .passive),
        .init(id: "device", displayName: "Device Information", risk: .read),
        .init(id: "translation", displayName: "Translation", risk: .passive),
        .init(id: "weather", displayName: "Weather", risk: .passive),
        .init(id: "keychain", displayName: "Keychain Access", risk: .privileged),
        .init(id: "cloud", displayName: "Cloud Services", risk: .write),
        .init(id: "share-sheet", displayName: "Share Sheet", risk: .passive),
        .init(id: "maps", displayName: "Maps", risk: .passive),
        .init(id: "document-utilities", displayName: "Document Utilities", risk: .read)
    ]
    
    public static let legacyAliases: [String: String] = [
        "node": "runtime.node",
        "typescript": "runtime.typescript",
        "python": "runtime.python",
        "javascript": "runtime.javascript",
        "runtime.jsc": "runtime.javascript",
        "jsc": "runtime.javascript",
        "shell": "runtime.shell",
        "network.fetch": "network",
        "speech": "speech-recognition",
        "biometrics": "local-authentication",
        "icloud": "cloud",
        "sharesheet": "share-sheet",
        "vision": "document-utilities"
    ]
}
