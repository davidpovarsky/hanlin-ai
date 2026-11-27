import Foundation
import SwiftUI
import HanlinLocalization
import HanlinHostContracts

/// Component hosts use the same process-owned runtime and public MCP facade.
/// The owner must be the app's retained shared owner, reused across its windows.
@MainActor
public final class HanlinAssistantServices {
    public let mcp: HanlinApplicationMCP
    public var skills: HanlinSkillCatalog { .shared }
    private let owner: AnyObject
    fileprivate let availableTools: @MainActor () -> [HanlinSkillToolReference]

    public init(runtimeConfiguration: HanlinApplicationRuntimeConfiguration,
                owner: AnyObject,
                availableTools: @escaping @MainActor () -> [HanlinSkillToolReference],
                validateConversation: @escaping @MainActor (UUID) throws -> Void) throws {
        try HanlinApplicationProcessRuntime.shared.install(runtimeConfiguration, modelContainer: owner,
            systemIntegrations: HanlinApplicationProcessRuntime.shared.systemIntegrations)
        self.owner = owner
        self.availableTools = availableTools
        self.mcp = HanlinApplicationMCP(validateConversation: validateConversation)
    }

    /// Reuses the process owner's exact original runtime configuration. Each
    /// facade retains its own live conversation validation and presentation
    /// catalog; windows do not replace one another's action source.
    public static func sharedRuntime(runtimeConfiguration: HanlinApplicationRuntimeConfiguration,
        availableTools: @escaping @MainActor () -> [HanlinSkillToolReference],
        validateConversation: @escaping @MainActor (UUID) throws -> Void) throws -> HanlinAssistantServices {
        let owner = try HanlinApplicationProcessRuntime.shared.assistantComponentOwner(runtimeConfiguration)
        return try HanlinAssistantServices(runtimeConfiguration: runtimeConfiguration, owner: owner,
            availableTools: availableTools, validateConversation: validateConversation)
    }

    public func prepare() async { await RuntimeLifecycleBridge.prepareApplication() }

    public func handleScenePhase(_ phase: ScenePhase) async {
        await RuntimeLifecycleBridge.handleScenePhase(phase)
    }

    public func makeConversationHost(identity: HanlinHostSession,
        validateCurrent: @escaping @MainActor @Sendable () throws -> Void,
        consent: HanlinAppToolConsent) -> HanlinAssistantConversationHost {
        HanlinAssistantConversationHost(identity: identity,
            validateCurrent: validateCurrent, consent: consent)
    }
}

@MainActor
public struct HanlinMCPSettingsView: View {
    public init() {}
    public var body: some View { MCPServersSettingsView() }
}

@MainActor
public struct HanlinSkillCenterView: View {
    private let service: HanlinAssistantServices
    public init(service: HanlinAssistantServices) { self.service = service }
    public var body: some View {
        SkillCenterView().environment(\.hanlinSkillTools, { [service] in service.availableTools() })
    }
}

/// Original management screens retain their original stores, installer,
/// permissions, cancellation and runtime receipts. Hosts own presentation.
@MainActor
public struct HanlinAssistantSettingsView: View {
    private let service: HanlinAssistantServices
    public init(service: HanlinAssistantServices) { self.service = service }

    public var body: some View {
        List {
            NavigationLink {
                MCPServersSettingsView()
            } label: {
                Label(MCPL10n.string("MCP Servers"), systemImage: "server.rack")
            }
            NavigationLink {
                HanlinSkillCenterView(service: service)
            } label: {
                Label(SkillL10n.string("Skills"), systemImage: "sparkles")
            }
        }
        .navigationTitle(Text("Assistant", bundle: HanlinLocalization.bundle))
    }
}


/// The host supplies its actual action controls; a component never substitutes
/// the full application's unrelated permissions or an empty tool catalogue.
@MainActor
public struct HanlinRuntimeSettingsView<Actions: View>: View {
    private let actions: Actions
    private let service: HanlinAssistantServices

    public init(service: HanlinAssistantServices, @ViewBuilder actions: () -> Actions) {
        self.service = service
        self.actions = actions()
    }

    public var body: some View {
        RuntimeCenterView { actions }
            .environment(\.hanlinSkillTools, { [service] in service.availableTools() })
    }
}
