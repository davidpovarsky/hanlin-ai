#if canImport(SwiftUI)
import SwiftUI
import Testing
import HanlinChatUI
import HanlinPlatformContracts

@MainActor
@Suite("Composer custom panel host registration")
struct HanlinCapabilityCustomPanelProviderTests {
    @Test func registrationRoutesOnlyTheDeclaredReferenceAndForwardsTheDraftBinding() throws {
        let reference = HanlinCapabilityReference(kind: .miniApp, sourceID: "library", capabilityID: "search")
        let otherReference = HanlinCapabilityReference(kind: .miniApp, sourceID: "other", capabilityID: "search")
        var configuration: HanlinJSONValue = .object(["collection": .string("tanakh")])
        var forwardedBinding: Binding<HanlinJSONValue>?
        var renderedPanels = 0
        func render(_ binding: Binding<HanlinJSONValue>) -> Text {
            renderedPanels += 1
            forwardedBinding = binding
            return Text("Host catalog")
        }
        let provider = HanlinCapabilityCustomPanelProvider(
            supports: { candidate, panelID in candidate == reference && panelID == "library.catalog" }
        ) { _, _, configuration in
            render(configuration)
        }
        var environment = EnvironmentValues()
        #expect(environment.hanlinCapabilityCustomPanelProvider == nil)
        environment.hanlinCapabilityCustomPanelProvider = provider
        let registered = try #require(environment.hanlinCapabilityCustomPanelProvider)
        let binding = Binding(get: { configuration }, set: { configuration = $0 })

        #expect(registered.supports("library.catalog", for: reference))
        #expect(renderedPanels == 0, "Registration and support checks must not construct panel content")
        #expect(registered.panel(for: "library.catalog", reference: otherReference, configuration: binding) == nil)
        #expect(registered.panel(for: "unknown", reference: reference, configuration: binding) == nil)
        #expect(renderedPanels == 0, "A different provider cannot borrow a custom panel ID")

        #expect(registered.panel(for: "library.catalog", reference: reference, configuration: binding) != nil)
        #expect(renderedPanels == 1)
        let editableConfiguration = try #require(forwardedBinding)
        editableConfiguration.wrappedValue = .object(["collection": .string("talmud")])
        #expect(configuration == .object(["collection": .string("talmud")]))
    }
}
#endif
