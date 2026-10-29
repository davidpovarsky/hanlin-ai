import SwiftUI

public struct HanlinScriptWidgetDynamicView: View {
    public let descriptor: ScriptWidgetDescriptor
    public let identity: HanlinScriptExtensionIdentity?
    public let environment: [String: Any]

    public init(
        descriptor: ScriptWidgetDescriptor,
        identity: HanlinScriptExtensionIdentity? = nil,
        environment: [String: Any] = [:]
    ) {
        self.descriptor = descriptor
        self.identity = identity
        self.environment = environment
    }

    public var body: some View {
        let envDict = descriptor.environment?.mapValues { $0.toAny() } ?? environment
        let result = HanlinScriptWidgetRuntime.shared.execute(
            script: descriptor.script,
            environment: envDict
        )

        switch result {
        case let .success(element):
            HanlinScriptWidgetElementView(element: element)
        case let .failure(error):
            VStack(alignment: .leading, spacing: 4) {
                Label("ScriptWidget Render Error", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.red)
                Text(error.localizedDescription)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(8)
        }
    }
}
