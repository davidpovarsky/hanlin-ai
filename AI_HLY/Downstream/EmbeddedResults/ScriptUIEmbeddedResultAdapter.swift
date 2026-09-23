import Foundation
import HanlinMiniAppCore
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
        let titleNode = HanlinScriptUINode(
            kind: .text,
            properties: [
                "text": .string(payload?.title ?? handler),
                "font": .string("headline")
            ]
        )
        var children = [titleNode]
        if let jsonPayload = payload?.payload {
            let bodyText: String
            if let data = try? JSONEncoder().encode(jsonPayload),
               let str = String(data: data, encoding: .utf8) {
                bodyText = str
            } else {
                bodyText = String(describing: jsonPayload)
            }
            children.append(
                HanlinScriptUINode(
                    kind: .text,
                    properties: [
                        "text": .string(bodyText),
                        "font": .string("body")
                    ]
                )
            )
        }
        let rootNode = HanlinScriptUINode(
            kind: .vStack,
            properties: ["spacing": .number(8)],
            children: children
        )

        let model = HanlinScriptUIModel(root: rootNode) { _, _ in }
        let view = HanlinScriptUIView(model: model)

        return AnyEmbeddedResultSession(
            engine: .scriptingJSC,
            appID: package.appID,
            rootView: AnyView(view)
        )
    }
}
