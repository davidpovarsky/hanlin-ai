import HanlinMiniAppCore
import HanlinPlatformContracts
import SwiftUI

/// Leaf composition seam. Existing host/catalog/package UI supply these closures;
/// no runtime, grant store or installed-package registry is duplicated here.
@MainActor
struct MiniAppsServices {
    let catalog: () async throws -> [HanlinMiniAppCatalogItem]
    let launch: (HanlinMiniAppCatalogItem) async throws -> AnyView
    let packageManagement: () throws -> AnyView

    enum IntegrationError: LocalizedError {
        case unavailable
        var errorDescription: String? {
            String(localized: "MiniApps services are awaiting target integration.")
        }
    }

    static let unconfigured = Self(
        catalog: { throw IntegrationError.unavailable },
        launch: { _ in throw IntegrationError.unavailable },
        packageManagement: { throw IntegrationError.unavailable }
    )

    /// Activated by the app composition root only after the existing services
    /// dependency cut and target graph have been delivered and verified.
    static func connected(to provider: HanlinMiniAppsProvider) -> Self {
        Self(catalog: { try await provider.catalog() },
             launch: { try await provider.launch($0) },
             packageManagement: { try provider.packageManagement() })
    }

    /// A real canonical discovery provider is injected by the existing host.
    init(discovery: any HanlinMiniAppDiscovery,
         launch: @escaping (HanlinMiniAppCatalogItem) async throws -> AnyView,
         packageManagement: @escaping () throws -> AnyView) {
        let catalog = HanlinCanonicalMiniAppCatalog(discovery: discovery)
        self.catalog = { try await catalog.items() }
        self.launch = launch; self.packageManagement = packageManagement
    }

    private init(catalog: @escaping () async throws -> [HanlinMiniAppCatalogItem],
                 launch: @escaping (HanlinMiniAppCatalogItem) async throws -> AnyView,
                 packageManagement: @escaping () throws -> AnyView) {
        self.catalog = catalog; self.launch = launch; self.packageManagement = packageManagement
    }
}
