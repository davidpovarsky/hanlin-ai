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

        // Strict match: must correspond to a declared embedded-capable entrypoint
        guard let entrypoint = package.entrypoints.first(where: {
            $0.id == handler && $0.runtimeProfile == .hanlinNativeScript
        }) else {
            return nil
        }

        do {
            guard let artifactRoot = platform.activeArtifactURL(for: package) else {
                return nil
            }
            let entrypointURL = artifactRoot.appending(path: entrypoint.sourcePath, directoryHint: .notDirectory)
            let sessionID = UUID().uuidString.lowercased()

            let adapter = NativeScriptHostServicesAdapter(
                appID: package.appID,
                installedPackageID: package.record.installedPackageID,
                grantedCapabilities: Set(package.grantedCapabilities.map(\.rawValue)),
                sessionID: sessionID
            )
            HanlinNativeServicesBridge.register(adapter, forSessionID: sessionID)

            var env = ProcessInfo.processInfo.environment
            env["HANLIN_EMBEDDED"] = "1"
            env["HANLIN_HANDLER"] = handler
            if let ref = payload?.resultReference {
                env["HANLIN_RESULT_REF"] = ref
            }
            if let json = payload?.payload,
               let data = try? JSONEncoder().encode(json),
               let str = String(data: data, encoding: .utf8) {
                env["HANLIN_PAYLOAD"] = str
            }

            let session = try HanlinNativeScriptSession(
                applicationRoot: entrypointURL.deletingLastPathComponent(),
                environment: env,
                sessionID: sessionID
            )

            try session.start()

            let wrapper = UIViewControllerHostView(controller: session.containerController)

            return AnyEmbeddedResultSession(
                sessionID: UUID(uuidString: sessionID) ?? UUID(),
                engine: .nativeScript,
                appID: package.appID,
                rootView: AnyView(wrapper),
                onTearDown: {
                    session.shutdown()
                    HanlinNativeServicesBridge.unregisterProvider(forSessionID: sessionID)
                }
            )
        } catch {
            return nil
        }
    }
}
