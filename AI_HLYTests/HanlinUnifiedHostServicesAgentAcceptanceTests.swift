import Testing
@testable import AI_HLY
import HanlinPlatformContracts
import HanlinMiniAppCore

@Suite("Agent Host Services Acceptance")
struct HanlinUnifiedHostServicesAgentAcceptanceTests {

    @Test func agentContextCreation() {
        let context = HanlinHostCallContext.forAgent()
        #expect(context.effectiveCapabilities.contains("all"))
        #expect(context.origin == .assistantModel)
        #expect(context.storageScope is HanlinHostStorageScope)
        if case .agent = context.storageScope {
            // Expected
        } else {
            Issue.record("Agent context should have .agent storage scope")
        }
    }

    @Test func agentAdapterMakesContextWithAllCapabilities() {
        let context = AgentHostServicesAdapter.makeContext()
        #expect(context.effectiveCapabilities.contains("all"))
        #expect(context.origin == .assistantModel)
        #expect(context.appID == nil)
        #expect(context.canPresentUI == false)
        #expect(context.runtimeWorkspaceIdentifier == "agent-workspace")
    }

    @Test func agentContextSessionIDsAreUnique() {
        let c1 = AgentHostServicesAdapter.makeContext()
        let c2 = AgentHostServicesAdapter.makeContext()
        #expect(c1.appSessionID != c2.appSessionID)
        #expect(c1.runtimeSessionID != c2.runtimeSessionID)
    }

    @Test func runtimeBrokerRejectsDisabledRuntime() async throws {
        let store = RuntimeAvailabilityStore.shared
        let kind = RuntimeKind.javaScriptCore
        let original = store.isAvailable(kind)
        defer { store.setAvailable(original, for: kind) }

        store.setAvailable(false, for: kind)

        let context = AgentHostServicesAdapter.makeContext()
        do {
            _ = try await HanlinRuntimeBroker.shared.execute(
                kind: kind,
                source: "1+1",
                context: context
            )
            Issue.record("Expected runtimeDisabledByUser error")
        } catch let error as HanlinHostServiceError {
            if case .runtimeDisabledByUser(let disabledKind) = error {
                #expect(disabledKind == kind)
            } else {
                Issue.record("Unexpected error: \(error)")
            }
        }
    }
}
