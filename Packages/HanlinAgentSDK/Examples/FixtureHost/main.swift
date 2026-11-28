import Foundation
import HanlinAgentCore
import HanlinHostContracts
import HanlinPlatformContracts
import HanlinSDKTestFixtures

@main struct FixtureHostExample {
    static func main() async throws {
        let namespace = try HanlinConversationNamespace(app: "fixture", account: "test-account", workspace: "test-workspace", space: "test-space")
        let context = HanlinHostContext(namespace: namespace, sceneID: UUID(), generation: UUID(), objectReference: "synthetic-document")
        let session = HanlinHostSession(conversationID: UUID(), context: context)
        let host = SyntheticFixtureHost(context: context)
        let dispatcher = HanlinHostDispatcher(host: host)
        let result = try await dispatcher.dispatch(alias: "fixture_read", argumentsJSON: #"{"text":"fixture input"}"#,
            providerCallID: "opaque-provider-id", runID: UUID(), step: 0, session: session,
            catalog: host.catalog(for: context), limits: .init())
        print("Synthetic fixture only: \(result.effectState.rawValue). No production Otzaria API was called.")
    }
}
