import Foundation
import HanlinPlatformContracts
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

        guard let entrypoint = package.manifest.entrypoints.first(where: {
            $0.id.rawValue == handler || $0.runtimeProfile == .nativeScript
        }) ?? package.manifest.entrypoints.first(where: { $0.runtimeProfile == .nativeScript }) else {
            return nil
        }

        do {
            let store = platform.store
            guard let artifactRoot = try? store.activeArtifactURL(for: package.record.installedPackageID) else {
                return nil
            }
            let entrypointURL = artifactRoot.appending(path: entrypoint.sourcePath, directoryHint: .notDirectory)
            let sessionID = UUID().uuidString.lowercased()

            let adapter = NativeScriptHostServicesAdapter(
                installedPackageID: package.record.installedPackageID,
                appID: package.appID,
                grantedCapabilities: Set(package.grantedCapabilities.map(\.rawValue)),
                sessionID: try HanlinAppSessionID(validating: "sess-" + String(sessionID.prefix(8)))
            )
            HanlinNativeServicesBridge.register(adapter, forSessionID: sessionID)

            var env = ProcessInfo.processInfo.environment
            env["HANLIN_EMBEDDED"] = "1"
            env["HANLIN_HANDLER"] = handler
            if let ref = payload?.resultReference {
                env["HANLIN_RESULT_REF"] = ref
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
