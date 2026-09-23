import Foundation
import HanlinPlatformContracts
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

        guard let entrypoint = package.manifest.entrypoints.first(where: {
            $0.id.rawValue == handler || $0.runtimeProfile == .hanlinExpo
        }) ?? package.manifest.entrypoints.first(where: { $0.runtimeProfile == .hanlinExpo }) else {
            return nil
        }

        do {
            let store = platform.store
            guard let artifactRoot = try? store.activeArtifactURL(for: package.record.installedPackageID) else {
                return nil
            }
            let entrypointURL = artifactRoot.appending(path: entrypoint.sourcePath, directoryHint: .notDirectory)
            let sessionID = UUID().uuidString.lowercased()

            let adapter = ExpoHostServicesAdapter(
                appID: package.appID,
                installedPackageID: package.record.installedPackageID,
                grantedCapabilities: Set(package.grantedCapabilities.map(\.rawValue)),
                sessionID: sessionID
            )
            HanlinExpoHostServicesBridge.register(provider: adapter, forSessionID: sessionID)

            let session = try HanlinExpoSession(
                applicationRoot: entrypointURL.deletingLastPathComponent(),
                sessionID: sessionID
            )

            try session.start()

            let wrapper = ExpoHostViewControllerView(controller: session.containerController)

            return AnyEmbeddedResultSession(
                sessionID: UUID(uuidString: sessionID) ?? UUID(),
                engine: .expo,
                appID: package.appID,
                rootView: AnyView(wrapper),
                onTearDown: {
                    HanlinExpoHostServicesBridge.unregisterProvider(forSessionID: sessionID)
                }
            )
        } catch {
            return nil
        }
    }
}
