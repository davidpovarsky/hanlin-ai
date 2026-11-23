import SwiftData
import SwiftUI

/// Installs the original store and application lifecycle for an embedded
/// component. Repeated views share the context's one bootstrap operation.
@MainActor
private struct HanlinApplicationHostModifier: ViewModifier {
    let context: HanlinApplicationContext
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .modelContainer(context.modelContainer)
            .task {
                await context.prepareApplication()
                await context.handleScenePhase(scenePhase)
            }
            .onChange(of: scenePhase) { _, phase in
                Task { await context.handleScenePhase(phase) }
            }
    }
}

public extension View {
    /// Attach the original Hanlin model container and runtime lifecycle to a
    /// custom arrangement of SDK components. The public component views apply
    /// this automatically.
    @MainActor
    func hanlinApplicationContext(_ context: HanlinApplicationContext) -> some View {
        modifier(HanlinApplicationHostModifier(context: context))
    }
}

/// The unchanged original tab workspace, including chat and personal library.
@MainActor
public struct HanlinWorkspaceView: View {
    private let context: HanlinApplicationContext
    @Binding private var deepLinkTarget: String?

    public init(context: HanlinApplicationContext, deepLinkTarget: Binding<String?> = .constant(nil)) {
        self.context = context
        self._deepLinkTarget = deepLinkTarget
    }

    public var body: some View {
        MainTabView(deepLinkTarget: $deepLinkTarget).hanlinApplicationContext(context)
    }
}

/// The original settings flow and its original editors.
@MainActor
public struct HanlinSettingsView: View {
    private let context: HanlinApplicationContext
    private let onDone: (() -> Void)?

    public init(context: HanlinApplicationContext, onDone: (() -> Void)? = nil) {
        self.context = context
        self.onDone = onDone
    }

    public var body: some View {
        SettingsView(onDone: onDone).hanlinApplicationContext(context)
    }
}

/// The original library with navigation supplied by the embedding host.
@MainActor
public struct HanlinLibraryView: View {
    private let context: HanlinApplicationContext
    private let onOpenConversation: (HanlinConversationDestination) -> Void
    private let onOpenProfile: () -> Void
    private let onOpenMiniApps: () -> Void
    private let onOpenVision: () -> Void

    public init(context: HanlinApplicationContext,
                onOpenConversation: @escaping (HanlinConversationDestination) -> Void,
                onOpenProfile: @escaping () -> Void,
                onOpenMiniApps: @escaping () -> Void,
                onOpenVision: @escaping () -> Void) {
        self.context = context
        self.onOpenConversation = onOpenConversation
        self.onOpenProfile = onOpenProfile
        self.onOpenMiniApps = onOpenMiniApps
        self.onOpenVision = onOpenVision
    }

    public var body: some View {
        HanlinPersonalLibraryView(onOpenProfile: onOpenProfile,
            onOpenMiniApps: onOpenMiniApps, onOpenVision: onOpenVision,
            onOpenConversation: { onOpenConversation(.init($0)) })
            .hanlinApplicationContext(context)
    }
}

/// Independently embeddable original management surfaces. Navigation containers
/// remain under host control; surfaces that already own one retain it.
public enum HanlinApplicationPanel: String, CaseIterable, Sendable {
    case models, providers, skills, mcp, runtimes, miniApps
    case prompts, memory, translations, knowledge, diagnostics, toolPermissions
    case guide, costs, support
}

@MainActor
public struct HanlinApplicationPanelView: View {
    private let context: HanlinApplicationContext
    private let panel: HanlinApplicationPanel

    public init(context: HanlinApplicationContext, panel: HanlinApplicationPanel) {
        self.context = context
        self.panel = panel
    }

    public var body: some View {
        panelContent.hanlinApplicationContext(context)
    }

    @ViewBuilder private var panelContent: some View {
        switch panel {
        case .models: ModelsView()
        case .providers: APIKeysView()
        case .skills: SkillCenterView()
        case .mcp: MCPServersSettingsView()
        case .runtimes: RuntimeCenterView()
        case .miniApps: NativeAppsHubView()
        case .prompts: PromptRepoView()
        case .memory: MemoryArchiveView()
        case .translations: TranslationDicView()
        case .knowledge: KnowledgeListView()
        case .diagnostics: AgentDiagnosticsView()
        case .toolPermissions: HanlinToolPermissionsView()
        case .guide: HanlinHelpView(topic: .guide, showsDone: false)
        case .costs: HanlinHelpView(topic: .costs, showsDone: false)
        case .support: HanlinSupportView()
        }
    }
}

/// The original camera and visual analysis workspace. The host controls where
/// it is presented and handles the original workspace's return action.
@MainActor
public struct HanlinVisionView: View {
    private let context: HanlinApplicationContext
    private let onClose: () -> Void

    public init(context: HanlinApplicationContext, onClose: @escaping () -> Void) {
        self.context = context
        self.onClose = onClose
    }

    public var body: some View {
        VisionView(selectedTab: Binding(get: { 1 }, set: { destination in
            if destination != 1 { onClose() }
        })).hanlinApplicationContext(context)
    }
}
