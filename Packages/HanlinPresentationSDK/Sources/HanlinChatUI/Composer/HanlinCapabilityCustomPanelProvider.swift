import SwiftUI
import HanlinPlatformContracts

/// Registers native configuration content supplied by the embedding host.
/// Match both the capability reference and manifest panel ID so another tool
/// cannot select a component merely by reusing its customViewID.
@MainActor
public struct HanlinCapabilityCustomPanelProvider {
    private let supportsPanel: @MainActor (HanlinCapabilityReference, String) -> Bool
    private let makePanel: @MainActor (HanlinCapabilityReference, String, Binding<HanlinJSONValue>) -> AnyView

    public init<Panel: View>(
        supports: @escaping @MainActor (HanlinCapabilityReference, String) -> Bool,
        @ViewBuilder content: @escaping @MainActor (HanlinCapabilityReference, String, Binding<HanlinJSONValue>) -> Panel
    ) {
        supportsPanel = supports
        makePanel = { reference, panelID, configuration in
            AnyView(content(reference, panelID, configuration))
        }
    }

    public func supports(_ panelID: String, for reference: HanlinCapabilityReference) -> Bool {
        supportsPanel(reference, panelID)
    }

    /// Unsupported routes never invoke the host's content closure. Rendering
    /// receives only the current draft configuration, not a tool executor.
    public func panel(
        for panelID: String,
        reference: HanlinCapabilityReference,
        configuration: Binding<HanlinJSONValue>
    ) -> AnyView? {
        guard supports(panelID, for: reference) else { return nil }
        return makePanel(reference, panelID, configuration)
    }
}

private struct HanlinCapabilityCustomPanelProviderKey: EnvironmentKey {
    static let defaultValue: HanlinCapabilityCustomPanelProvider? = nil
}

public extension EnvironmentValues {
    /// Inherited by the real composer configuration page and SDK standalone
    /// configuration views. Registration can be scoped to one chat subtree.
    var hanlinCapabilityCustomPanelProvider: HanlinCapabilityCustomPanelProvider? {
        get { self[HanlinCapabilityCustomPanelProviderKey.self] }
        set { self[HanlinCapabilityCustomPanelProviderKey.self] = newValue }
    }
}

public extension View {
    /// Install above the host's chat/composer root. The normal configuration
    /// initializer then resolves custom panels through this environment value.
    @MainActor
    func hanlinCapabilityCustomPanels<Panel: View>(
        supports: @escaping @MainActor (HanlinCapabilityReference, String) -> Bool,
        @ViewBuilder content: @escaping @MainActor (HanlinCapabilityReference, String, Binding<HanlinJSONValue>) -> Panel
    ) -> some View {
        environment(\.hanlinCapabilityCustomPanelProvider,
                    HanlinCapabilityCustomPanelProvider(supports: supports, content: content))
    }
}
