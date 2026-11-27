import Foundation
import SwiftUI

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

enum HanlinSkillToolSource {
    @MainActor static func productionTools() -> [HanlinSkillToolReference] {
#if HANLIN_ASSISTANT_CAPABILITIES_SDK
        preconditionFailure("Present the original Skill Center with its HanlinAssistantServices facade")
#else
        NativeToolCatalog.shared.ensureBuiltinsRegistered()
        return NativeToolCatalog.shared.allEntries().map {
            HanlinSkillToolReference(name: $0.name, title: $0.title)
        }
#endif
    }
}

private struct HanlinSkillToolsEnvironmentKey: EnvironmentKey {
    static let defaultValue: @MainActor @Sendable () -> [HanlinSkillToolReference] = {
        HanlinSkillToolSource.productionTools()
    }
}

extension EnvironmentValues {
    var hanlinSkillTools: @MainActor @Sendable () -> [HanlinSkillToolReference] {
        get { self[HanlinSkillToolsEnvironmentKey.self] }
        set { self[HanlinSkillToolsEnvironmentKey.self] = newValue }
    }
}
