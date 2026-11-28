import Foundation

/// A transport projection of the producer's canonical MiniApp catalog.
/// The client never discovers, registers, or executes an engine.
public struct MiniAppCatalogItem: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let systemImage: String
    public let supportedContentTypes: [String]
    public let supportedOperations: [MiniAppOperation]
    public let actionID: String?
    public let localizedTitles: [String: String]
    /// PNG data projected from the original icon; optional for schema-v1 compatibility.
    public let iconData: Data?
    public let localizedSubtitles: [String: String]?

    public init(id: String, title: String, subtitle: String? = nil, systemImage: String = "app",
                supportedContentTypes: [String] = [],
                supportedOperations: [MiniAppOperation] = [.display], actionID: String? = nil,
                localizedTitles: [String: String] = [:], iconData: Data? = nil,
                localizedSubtitles: [String: String]? = nil) {
        self.id = id; self.title = title; self.subtitle = subtitle; self.systemImage = systemImage
        self.supportedContentTypes = supportedContentTypes; self.supportedOperations = supportedOperations
        self.actionID = actionID; self.localizedTitles = localizedTitles
        self.iconData = iconData; self.localizedSubtitles = localizedSubtitles
    }

    public func title(locale: Locale) -> String {
        localizedTitles[locale.identifier] ??
        localizedTitles[locale.language.languageCode?.identifier ?? ""] ?? title
    }

    public func subtitle(locale: Locale) -> String? {
        localizedSubtitles?[locale.identifier] ??
        localizedSubtitles?[locale.language.languageCode?.identifier ?? ""] ?? subtitle
    }

    public func accepts(_ inputs: [MiniAppContent]) -> Bool {
        guard !inputs.isEmpty, !supportedContentTypes.isEmpty else { return true }
        return inputs.contains { input in
            supportedContentTypes.contains { accepted in
                accepted == input.typeIdentifier ||
                accepted == input.kind.rawValue ||
                (accepted == "public.text" && [.text, .json].contains(input.kind)) ||
                (accepted == "public.data" && input.kind == .file) ||
                (accepted == "public.url" && input.kind == .url)
            }
        }
    }
}

public enum MiniAppOperation: String, Codable, CaseIterable, Hashable, Sendable {
    case display, insert, replaceSelection, replaceDocument, custom
}

public struct MiniAppContent: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable { case text, url, file, json }
    public let kind: Kind
    public let text: String?
    public let url: URL?
    public let attachmentID: UUID?
    public let typeIdentifier: String?
    public let name: String?

    public init(kind: Kind, text: String? = nil, url: URL? = nil, attachmentID: UUID? = nil,
                typeIdentifier: String? = nil, name: String? = nil) {
        self.kind = kind; self.text = text; self.url = url; self.attachmentID = attachmentID
        self.typeIdentifier = typeIdentifier; self.name = name
    }
}

/// Offsets use the UTF-16 convention used by NSRange and native text editors.
public struct MiniAppTextSelection: Codable, Hashable, Sendable {
    public let location: Int
    public let length: Int
    public let text: String
    public let blockIDs: [String]
    public init(location: Int, length: Int, text: String, blockIDs: [String] = []) {
        self.location = location; self.length = length; self.text = text; self.blockIDs = blockIDs
    }
}

public struct MiniAppSourceContext: Codable, Hashable, Sendable {
    public let appID: String
    public let displayName: String
    public let documentID: String?
    public let documentTitle: String?
    public let revision: String?
    public let selection: MiniAppTextSelection?
    public let documentText: String?
    public let kind: String?
    public let locator: String?
    public let sceneID: String?
    public let metadata: [String: String]

    public init(appID: String, displayName: String, documentID: String? = nil,
                documentTitle: String? = nil, revision: String? = nil,
                selection: MiniAppTextSelection? = nil, documentText: String? = nil,
                kind: String? = nil, locator: String? = nil, sceneID: String? = nil,
                metadata: [String: String] = [:]) {
        self.appID = appID; self.displayName = displayName; self.documentID = documentID
        self.documentTitle = documentTitle; self.revision = revision; self.selection = selection
        self.documentText = documentText; self.kind = kind; self.locator = locator
        self.sceneID = sceneID; self.metadata = metadata
    }
}

public struct MiniAppCallbacks: Codable, Hashable, Sendable {
    public let success: URL?
    public let error: URL?
    public let cancel: URL?
    public init(success: URL? = nil, error: URL? = nil, cancel: URL? = nil) {
        self.success = success; self.error = error; self.cancel = cancel
    }
}

public struct MiniAppInvocation: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let appID: String
    public let actionID: String?
    public let source: MiniAppSourceContext
    public let inputs: [MiniAppContent]
    public let operation: MiniAppOperation
    public let callbacks: MiniAppCallbacks
    public let opensInNewWindow: Bool
    public let createdAt: Date

    public init(id: UUID = UUID(), appID: String, actionID: String? = nil,
                source: MiniAppSourceContext, inputs: [MiniAppContent] = [],
                operation: MiniAppOperation = .display, callbacks: MiniAppCallbacks = .init(),
                opensInNewWindow: Bool = true, createdAt: Date = .now) {
        self.id = id; self.appID = appID; self.actionID = actionID; self.source = source
        self.inputs = inputs; self.operation = operation; self.callbacks = callbacks
        self.opensInNewWindow = opensInNewWindow; self.createdAt = createdAt
    }

    public func callbackURL(for result: MiniAppResult) -> URL? {
        guard result.requestID == id else { return nil }
        let base: URL?
        switch result.status {
        case .success: base = callbacks.success
        case .error: base = callbacks.error
        case .cancelled: base = callbacks.cancel
        }
        guard let base, var parts = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        let reserved = Set(["request", "status", "errorMessage"])
        var query = (parts.queryItems ?? []).filter { !reserved.contains($0.name) }
        query += [.init(name: "request", value: id.uuidString.lowercased()),
                  .init(name: "status", value: result.status.rawValue)]
        if result.status == .error, let message = result.message {
            query.append(.init(name: "errorMessage", value: message))
        }
        parts.queryItems = query
        return parts.url
    }
}

public struct MiniAppResult: Codable, Hashable, Sendable {
    public enum Status: String, Codable, Hashable, Sendable { case success, error, cancelled }
    public let requestID: UUID
    public let status: Status
    public let operation: MiniAppOperation
    public let items: [MiniAppContent]
    public let message: String?
    public let metadata: [String: String]

    public init(requestID: UUID, status: Status = .success, operation: MiniAppOperation = .display,
                items: [MiniAppContent] = [], message: String? = nil,
                metadata: [String: String] = [:]) {
        self.requestID = requestID; self.status = status; self.operation = operation
        self.items = items; self.message = message; self.metadata = metadata
    }

    public var text: String { items.compactMap(\.text).joined(separator: "\n") }
}

public enum MiniAppBridgeError: Error, LocalizedError, Equatable, Sendable {
    case appGroupUnavailable, unsupportedSchema, duplicateIdentity, missingRequest
    case conflictingResult, wrongSource, invalidSelection, selectionChanged, invalidAttachment
    case invalidURL, duplicateCatalogIdentity

    public var errorDescription: String? {
        switch self {
        case .appGroupUnavailable: "The shared MiniApps container is unavailable."
        case .unsupportedSchema: "This MiniApps request uses an unsupported format."
        case .duplicateIdentity: "A different MiniApps request already has this identifier."
        case .missingRequest: "The original MiniApps request could not be found."
        case .conflictingResult: "This MiniApps request already has a different completed result."
        case .wrongSource: "This result belongs to a different source app."
        case .invalidSelection: "The original text selection is no longer available."
        case .selectionChanged: "The selected text changed while the MiniApp was open."
        case .invalidAttachment: "The shared attachment could not be found."
        case .invalidURL: "The MiniApps link could not be created."
        case .duplicateCatalogIdentity: "The MiniApps catalog contains a duplicate app identifier."
        }
    }
}
