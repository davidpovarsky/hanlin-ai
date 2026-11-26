import Foundation
import SwiftUI
import HanlinLocalization

/// Component hosts use the same process-owned runtime and public MCP facade.
/// The owner must be the app's retained shared owner, reused across its windows.
@MainActor
public final class HanlinAssistantServices {
    public let mcp: HanlinApplicationMCP
    public var skills: HanlinSkillCatalog { .shared }
    private let owner: AnyObject

    public init(runtimeConfiguration: HanlinApplicationRuntimeConfiguration,
                owner: AnyObject,
                validateConversation: @escaping @MainActor (UUID) throws -> Void) throws {
        try HanlinApplicationProcessRuntime.shared.install(runtimeConfiguration, modelContainer: owner)
        self.owner = owner
        self.mcp = HanlinApplicationMCP(validateConversation: validateConversation)
    }

    public func prepare() async { await RuntimeLifecycleBridge.prepareApplication() }

    public func handleScenePhase(_ phase: ScenePhase) async {
        await RuntimeLifecycleBridge.handleScenePhase(phase)
    }
}

/// Original management screens retain their original stores, installer,
/// permissions, cancellation and runtime receipts. Hosts own presentation.
@MainActor
public struct HanlinAssistantSettingsView: View {
    public init() {}

    public var body: some View {
        List {
            NavigationLink {
                MCPServersSettingsView()
            } label: {
                Label(MCPL10n.string("MCP Servers"), systemImage: "server.rack")
            }
            NavigationLink {
                SkillCenterView()
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

    public init(@ViewBuilder actions: () -> Actions) {
        self.actions = actions()
    }

    public var body: some View {
        RuntimeCenterView { actions }
    }
}
