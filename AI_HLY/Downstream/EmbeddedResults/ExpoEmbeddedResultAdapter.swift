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
        var ownedSession: HanlinExpoSession?
        var ownedActionChannel: HanlinMiniAppActionChannel?
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
            ownedActionChannel = adapter.actionChannel
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
                context["payload"] = try payloadProperty(value)
            }

            let session = try HanlinExpoSession(
                applicationRoot: entrypointURL.deletingLastPathComponent(),
                sessionID: sessionID,
                packageID: package.record.packageID.rawValue,
                installedPackageID: package.record.installedPackageID.rawValue,
                packageGeneration: package.record.activeGeneration,
                isNativeAPIGranted: true
            )

            ownedSession = session
            HanlinExpoHostServicesBridge.register(provider: adapter, forSessionID: sessionID)
            try session.start(initialProperties: ["hanlin": context])

            let wrapper = ExpoHostViewControllerView(controller: session.containerController)

            return AnyEmbeddedResultSession(
                sessionID: UUID(uuidString: sessionID) ?? UUID(),
                engine: .expo,
                appID: package.appID,
                rootView: AnyView(wrapper),
                onTearDown: {
                    HanlinExpoHostServicesBridge.unregister(sessionID: sessionID)
                    Task { await adapter.actionChannel.close() }
                    session.shutdown()
                }
            )
        } catch {
            HanlinExpoHostServicesBridge.unregister(sessionID: sessionID)
            if let ownedActionChannel { Task { await ownedActionChannel.close() } }
            ownedSession?.shutdown()
            return nil
        }
    }

    /// React props carry ordinary JavaScript JSON. The rich tagged Codable
    /// representation stays inside canonical native storage and is not a UI API.
    static func payloadProperty(_ value: HanlinValue) throws -> Any {
        let original = try value.jsonValue(destination: .javaScriptBinary64)
        let bytes = try original.canonicalJSONData(limits: .unbounded)
        let property = try JSONSerialization.jsonObject(with: bytes, options: [.fragmentsAllowed])
        let projectedBytes = try JSONSerialization.data(withJSONObject: property, options: [.fragmentsAllowed])
        let projected = try HanlinJSONValue.decodeCanonicalJSON(projectedBytes, limits: .unbounded)
        guard try javaScriptNumbers(projected).canonicalJSONData(limits: .unbounded) ==
            javaScriptNumbers(original).canonicalJSONData(limits: .unbounded) else {
            throw HanlinContractError.invalidJSON(
                reason: "Embedded result cannot be represented exactly in React Native properties.", byteOffset: 0)
        }
        return property
    }

    // Foundation may serialize 42.0 as 42. Both become the same exact JS Number;
    // normalize only that distinction after the original integer safety check.
    private static func javaScriptNumbers(_ value: HanlinJSONValue) -> HanlinJSONValue {
        switch value {
        case let .integer(integer): return .number(Double(integer))
        case let .array(items): return .array(items.map(javaScriptNumbers))
        case let .object(members): return .object(members.mapValues(javaScriptNumbers))
        default: return value
        }
    }
}
