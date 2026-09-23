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

        // Strict declared handler match
        guard let entrypoint = package.entrypoints.first(where: {
            $0.id == handler && $0.runtimeProfile == .scriptingJSC
        }) else {
            return nil
        }

        guard let artifactRoot = platform.activeArtifactURL(for: package) else {
            return nil
        }

        let compiledURL = artifactRoot.appending(path: entrypoint.sourcePath, directoryHint: .notDirectory)
        guard FileManager.default.fileExists(atPath: compiledURL.path(percentEncoded: false)),
              let program = try? String(contentsOf: compiledURL, encoding: .utf8) else {
            return nil
        }

        do {
            let storageCapability = try HanlinCapabilityID(validating: "storage")
            let filesCapability = try HanlinCapabilityID(validating: "files")

            let payloadJSON: String = {
                if let payload = payload?.payload {
                    switch payload {
                    case .string(let s): return s
                    case .number(let n): return "\(n)"
                    case .boolean(let b): return "\(b)"
                    case .object(let dict):
                        let data = (try? JSONSerialization.data(withJSONObject: dict)) ?? Data()
                        return String(decoding: data, as: UTF8.self)
                    case .array(let arr):
                        let data = (try? JSONSerialization.data(withJSONObject: arr)) ?? Data()
                        return String(decoding: data, as: UTF8.self)
                    case .null: return "{}"
                    }
                }
                return "{}"
            }()

            // Real ScriptUI application session with independent lifecycle (never overwrites activeApplicationModel)
            let session = try HanlinScriptingApplicationSession(
                installedPackageID: package.record.installedPackageID,
                program: program,
                filename: entrypoint.sourcePath,
                entrypointContext: .embeddedResult(
                    handler: handler,
                    payloadJSON: payloadJSON,
                    resultReference: payload?.resultReference,
                    ownerID: packageID.rawValue
                ),
                storageAllowed: package.grantedCapabilities.contains(storageCapability),
                filesAllowed: package.grantedCapabilities.contains(filesCapability),
                packageSourceDirectory: artifactRoot.appending(path: "source", directoryHint: .isDirectory)
            )

            let view = HanlinScriptUIView(model: session.model)

            return AnyEmbeddedResultSession(
                engine: .scriptingJSC,
                appID: package.appID,
                rootView: AnyView(view),
                onTearDown: {
                    session.dispose()
                }
            )
        } catch {
            return nil
        }
    }
}
