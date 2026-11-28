import Foundation
import HanlinHostContracts
import HanlinPlatformContracts
import Testing

// This consumer deliberately has the same upcoming concurrency feature as the app,
// while HostContracts retains its existing SDK convention. No executor is simulated.
@MainActor private final class ApproachableHostWitness: HanlinHostIntegration {
    nonisolated let apiVersion = HanlinAPIVersion(major: 1, minor: 1)
    func context(for session: HanlinHostSession) async throws -> HanlinHostContext { session.context }
    func catalog(for context: HanlinHostContext) async throws -> HanlinHostCatalog {
        .init(apiVersion: apiVersion, revision: .init(0), context: context, tools: [])
    }
    func execute(_ invocation: HanlinHostInvocation,
                 progress: @escaping HanlinHostProgressHandler) async throws -> HanlinHostExecutionResult {
        throw HanlinHostError.unsupportedProviderCapability
    }
    func cancel(_ invocation: HanlinToolInvocationID) async {}
    func open(_ destination: HanlinHostDestination) async throws -> HanlinHostNavigationResult {
        throw HanlinHostError.unsupportedProviderCapability
    }
}

@Suite struct HostCallbackConventionTests {
    @Test @MainActor func importedHostWitnessSupportsTheOriginalAppsConcurrencyConvention() async throws {
        let namespace = try HanlinConversationNamespace(app: "hanlin", account: "test", workspace: "test", space: "test")
        let context = HanlinHostContext(namespace: namespace, sceneID: UUID(), generation: UUID())
        let identity = HanlinHostSession(conversationID: UUID(), context: context)
        let host: any HanlinHostIntegration = ApproachableHostWitness()
        #expect(try await host.context(for: identity) == context)
    }
}
