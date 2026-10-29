import SwiftUI

public struct HanlinExpoWidgetsDynamicView: View {
    public let descriptor: ExpoWidgetDescriptor
    public let identity: HanlinScriptExtensionIdentity?
    public let environment: [String: Any]

    public init(
        descriptor: ExpoWidgetDescriptor,
        identity: HanlinScriptExtensionIdentity? = nil,
        environment: [String: Any] = [:]
    ) {
        self.descriptor = descriptor
        self.identity = identity
        self.environment = environment
    }

    public var body: some View {
        let actionContext = HanlinExpoActionContext(
            packageID: identity?.packageID.rawValue ?? "",
            entrypointID: identity?.entrypointID ?? "",
            environmentJSON: (try? String(data: JSONSerialization.data(withJSONObject: environment), encoding: .utf8)) ?? "{}"
        )

        let propsDict = descriptor.props?.mapValues { $0.toAny() }
        let result = HanlinExpoWidgetsRuntime.shared.render(
            layout: descriptor.layout,
            props: propsDict,
            environment: environment
        )

        switch result {
        case let .success(node):
            HanlinExpoWidgetsViewRenderer.renderNode(node, actionContext: actionContext)
        case let .failure(error):
            VStack(alignment: .leading, spacing: 4) {
                Label("Expo Widget Render Error", systemImage: "exclamationmark.triangle.fill")
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
