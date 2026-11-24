import Foundation
import HanlinExpoRuntime
import HanlinMiniAppCore
import HanlinPlatformContracts
import HanlinScriptContracts
import SwiftUI
import UIKit

private struct ExpoHostViewControllerView: UIViewControllerRepresentable {
    let controller: UIViewController

    func makeUIViewController(context: Context) -> UIViewController {
        controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

@MainActor
public enum ExpoEmbeddedResultAdapter {
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
            $0.id == handler && $0.kind == .embeddedResult && $0.runtimeProfile == .hanlinExpo
        }) else {
            return nil
        }

        let sessionID = UUID().uuidString.lowercased()
        do {
            guard let artifactRoot = platform.activeArtifactURL(for: package) else {
                return nil
            }
            let entrypointURL = artifactRoot.appending(path: entrypoint.sourcePath, directoryHint: .notDirectory)

            let adapter = ExpoHostServicesAdapter(
                appID: package.appID,
                installedPackageID: package.record.installedPackageID,
                grantedCapabilities: Set(package.grantedCapabilities.map(\.rawValue)),
                sessionID: sessionID
            )
            HanlinExpoHostServicesBridge.register(provider: adapter, forSessionID: sessionID)

            var context: [String: Any] = [
                "kind": "embeddedResult", "handler": handler,
                "ownerID": package.record.packageID.rawValue,
                "installedPackageID": package.record.installedPackageID.rawValue,
                "generation": package.record.activeGeneration
            ]
            if let reference = payload?.resultReference {
                context["resultReference"] = reference
            }
            if let value = payload?.payload {
                context["payload"] = try JSONSerialization.jsonObject(
                    with: value.canonicalJSONData(), options: [.fragmentsAllowed])
            }

            let session = try HanlinExpoSession(
                applicationRoot: entrypointURL.deletingLastPathComponent(),
                sessionID: sessionID,
                packageID: package.record.packageID.rawValue,
                installedPackageID: package.record.installedPackageID.rawValue,
                packageGeneration: package.record.activeGeneration,
                isNativeAPIGranted: true
            )

            try session.start(initialProperties: ["hanlin": context])

            let wrapper = ExpoHostViewControllerView(controller: session.containerController)

            return AnyEmbeddedResultSession(
                sessionID: UUID(uuidString: sessionID) ?? UUID(),
                engine: .expo,
                appID: package.appID,
                rootView: AnyView(wrapper),
                onTearDown: {
                    session.shutdown()
                    HanlinExpoHostServicesBridge.unregister(sessionID: sessionID)
                }
            )
        } catch {
            HanlinExpoHostServicesBridge.unregister(sessionID: sessionID)
            return nil
        }
    }
}
