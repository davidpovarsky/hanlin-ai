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
        try records().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [HanlinScriptActionEntity] {
        try records()
    }

    private func records() throws -> [HanlinScriptActionEntity] {
        try HanlinScriptExtensionStore().load()?.intentEntities.map {
            .init(id: $0.id, displayName: $0.displayName, subtitle: $0.subtitle, identity: $0.identity)
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
        let invocation = HanlinScriptIntentInvocation(
            identity: action.identity,
            entityID: action.id,
            parameters: .string(input),
            continueInForeground: true
        )
        try HanlinScriptExtensionStore().enqueue(.init(invocation: invocation))
        return .result(dialog: "Continuing in Hanlin")
    }
}
