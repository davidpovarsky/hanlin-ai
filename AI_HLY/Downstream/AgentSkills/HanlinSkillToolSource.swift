import Foundation

/// A presentation projection of a tool that the current host actually exposes.
/// Execution and authorization remain with the original host tool owner.
public struct HanlinSkillToolReference: Identifiable, Sendable {
    public let name: String
    public let title: String
    public var id: String { name }

    public init(name: String, title: String) {
        self.name = name
        self.title = title
    }
}

@MainActor
enum HanlinSkillToolSource {
    static var provider: @MainActor () -> [HanlinSkillToolReference] = productionTools

    private static func productionTools() -> [HanlinSkillToolReference] {
#if HANLIN_ASSISTANT_CAPABILITIES_SDK
        preconditionFailure("Install HanlinAssistantServices with the host's actual tool catalog before presenting skill settings")
#else
        NativeToolCatalog.shared.ensureBuiltinsRegistered()
        return NativeToolCatalog.shared.allEntries().map {
            HanlinSkillToolReference(name: $0.name, title: $0.title)
        }
#endif
    }
}
