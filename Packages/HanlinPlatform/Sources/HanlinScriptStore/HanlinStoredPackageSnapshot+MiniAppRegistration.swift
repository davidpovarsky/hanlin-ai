// HanlinStoredPackageSnapshot+MiniAppRegistration.swift
// HanlinScriptStore
//
// Bridges installed Scripting and NativeScript packages to the canonical
// HanlinMiniAppRegistration protocol, providing a unified root Mini App
// identity and descriptor model across all runtime families.

import Foundation
import HanlinPlatformContracts
import HanlinScriptContracts

extension HanlinStoredPackageSnapshot: HanlinMiniAppRegistration {
    public var appID: HanlinAppID {
        (try? HanlinAppID(validating: record.packageID.rawValue))
            ?? (try! HanlinAppID(validating: "package.unknown"))
    }

    public func appDescriptor() throws -> HanlinAppDescriptor {
        let appID = try HanlinAppID(validating: record.packageID.rawValue)
        let nameString = manifest?.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? manifest!.name
            : record.packageID.rawValue

        var namesDict: [String: String] = ["en": nameString]
        if let localized = manifest?.localizedNames {
            for (k, v) in localized where !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                namesDict[k] = v
            }
        }
        let name = try LocalizedValue(namesDict, fallbackLocale: "en")

        let descString = manifest?.description?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? manifest!.description!
            : nameString
        var descDict: [String: String] = ["en": descString]
        if let localized = manifest?.localizedDescriptions {
            for (k, v) in localized where !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                descDict[k] = v
            }
        }
        let summary = try LocalizedValue(descDict, fallbackLocale: "en")

        let mappedEntryPoints: [HanlinEntryPointDescriptor] = entrypoints.compactMap { ep in
            guard let canonicalKind = ep.kind.canonicalKind else { return nil }
            let contexts = ep.supportedContexts.isEmpty ? [.mainApplication] : Array(ep.supportedContexts)
            return HanlinEntryPointDescriptor(
                kind: canonicalKind,
                handler: ep.sourcePath,
                allowedContexts: contexts
            )
        }

        let capabilitiesDeclarations: [HanlinCapabilityDeclaration] = grantedCapabilities.map { capID in
            let reasonVal = (try? LocalizedValue(["en": "Granted capability"]))
                ?? (try! LocalizedValue(["en": "Default capability"]))
            return HanlinCapabilityDeclaration(
                id: capID,
                reason: reasonVal,
                constraints: .object([:]),
                risk: .read
            )
        }

        let authorList: [HanlinAuthor] = if let author = manifest?.author,
                                            !author.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            [HanlinAuthor(name: author.name, website: author.homepage.flatMap { URL(string: $0) })]
        } else {
            [HanlinAuthor(name: "Script Author")]
        }

        let isNativeScript = entrypoints.contains { $0.runtimeProfile == .hanlinNativeScript }

        let iconDescriptor: HanlinIconDescriptor = if let icon = manifest?.icon, !icon.isEmpty {
            .systemSymbol(name: icon)
        } else if let iconImage = manifest?.iconImage, !iconImage.isEmpty {
            .packageResource(path: iconImage)
        } else {
            .systemSymbol(name: isNativeScript ? "applescript" : "scroll")
        }

        let accentHex = manifest?.color.flatMap { color -> String? in
            let trimmed = color.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return trimmed.hasPrefix("#") ? trimmed : "#\(trimmed)"
        }

        let integrity: HanlinIntegrityDeclaration? = if record.sourceDigest.count == 64 {
            HanlinIntegrityDeclaration(
                algorithm: .sha256,
                digest: record.sourceDigest
            )
        } else {
            nil
        }

        let descriptor = HanlinAppDescriptor(
            schemaVersion: .init(major: 1, minor: 0),
            descriptorRevision: HanlinDescriptorRevision(1),
            id: appID,
            name: name,
            summary: summary,
            description: summary,
            version: record.version,
            apiVersion: .init(major: 1, minor: 0),
            icon: iconDescriptor,
            appearance: .init(accentHex: accentHex),
            category: .utilities,
            implementation: .script(packageID: record.packageID),
            entryPoints: mappedEntryPoints.isEmpty
                ? [HanlinEntryPointDescriptor(kind: .app, handler: "index.tsx", allowedContexts: [.mainApplication])]
                : mappedEntryPoints,
            capabilities: capabilitiesDeclarations,
            authors: authorList,
            distribution: .init(
                sourceVisible: true,
                sourceEditable: !isNativeScript,
                remoteUpdates: manifest?.remoteResource != nil,
                allowedModes: [.personalDevelopment]
            ),
            integrity: integrity
        )
        try descriptor.validate()
        return descriptor
    }
}
