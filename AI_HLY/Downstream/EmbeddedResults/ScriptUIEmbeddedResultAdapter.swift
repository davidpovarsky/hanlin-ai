import Foundation
import HanlinPlatformContracts
import HanlinScriptUI
import SwiftUI

@MainActor
public enum ScriptUIEmbeddedResultAdapter {
    public static func resolve(
        packageID: HanlinPackageID,
        handler: String,
        payload: HanlinEmbeddedResultPayload?
    ) -> (any HanlinEmbeddedResultSession)? {
        let platform = HanlinScriptingPlatform.shared
        guard let package = platform.installedPackages.first(where: {
            $0.record.packageID == packageID || $0.appID.rawValue == packageID.rawValue
        }), package.enabled else {
            return nil
        }

        // If payload contains structured HanlinValue with UI node representation, render it directly
        // via independent HanlinScriptUIModel without touching activeApplicationModel
        let rootNode: HanlinScriptUINode
        if let jsonPayload = payload?.payload {
            rootNode = .vstack(
                spacing: 8,
                alignment: .leading,
                children: [
                    .text(payload?.title ?? handler, font: .subheadline, weight: .semibold),
                    .text(jsonPayload.description, font: .body, foregroundColor: .primary)
                ]
            )
        } else {
            rootNode = .vstack(
                spacing: 8,
                alignment: .leading,
                children: [
                    .text(payload?.title ?? handler, font: .subheadline, weight: .semibold)
                ]
            )
        }

        let model = HanlinScriptUIModel(root: rootNode) { _, _ in }
        let view = HanlinScriptUIView(model: model)

        return AnyEmbeddedResultSession(
            engine: .scriptingJSC,
            appID: package.appID,
            rootView: AnyView(view)
        )
    }
}
