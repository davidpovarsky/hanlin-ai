import CryptoKit
import Foundation
import HanlinCameraCaptureUI
import HanlinPlatformContracts
import HanlinScriptContracts
import HanlinScriptStore

/// Catalog of declared installed entrypoints. It intentionally does not consult
/// WidgetKit instances or the widget-only HanlinScriptPackageEntity query.
struct HanlinMiniAppSystemRecord: Hashable, Identifiable, Sendable {
    let id: String
    let productIdentifier: String
    let installedPackageID: HanlinInstalledPackageID
    let packageID: HanlinPackageID
    let generation: UInt64
    let entrypoint: HanlinPackageEntrypointDescriptor
    let title: String
    let summary: String
    let keywords: [String]
    let symbolName: String?
    let iconURL: URL?

    var cameraTarget: HanlinCameraCaptureTarget? {
        guard entrypoint.kind == .capture, let action = entrypoint.exportedSymbol else { return nil }
        return .init(productIdentifier: productIdentifier, installedPackageID: installedPackageID.rawValue,
            packageID: packageID.rawValue, generation: generation, entrypointID: entrypoint.id, actionID: action)
    }
}

enum HanlinMiniAppSystemCatalog {
    static func records(packages: [HanlinStoredPackageSnapshot], productIdentifier: String,
                        artifactRoot: (HanlinStoredPackageSnapshot) -> URL?) -> [HanlinMiniAppSystemRecord] {
        packages.filter(\.enabled).flatMap { package -> [HanlinMiniAppSystemRecord] in
            let app = package.entrypoints.first { $0.kind == .app &&
                ($0.runtimeProfile == .hanlinExpo || $0.runtimeProfile == .hanlinNativeScript) }
            guard let app else { return [] }
            return package.entrypoints.compactMap { entry in
                guard entry.kind == .spotlight || entry.kind == .capture,
                      entry.runtimeProfile == app.runtimeProfile, entry.sourcePath == app.sourcePath,
                      entry.supportedContexts.contains(.mainApplication) else { return nil }
                if let action = entry.exportedSymbol {
                    guard let descriptor = try? package.appDescriptor() else { return nil }
                    let matches = descriptor.actions.filter { $0.id.rawValue == action }
                    guard matches.count == 1, let declared = matches.first,
                          declared.handler == entry.sourcePath, !declared.capabilities.isEmpty else { return nil }
                } else if entry.kind == .capture {
                    // Captured files must reach a declared action, not merely an open app.
                    return nil
                }
                let manifest = package.manifest
                let language = Locale.preferredLanguages.first?.split(separator: "-").first.map(String.init)
                let title = language.flatMap { manifest?.localizedNames[$0] }
                    ?? manifest?.name ?? package.record.packageID.rawValue
                let summary = language.flatMap { manifest?.localizedDescriptions[$0] }
                    ?? manifest?.description ?? ""
                let keywords: [String]
                if case let .array(values)? = manifest?.unknownFields["keywords"] {
                    keywords = values.compactMap { if case let .string(value) = $0 { value } else { nil } }
                } else { keywords = [] }
                var iconURL: URL?
                if let icon = manifest?.iconImage, let root = artifactRoot(package),
                   let path = HanlinPackagePath.normalizedRelativePath(icon) {
                    let candidate = root.appending(path: path)
                    if let values = try? candidate.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                       values.isRegularFile == true, values.isSymbolicLink != true,
                       candidate.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/") {
                        iconURL = candidate
                    }
                }
                return .init(id: identifier(productIdentifier: productIdentifier,
                    installation: package.record.installedPackageID.rawValue, entrypoint: entry.id),
                    productIdentifier: productIdentifier, installedPackageID: package.record.installedPackageID,
                    packageID: package.record.packageID, generation: package.record.activeGeneration,
                    entrypoint: entry, title: title, summary: summary, keywords: keywords,
                    symbolName: manifest?.icon, iconURL: iconURL)
            }
        }.sorted { $0.id < $1.id }
    }

    static func identifier(productIdentifier: String, installation: String, entrypoint: String) -> String {
        // Length-prefixed UTF-8 prevents separator/Unicode ambiguity. The generation
        // is deliberately not in the key: an update replaces the same search item.
        var data = Data()
        for value in [productIdentifier, installation, entrypoint] {
            let bytes = Data(value.utf8)
            data.append(Data("\(bytes.count):".utf8)); data.append(bytes)
        }
        return productIdentifier + ".miniapp." + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
