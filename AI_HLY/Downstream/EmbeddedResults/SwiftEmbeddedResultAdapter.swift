import Foundation
import HanlinMiniAppCore
import HanlinPlatformContracts
import SwiftUI

@MainActor
public enum SwiftEmbeddedResultAdapter {
    public static func resolve(
        appID: HanlinAppID,
        handler: String,
        payload: HanlinEmbeddedResultPayload?
    ) -> (any HanlinEmbeddedResultSession)? {
        BuiltinCanonicalRegistrations.ensureRegistered()
        guard let provider = HanlinCompiledMiniAppRegistry.shared.provider(for: appID) else {
            return nil
        }

        let host = HanlinMiniAppHost.shared
        let context = HanlinMiniAppHostContext(
            appID: appID,
            storage: HanlinMiniAppStorageContext(appID: appID, store: host.dataStore),
            requestBroker: host.requestBroker,
            network: { url in
                var request = URLRequest(url: url)
                request.timeoutInterval = 15
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                return "HTTPS \(http.statusCode), \(data.count) bytes"
            }
        )

        let safePayload = payload ?? HanlinEmbeddedResultPayload()

        let rootView: AnyView
        if let embeddedProvider = provider as? any HanlinCompiledEmbeddedResultProvider,
           let customView = embeddedProvider.makeEmbeddedView(handler: handler, payload: safePayload, context: context) {
            rootView = customView
        } else {
            rootView = provider.makeRootView(context: context)
        }

        return AnyEmbeddedResultSession(
            engine: .swift,
            appID: appID,
            rootView: rootView
        )
    }
}
