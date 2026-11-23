import HanlinExtensionContracts
import HanlinLocalization
import AppIntents
import HanlinPlatformContracts
import HanlinScriptExtensions

public struct HanlinScriptActionEntity: AppEntity {
    public init(id: String, displayName: String, subtitle: String? = nil,
                identity: HanlinScriptExtensionIdentity) {
        self.id = id; self.displayName = displayName
        self.subtitle = subtitle; self.identity = identity
    }

    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("Script Action", table: "HanlinAppIntents"))
    public static let defaultQuery = HanlinScriptActionEntityQuery()

    public let id: String
    public let displayName: String
    public let subtitle: String?
    public let identity: HanlinScriptExtensionIdentity

    public var displayRepresentation: DisplayRepresentation {
        if let subtitle {
            DisplayRepresentation(title: "\(displayName)", subtitle: "\(subtitle)")
        } else {
            DisplayRepresentation(title: "\(displayName)")
        }
    }
}

public struct HanlinScriptActionEntityQuery: EntityQuery {
    public init() {}

    public func entities(for identifiers: [String]) async throws -> [HanlinScriptActionEntity] {
        let all = try records()
        return all.filter { entity in
            // Exact fully-qualified scoped ID match (packageID::entrypointID::actionID)
            if identifiers.contains(entity.id) {
                return true
            }
            // Strict migration fallback: only allow short-ID match if exactly ONE entity across the entire store matches
            let shortID = entity.id.components(separatedBy: "::").last ?? ""
            if identifiers.contains(shortID) {
                let shortMatches = all.filter { ($0.id.components(separatedBy: "::").last ?? "") == shortID }
                return shortMatches.count == 1
            }
            return false
        }
    }

    public func suggestedEntities() async throws -> [HanlinScriptActionEntity] {
        try records()
    }

    private func records() throws -> [HanlinScriptActionEntity] {
        try HanlinScriptExtensionStore().load()?.intentEntities.map {
            let scopedID = "\($0.identity.packageID.rawValue)::\($0.identity.entrypointID)::\($0.id)"
            return .init(
                id: scopedID,
                displayName: $0.displayName,
                subtitle: $0.subtitle ?? $0.identity.packageID.rawValue,
                identity: $0.identity
            )
        } ?? []
    }
}

public struct HanlinRunScriptActionIntent: AppIntent {
    public init(action: HanlinScriptActionEntity, input: String = "") {
        self.action = action; self.input = input
    }

    public init() {}

    public static let title = LocalizedStringResource("Run Script Action", table: "HanlinAppIntents")
    public static let description = IntentDescription(LocalizedStringResource("Runs an action from an installed Hanlin Script package.", table: "HanlinAppIntents"))
    public static let openAppWhenRun = true

    @Parameter(title: LocalizedStringResource("Action", table: "HanlinAppIntents"))
    public var action: HanlinScriptActionEntity

    @Parameter(title: LocalizedStringResource("Input", table: "HanlinAppIntents"), default: "")
    public var input: String

    public static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$action) with \(\.$input)")
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let rawActionID = action.id.components(separatedBy: "::").last ?? action.id
        let invocation = HanlinScriptIntentInvocation(
            identity: action.identity,
            entityID: rawActionID,
            parameters: .string(input),
            continueInForeground: true
        )
        try HanlinScriptExtensionStore().enqueue(.init(invocation: invocation))
        return .result(dialog: IntentDialog(LocalizedStringResource("Continuing in Hanlin", bundle: .atURL(HanlinLocalization.bundle.bundleURL))))
    }
}
