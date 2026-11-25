import Foundation
import HanlinMiniAppCore
import HanlinNativeScriptCoreSupport
import HanlinNativeScriptRuntime
import HanlinPlatformContracts
import HanlinScriptContracts
import SwiftUI
import UIKit

private struct UIViewControllerHostView: UIViewControllerRepresentable {
    let controller: UIViewController

    func makeUIViewController(context: Context) -> UIViewController {
        controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

@MainActor
public enum NativeScriptEmbeddedResultAdapter {
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

        // Tool results retain their installed generation. A package update must
        // not silently reinterpret old output in a different renderer.
        if let metadata = payload?.metadata,
           metadata["installedPackageID"] != nil || metadata["generation"] != nil {
            guard metadata["installedPackageID"] == package.record.installedPackageID.rawValue,
                  metadata["generation"] == String(package.record.activeGeneration) else { return nil }
        }

        // Strict match: must correspond to a declared embedded-capable entrypoint
        guard let entrypoint = package.entrypoints.first(where: {
            $0.id == handler && $0.kind == .embeddedResult && $0.runtimeProfile == .hanlinNativeScript
        }) else {
            return nil
        }

        let sessionID = UUID().uuidString.lowercased()
        var ownedSession: HanlinNativeScriptSession?
        do {
            guard let artifactRoot = platform.activeArtifactURL(for: package) else {
                return nil
            }
            let entrypointURL = artifactRoot.appending(path: entrypoint.sourcePath, directoryHint: .notDirectory)
            let adapter = NativeScriptHostServicesAdapter(
                appID: package.appID,
                installedPackageID: package.record.installedPackageID,
                grantedCapabilities: Set(package.grantedCapabilities.map(\.rawValue)),
                sessionID: sessionID,
                assistantServiceFactory: platform.assistantServiceFactory
            )
            // Own only this renderer's environment keys. Explicit empty values
            // prevent a missing field from inheriting another session's payload.
            let env: [String: String] = [
                "HANLIN_APP_ID": package.appID.rawValue,
                "HANLIN_EMBEDDED": "1",
                "HANLIN_HANDLER": handler,
                "HANLIN_RESULT_REF": payload?.resultReference ?? "",
                "HANLIN_PAYLOAD": try payloadJSON(payload?.payload ?? .null)
            ]

            let session = try HanlinNativeScriptSession(
                applicationRoot: entrypointURL.deletingLastPathComponent(),
                environment: env,
                sessionID: sessionID
            )

            ownedSession = session
            HanlinNativeServicesBridge.register(adapter, forSessionID: sessionID)
            try session.start()

            let wrapper = UIViewControllerHostView(controller: session.containerController)

            return AnyEmbeddedResultSession(
                sessionID: UUID(uuidString: sessionID) ?? UUID(),
                engine: .nativeScript,
                appID: package.appID,
                rootView: AnyView(wrapper),
                onTearDown: {
                    HanlinNativeServicesBridge.unregisterProvider(forSessionID: sessionID)
                    session.shutdown()
                }
            )
        } catch {
            // Release JS handler blocks before a partially started VM closes.
            HanlinNativeServicesBridge.unregisterProvider(forSessionID: sessionID)
            ownedSession?.shutdown()
            return nil
        }
    }

    static func payloadJSON(_ value: HanlinValue) throws -> String {
        let bytes = try value.jsonValue(destination: .javaScriptBinary64).canonicalJSONData(limits: .unbounded)
        return String(decoding: bytes, as: UTF8.self)
    }
}
