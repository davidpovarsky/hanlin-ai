import Foundation

enum ToolActivityPresentationKind: String, Codable, Hashable, Sendable {
    case search
    case retrieve
    case read
    case write
    case execute
    case calculate
    case navigate
    case generate
    case communicate
    case inspect
    case generic
}

struct ToolActivityPresentationDescriptor: Codable, Hashable, Sendable {
    var kind: ToolActivityPresentationKind
    var systemImage: String
    var runningTitle: String
    var completedTitle: String
    var failedTitle: String
    var visibleArgumentKeys: [String]
}

enum ToolResultRendererKind: String, Codable, Hashable, Sendable {
    case modernNative
    case legacyExisting
}

struct ToolResultPresentationDescriptor: Codable, Hashable, Sendable {
    var rendererKind: ToolResultRendererKind
    var supportsCard: Bool
}

enum ToolResultDisplayPolicy: String, Codable, Hashable, Sendable {
    case never
    case modelControlled
    case always
}

enum ToolResultPresentationRequest: String, Codable, Hashable, Sendable {
    case none
    case card
}

struct ToolPresentationProfile: Codable, Hashable, Sendable {
    var identity: String
    var activity: ToolActivityPresentationDescriptor
    var result: ToolResultPresentationDescriptor?
    var resultDisplayPolicy: ToolResultDisplayPolicy

    static func generic(toolName: String) -> ToolPresentationProfile {
        ToolPresentationProfile(
            identity: "generic.\(toolName)",
            activity: ToolActivityPresentationDescriptor(
                kind: .generic,
                systemImage: "sparkles",
                runningTitle: String(localized: "Using a tool"),
                completedTitle: String(localized: "Used a tool"),
                failedTitle: String(localized: "Tool failed"),
                visibleArgumentKeys: []
            ),
            result: nil,
            resultDisplayPolicy: .never
        )
    }

    static func modernNative(
        toolName: String,
        kind: ToolActivityPresentationKind,
        systemImage: String,
        runningTitle: LocalizedStringResource,
        completedTitle: LocalizedStringResource,
        failedTitle: LocalizedStringResource = "Tool failed",
        visibleArgumentKeys: [String],
        supportsCard: Bool = true
    ) -> ToolPresentationProfile {
        ToolPresentationProfile(
            identity: "native.\(toolName)",
            activity: ToolActivityPresentationDescriptor(
                kind: kind,
                systemImage: systemImage,
                runningTitle: String(localized: runningTitle),
                completedTitle: String(localized: completedTitle),
                failedTitle: String(localized: failedTitle),
                visibleArgumentKeys: visibleArgumentKeys
            ),
            result: supportsCard
                ? ToolResultPresentationDescriptor(rendererKind: .modernNative, supportsCard: true)
                : nil,
            resultDisplayPolicy: supportsCard ? .modelControlled : .never
        )
    }
}

extension ToolActivityPresentationKind {
    var agentActivityKind: AgentActivityKind {
        switch self {
        case .search: .webSearch
        case .retrieve, .read: .sourceRead
        case .execute, .calculate: .codeExecution
        case .navigate: .map
        case .write, .generate, .communicate, .inspect, .generic: .toolExecution
        }
    }

    var displayActivityKind: AgentDisplayActivityKind {
        switch self {
        case .search: .search
        case .retrieve, .read: .source
        case .execute, .calculate: .code
        case .navigate: .map
        case .write, .generate, .communicate, .inspect, .generic: .tool
        }
    }
}
