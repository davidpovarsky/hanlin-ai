import Foundation
import HanlinPlatformContracts

#if !HANLIN_ASSISTANT_CAPABILITIES_SDK
extension HanlinAISDKToolAdapter: HanlinOriginalToolSource {
    func descriptor(for alias: String) -> HanlinToolDescriptor? {
        preparedTools.authority.toolDescriptor(for: alias)
    }
    func isMCP(_ alias: String) -> Bool {
        if case .mcp? = preparedTools.authority.resolution(alias: alias)?.backend { return true }
        return false
    }
    func originalMCPInputSchema(for alias: String) -> Data? {
        preparedTools.authority.originalInputSchemasByAlias[alias]
    }
    func mcpServerID(for alias: String) -> UUID? {
        if case .mcp(let serverID, _)? = preparedTools.authority.resolution(alias: alias)?.backend { return serverID }
        return nil
    }
}
#endif
