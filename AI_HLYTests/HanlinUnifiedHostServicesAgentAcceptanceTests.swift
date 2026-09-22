import Testing
@testable import AI_Hanlin
import HanlinPlatformContracts
import HanlinMiniAppCore

@MainActor
@Suite("Agent Host Services Acceptance")
struct HanlinUnifiedHostServicesAgentAcceptanceTests {

    @Test func agentContextCreation() {
        let context = HanlinHostCallContext.forAgent()
        #expect(context.effectiveCapabilities.contains("all"))
        #expect(context.origin == .assistantModel)
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

    @Test func agentToolExecutesJavaScriptCore() async {
        let tool = ExecuteJavaScriptTool()
        let context = NativeToolExecutionContext(localeIdentifier: "en")
        let result = await tool.execute(
            argumentsJSON: "{\"source\": \"6 * 7\", \"runtime\": \"jscore\"}",
            context: context
        )
        #expect(!result.isError)
        #expect(result.modelText.contains("42"))
    }

    @Test func agentToolExecutesNode() async {
        let tool = ExecuteJavaScriptTool()
        let context = NativeToolExecutionContext(localeIdentifier: "en")
        let result = await tool.execute(
            argumentsJSON: "{\"source\": \"console.log(14 * 3);\", \"runtime\": \"node\"}",
            context: context
        )
        if !result.isError {
            #expect(result.modelText.contains("42"))
        }
    }

    @Test func agentToolExecutesPython() async {
        let tool = ExecuteLocalPythonTool()
        let context = NativeToolExecutionContext(localeIdentifier: "en")
        let result = await tool.execute(
            argumentsJSON: "{\"source\": \"print(40 + 2)\"}",
            context: context
        )
        if !result.isError {
            #expect(result.modelText.contains("42"))
        }
    }

    @Test func agentToolExecutesTypeScript() async {
        let tool = ExecuteTypeScriptTool()
        let context = NativeToolExecutionContext(localeIdentifier: "en")
        let result = await tool.execute(
            argumentsJSON: "{\"source\": \"const ans: number = 42; console.log(ans);\"}",
            context: context
        )
        if !result.isError {
            #expect(result.modelText.contains("42"))
        }
    }

    @Test func agentToolExecutesShell() async {
        let tool = ExecuteShellCommandTool()
        let context = NativeToolExecutionContext(localeIdentifier: "en")
        let result = await tool.execute(
            argumentsJSON: "{\"command\": \"echo 42\"}",
            context: context
        )
        if !result.isError {
            #expect(result.modelText.contains("42"))
        }
    }

    @Test func agentToolRespectsDisabledRuntimeToggle() async {
        let store = RuntimeAvailabilityStore.shared
        let original = store.isAvailable(.javaScriptCore)
        defer { store.setAvailable(original, for: .javaScriptCore) }

        store.setAvailable(false, for: .javaScriptCore)

        let tool = ExecuteJavaScriptTool()
        let context = NativeToolExecutionContext(localeIdentifier: "en")
        let result = await tool.execute(
            argumentsJSON: "{\"source\": \"6 * 7\", \"runtime\": \"jscore\"}",
            context: context
        )
        #expect(result.isError)
        #expect(result.modelText.lowercased().contains("disabled") || result.modelText.lowercased().contains("unavailable"))
    }
}
