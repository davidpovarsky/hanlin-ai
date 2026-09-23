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
    public func resolve(
        handler: String,
        toolName: String? = nil,
        payload: HanlinEmbeddedResultPayload? = nil
    ) -> (any HanlinEmbeddedResultSession)? {
        let trimmedHandler = handler.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHandler.isEmpty else { return nil }

        // Parse handler format: either "appID:handlerName" or "handlerName"
        let parts = trimmedHandler.split(separator: ":", maxSplits: 1).map(String.init)
        let resolvedAppIDStr = parts.count == 2 ? parts[0] : (toolName ?? "")
        let subHandler = parts.count == 2 ? parts[1] : parts[0]

        // 1. Check for Swift compiled mini app
        if let appID = try? HanlinAppID(validating: resolvedAppIDStr) {
            if let custom = customSwiftResolver?(appID, subHandler, payload) {
                return custom
            }
            if let session = SwiftEmbeddedResultAdapter.resolve(appID: appID, handler: subHandler, payload: payload) {
                return session
            }
        }

        // 2. Check for installed scripting package (ScriptUI, NativeScript, Expo)
        if let packageID = try? HanlinPackageID(validating: resolvedAppIDStr) {
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
