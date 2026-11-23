import Foundation

/// Immutable, process-bundle configuration shared by the app and its extensions.
/// Each executable supplies its own dictionary and entitlements. No SDK singleton
/// installs a different application's App Group underneath an active request.
public struct HanlinExtensionHostConfiguration: Hashable, Sendable {
    public static let infoDictionaryKey = "HanlinExtensionHost"
    public static let hanlinAppGroupIdentifier = "group.com.itorah.chavrusachat"
    public static let hanlinWidgetKind = "com.hanlin.scripting.widget"

    public let appGroupIdentifier: String?
    public let widgetKind: String?
    public let notificationCategoryIdentifier: String?
    public let visionURL: URL?
    /// Relative product storage below the shared App Group container.
    public let storageNamespace: String?

    public init(appGroupIdentifier: String? = nil, widgetKind: String? = nil,
                notificationCategoryIdentifier: String? = nil, visionURL: URL? = nil,
                storageNamespace: String? = nil) {
        self.appGroupIdentifier = appGroupIdentifier
        self.widgetKind = widgetKind
        self.notificationCategoryIdentifier = notificationCategoryIdentifier
        self.visionURL = visionURL
        self.storageNamespace = storageNamespace
    }

    /// Explicit original-app policy. Other hosts supply their own configuration.
    public static var hanlin: Self {
        .init(appGroupIdentifier: hanlinAppGroupIdentifier,
              widgetKind: hanlinWidgetKind,
              notificationCategoryIdentifier: "CHAVRUSA_REMINDER",
              visionURL: URL(string: "chavrusachat://openVisionView"))
    }

    public static var miniapps: Self {
        .init(appGroupIdentifier: hanlinAppGroupIdentifier,
              widgetKind: hanlinWidgetKind,
              notificationCategoryIdentifier: "CHAVRUSA_REMINDER",
              storageNamespace: "HanlinMiniApps/v1")
    }

    /// Both the host app and its extensions resolve the same product container.
    /// No fallback into a sibling product's installed packages or receipts.
    public func storageContainer(in appGroupContainer: URL) throws -> URL {
        let container = appGroupContainer.resolvingSymlinksInPath().standardizedFileURL
        guard let storageNamespace else { return container }
        let parts = storageNamespace.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              !storageNamespace.contains("\\"), !storageNamespace.contains("\0") else {
            throw HanlinExtensionConfigurationError.invalidConfiguration
        }
        let product = container.appending(path: storageNamespace, directoryHint: .isDirectory)
        guard product.resolvingSymlinksInPath().standardizedFileURL.path == product.standardizedFileURL.path else {
            throw HanlinExtensionConfigurationError.invalidConfiguration
        }
        return product
    }

    /// Reads only the current executable's declared configuration. A missing or
    /// malformed dictionary never falls back to Hanlin's container or URL.
    public static func load(from bundle: Bundle = .main) throws -> Self {
        guard let raw = bundle.object(forInfoDictionaryKey: infoDictionaryKey) else {
            throw HanlinExtensionConfigurationError.notConfigured
        }
        guard let dictionary = raw as? [String: Any] else {
            throw HanlinExtensionConfigurationError.invalidConfiguration
        }
        return try Self(infoDictionary: dictionary)
    }

    public init(infoDictionary: [String: Any]) throws {
        func string(_ key: String) throws -> String? {
            guard let value = infoDictionary[key] else { return nil }
            guard let text = value as? String, !text.isEmpty,
                  text == text.trimmingCharacters(in: .whitespacesAndNewlines),
                  text.utf8.count <= 4_096 else {
                throw HanlinExtensionConfigurationError.invalidConfiguration
            }
            return text
        }
        let group = try string("AppGroupIdentifier")
        let kind = try string("WidgetKind")
        let category = try string("NotificationCategoryIdentifier")
        let rawVision = try string("VisionURL")
        let vision: URL?
        if let rawVision {
            guard let parsed = URL(string: rawVision), let scheme = parsed.scheme, !scheme.isEmpty else {
                throw HanlinExtensionConfigurationError.invalidConfiguration
            }
            vision = parsed
        } else { vision = nil }
        let namespace = try string("StorageNamespace")
        self.init(appGroupIdentifier: group, widgetKind: kind,
                  notificationCategoryIdentifier: category, visionURL: vision, storageNamespace: namespace)
        _ = try storageContainer(in: URL(filePath: "/"))
    }

    public func requireAppGroupIdentifier() throws -> String {
        guard let appGroupIdentifier, !appGroupIdentifier.isEmpty else {
            throw HanlinExtensionConfigurationError.appGroupNotConfigured
        }
        return appGroupIdentifier
    }

    public func requireWidgetKind() throws -> String {
        guard let widgetKind, !widgetKind.isEmpty else {
            throw HanlinExtensionConfigurationError.widgetKindNotConfigured
        }
        return widgetKind
    }
}

public enum HanlinExtensionConfigurationError: Error, LocalizedError, Sendable {
    case notConfigured, invalidConfiguration, appGroupNotConfigured, widgetKindNotConfigured

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Configure HanlinExtensionHost in this application's or extension's Info.plist."
        case .invalidConfiguration:
            "The host extension configuration is invalid."
        case .appGroupNotConfigured:
            "The host has not configured a shared App Group."
        case .widgetKindNotConfigured:
            "The host has not configured a widget kind."
        }
    }
}
