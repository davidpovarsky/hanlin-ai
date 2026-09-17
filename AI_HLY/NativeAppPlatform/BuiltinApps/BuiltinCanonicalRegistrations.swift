import Foundation
import HanlinMiniAppCore
import HanlinParityMiniApp
import HanlinPlatformContracts
import HanlinSefariaMiniApp
import HanlinTextStudioMiniApp
import HanlinWikipediaMiniApp
import SwiftUI

// MARK: - Built-in Canonical Index

/// Central index of all built-in native Mini App canonical registrations.
@MainActor
enum BuiltinCanonicalRegistrations {
    private static var _isRegistered = false

    static func ensureRegistered() {
        guard !_isRegistered else { return }
        _isRegistered = true

        let registry = HanlinCompiledMiniAppRegistry.shared
        registry.register(SwiftParityMiniAppProvider())
        registry.register(SefariaMiniAppProvider())
        registry.register(WikipediaMiniAppProvider())
        registry.register(TextStudioMiniAppProvider())

        SefariaMiniAppProvider.customViewFactory = { context in
            AnyView(NativeAppSessionContainerView(request: NativeAppRouter().launchRequest(
                appID: "nativeapp.sefaria",
                presentationStyle: .fullScreen
            )))
        }
        WikipediaMiniAppProvider.customViewFactory = { context in
            AnyView(NativeAppSessionContainerView(request: NativeAppRouter().launchRequest(
                appID: "nativeapp.wikipedia",
                presentationStyle: .fullScreen
            )))
        }
        TextStudioMiniAppProvider.customViewFactory = { context in
            AnyView(NativeAppSessionContainerView(request: NativeAppRouter().launchRequest(
                appID: "nativeapp.textstudio",
                presentationStyle: .fullScreen
            )))
        }
    }

    static var all: [any HanlinStaticMiniAppRegistration] {
        ensureRegistered()
        return HanlinCompiledMiniAppRegistry.shared.allProviders()
            .map(\.registration)
    }

    static func registration(
        for appID: HanlinAppID
    ) -> (any HanlinStaticMiniAppRegistration)? {
        ensureRegistered()
        return HanlinCompiledMiniAppRegistry.shared.provider(for: appID)?.registration
    }
}

// MARK: - Built-in Canonical Discovery

/// Discovery service for built-in native Mini Apps conforming to the canonical protocol.
public struct BuiltinMiniAppDiscovery: HanlinMiniAppDiscovery, Sendable {
    public init() {}

    public func registrations() async throws -> [any HanlinMiniAppRegistration] {
        await BuiltinCanonicalRegistrations.all
    }

    public func registration(
        for appID: HanlinAppID
    ) async throws -> (any HanlinMiniAppRegistration)? {
        await BuiltinCanonicalRegistrations.registration(for: appID)
    }

    public func catalogSnapshot(
        revision: HanlinCatalogRevision = .init(1)
    ) async throws -> HanlinCatalogSnapshot {
        let all = await BuiltinCanonicalRegistrations.all
        let descriptors = try all.map {
            try $0.appDescriptor()
        }
        return HanlinCatalogSnapshot(
            revision: revision,
            generatedAt: .now,
            apps: descriptors
        )
    }
}
