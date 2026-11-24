import Foundation
import HanlinExtensionContracts
import HanlinScriptExtensions

/// Host-owned storage and credentials feed the original extension session.
/// The original compact client and shared chat engine still perform generation.
public struct HanlinTranslationHostServices: Sendable {
    public let agentClient: HanlinCompactAgentClient
    public let loadSnapshot: @Sendable () throws -> HanlinScriptExtensionSnapshot?

    public init(agentClient: HanlinCompactAgentClient,
                loadSnapshot: @escaping @Sendable () throws -> HanlinScriptExtensionSnapshot?) {
        self.agentClient = agentClient
        self.loadSnapshot = loadSnapshot
    }

    /// Re-read the host's model selection and resolve credentials on every turn.
    public init(configuration: HanlinExtensionHostConfiguration,
                credentialResolver: (@Sendable (String) throws -> String)? = nil) {
        self.agentClient = HanlinCompactAgentClient(configurationLoader: {
            try HanlinCompactAgentConfigStore(
                appGroupIdentifier: configuration.requireAppGroupIdentifier()).load()
        }, credentialResolver: credentialResolver)
        self.loadSnapshot = {
            try HanlinScriptExtensionStore(hostConfiguration: configuration).load()
        }
    }
}
