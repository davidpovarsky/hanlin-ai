import AppIntents
import HanlinPlatformContracts
import HanlinScriptExtensions

struct HanlinScriptActionEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Script Action")
    static let defaultQuery = HanlinScriptActionEntityQuery()

    let id: String
    let displayName: String
    let subtitle: String?
    let identity: HanlinScriptExtensionIdentity

    var displayRepresentation: DisplayRepresentation {
        if let subtitle {
            DisplayRepresentation(title: "\(displayName)", subtitle: "\(subtitle)")
        } else {
            DisplayRepresentation(title: "\(displayName)")
        }
    }
}

struct HanlinScriptActionEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [HanlinScriptActionEntity] {
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

    func suggestedEntities() async throws -> [HanlinScriptActionEntity] {
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

struct HanlinRunScriptActionIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Script Action"
    static let description = IntentDescription("Runs an action from an installed Hanlin Script package.")
    static let openAppWhenRun = true

    @Parameter(title: "Action")
    var action: HanlinScriptActionEntity

    @Parameter(title: "Input", default: "")
    var input: String

    static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$action) with \(\.$input)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let rawActionID = action.id.components(separatedBy: "::").last ?? action.id
        let invocation = HanlinScriptIntentInvocation(
            identity: action.identity,
            entityID: rawActionID,
            parameters: .string(input),
            continueInForeground: true
        )
        try HanlinScriptExtensionStore().enqueue(.init(invocation: invocation))
        return .result(dialog: "Continuing in Hanlin")
    }
}
