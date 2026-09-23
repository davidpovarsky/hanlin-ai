import Foundation
import HanlinMiniAppCore
import HanlinPlatformContracts
import SwiftUI

@MainActor
public final class HanlinEmbeddedResultResolver {
    public static let shared = HanlinEmbeddedResultResolver()

    // Injected engine resolvers for unit/integration testing
    public var customSwiftResolver: (@MainActor (HanlinAppID, String, HanlinEmbeddedResultPayload?) -> (any HanlinEmbeddedResultSession)?)?
    public var customScriptUIResolver: (@MainActor (HanlinPackageID, String, HanlinEmbeddedResultPayload?) -> (any HanlinEmbeddedResultSession)?)?
    public var customNativeScriptResolver: (@MainActor (HanlinPackageID, String, HanlinEmbeddedResultPayload?) -> (any HanlinEmbeddedResultSession)?)?
    public var customExpoResolver: (@MainActor (HanlinPackageID, String, HanlinEmbeddedResultPayload?) -> (any HanlinEmbeddedResultSession)?)?

    public init() {}

    /// Resolves an arbitrary embedded result handler into an interactive session.
    /// Requires explicit canonical owner identity (via ownerID or payload.ownerID) or a qualified "owner:handler" format.
    /// Never falls back to guessing ownership from toolName.
    public func resolve(
        handler: String,
        ownerID: String? = nil,
        toolName: String? = nil,
        payload: HanlinEmbeddedResultPayload? = nil
    ) -> (any HanlinEmbeddedResultSession)? {
        let trimmedHandler = handler.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHandler.isEmpty else { return nil }

        // 1. Explicit canonical owner identity (from argument or payload.ownerID)
        // 2. Compatibility fallback: qualified "ownerID:handlerName"
        // NEVER fall back to toolName == appID
        let explicitOwner = (ownerID ?? payload?.ownerID)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedOwnerStr: String
        let subHandler: String

        if let explicitOwner, !explicitOwner.isEmpty {
            resolvedOwnerStr = explicitOwner
            if trimmedHandler.hasPrefix(explicitOwner + ":") {
                subHandler = String(trimmedHandler.dropFirst(explicitOwner.count + 1))
            } else {
                subHandler = trimmedHandler
            }
        } else {
            let parts = trimmedHandler.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                // Without explicit owner identity or qualified format, resolution fails cleanly
                return nil
            }
            resolvedOwnerStr = parts[0]
            subHandler = parts[1]
        }

        guard !resolvedOwnerStr.isEmpty, !subHandler.isEmpty else { return nil }

        // 1. Check for Swift compiled mini app
        if let appID = try? HanlinAppID(validating: resolvedOwnerStr) {
            if let custom = customSwiftResolver?(appID, subHandler, payload) {
                return custom
            }
            if let session = SwiftEmbeddedResultAdapter.resolve(appID: appID, handler: subHandler, payload: payload) {
                return session
            }
        }

        // 2. Check for installed scripting package (ScriptUI, NativeScript, Expo)
        if let packageID = try? HanlinPackageID(validating: resolvedOwnerStr) {
            // Injected test resolvers first
            if let custom = customScriptUIResolver?(packageID, subHandler, payload) {
                return custom
            }
            if let custom = customNativeScriptResolver?(packageID, subHandler, payload) {
                return custom
            }
            if let custom = customExpoResolver?(packageID, subHandler, payload) {
                return custom
            }

            // Real adapters
            if let session = ScriptUIEmbeddedResultAdapter.resolve(packageID: packageID, handler: subHandler, payload: payload) {
                return session
            }
            if let session = NativeScriptEmbeddedResultAdapter.resolve(packageID: packageID, handler: subHandler, payload: payload) {
                return session
            }
            if let session = ExpoEmbeddedResultAdapter.resolve(packageID: packageID, handler: subHandler, payload: payload) {
                return session
            }
        }

        return nil
    }
}
