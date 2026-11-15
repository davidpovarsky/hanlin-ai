import Foundation
import HanlinMiniAppCore
import HanlinPlatformContracts
import SwiftUI

/// Both products compile these existing host sources. Each process owns its
/// lifetime and private container; AI's original store remains in place.
@MainActor
enum MiniAppsComposition {
    static func makeServices() async throws -> MiniAppsServices {
        let platform = HanlinScriptingPlatform.shared
        let host = HanlinMiniAppHost.shared
        return MiniAppsServices(catalog: {
            await platform.restore()
            if let error = platform.bootstrapError { throw HostError.unavailable(error) }
            await host.refresh(installedPackages: platform.installedPackages)
            if let error = host.lastError { throw HostError.unavailable(error) }
            return host.visibleItems
        }, launch: { item in
            switch item.engine {
            case .swift:
                return try host.swiftDestination(for: item).view
            case .nativeScript:
                try await host.launchNativeScript(item, platform: platform)
            case .expo:
                try await host.launchExpo(item, platform: platform)
            case .scriptingJSC:
                try await host.launchScriptingJSC(item, platform: platform)
            }
            guard platform.activeApplicationID != nil else {
                if case let .failed(message) = platform.activity { throw HostError.unavailable(message) }
                throw HostError.unavailable("The app could not be opened.")
            }
            return AnyView(ScriptingApplicationContainerView(platform: platform))
        }, packageManagement: {
            AnyView(MiniAppsPackageManagementView(platform: platform))
        })
    }

    private enum HostError: LocalizedError {
        case unavailable(String)
        var errorDescription: String? {
            switch self { case let .unavailable(message): message }
        }
    }
}

/// Package operations remain in the original platform and its existing screens.
private struct MiniAppsPackageManagementView: View {
    let platform: HanlinScriptingPlatform
    @State private var importing = false

    var body: some View {
        List {
            Section {
                Button("Import package", systemImage: "square.and.arrow.down") { importing = true }
                    .accessibilityIdentifier("miniapps.import")
            }
            Section("Installed packages") {
                ForEach(platform.installedPackages, id: \.record.installedPackageID) { package in
                    NavigationLink {
                        ScriptingInstalledPackageDetailView(packageID: package.record.installedPackageID,
                                                           platform: platform)
                    } label: {
                        LabeledContent(package.manifest?.name ?? package.record.packageID.rawValue,
                                       value: package.record.version.description)
                    }
                }
            }
        }
        .navigationTitle("Packages")
        .task { await platform.restore() }
        .sheet(isPresented: $importing) {
            NavigationStack { ScriptingPackageImportView(platform: platform) }
        }
    }
}
