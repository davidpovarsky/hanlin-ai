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
        stableAppID ?? (try! HanlinAppID(validating: "package.unknown"))
    }

    /// Extracts a stable canonical app ID from the manifest's `hanlinAppID` field
    /// if present and valid, falling back to the package ID.
    private var stableAppID: HanlinAppID? {
        if let manifest {
            if let explicit = manifest.hanlinAppID, let id = HanlinAppID(rawValue: explicit) {
                return id
            }
            if case let .string(rawID) = manifest.unknownFields["hanlinAppID"],
               let id = HanlinAppID(rawValue: rawID) {
                return id
            }
        }
        return HanlinAppID(rawValue: record.packageID.rawValue)
    }

    public func appDescriptor() throws -> HanlinAppDescriptor {
        let appID = try stableAppID ?? HanlinAppID(validating: record.packageID.rawValue)
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

        var packageExposures: [HanlinExposureKind] = []
        var seenExposures = Set<HanlinExposureKind>()
        for ep in entrypoints {
            let exp = ep.kind.exposureKind
            if seenExposures.insert(exp).inserted {
                packageExposures.append(exp)
            }
        }

        if let manifestExposures = manifest?.unknownFields["supportedExposures"] ?? manifest?.unknownFields["exposures"] {
            if case let .array(items) = manifestExposures {
                for item in items {
                    if case let .string(raw) = item {
                        let kind: HanlinExposureKind
                        switch raw {
                        case "translation_ui", "translationUI":
                            kind = .translationUI
                        case "widget":
                            kind = .widget
                        case "app_intent", "appIntent":
                            kind = .appIntent
                        default:
                            kind = HanlinExposureKind(rawValue: raw)
                        }
                        if seenExposures.insert(kind).inserted {
                            packageExposures.append(kind)
                        }
                    }
                }
            }
        }

        // Separate these concepts:
        // - explicit runtime on an entrypoint (ep.runtimeProfile)
        // - explicit package-level default runtime declared by manifest metadata
        // - implementation family
        // - observed runtime of some other entrypoint (must NOT be used as proof for sibling entrypoint)
        let manifestDeclaredPackageRuntime: HanlinRuntimeProfile? = {
            if let manifest {
                if let rt = manifest.hanlinRuntime, let profile = HanlinRuntimeProfile(rawValue: rt) {
                    return profile
                }
                if case let .string(rawRT) = manifest.unknownFields["hanlinRuntime"],
                   let profile = HanlinRuntimeProfile(rawValue: rawRT) {
                    return profile
                }
                if manifest.entry?.contains("nativescript") == true {
                    return .hanlinNativeScript
                }
            }
            return nil
        }()

        let mappedEntryPoints: [HanlinEntryPointDescriptor] = entrypoints.compactMap { ep in
            guard let canonicalKind = ep.kind.canonicalKind else { return nil }
            let contexts = ep.supportedContexts.isEmpty ? [.mainApplication] : Array(ep.supportedContexts)
            let epRuntime = ep.runtimeProfile
            return HanlinEntryPointDescriptor(
                kind: canonicalKind,
                handler: ep.sourcePath,
                allowedContexts: contexts,
                runtimeProfile: epRuntime
            )
        }

        let finalEntryPoints: [HanlinEntryPointDescriptor]
        if !mappedEntryPoints.isEmpty {
            finalEntryPoints = mappedEntryPoints
        } else if entrypoints.isEmpty {
            // Legacy script package with no explicit entrypoints.
            // Synthesize foreground app entrypoint when the legacy manifest represents an app.
            let isForegroundApp = manifest?.runInApp == true || manifest?.entry != nil || manifest == nil
            if isForegroundApp {
                let handler = manifest?.entry ?? "index.tsx"
                let epRuntime: HanlinRuntimeProfile? = manifestDeclaredPackageRuntime
                finalEntryPoints = [
                    HanlinEntryPointDescriptor(
                        kind: .app,
                        handler: handler,
                        allowedContexts: [.mainApplication],
                        runtimeProfile: epRuntime
                    )
                ]
                if seenExposures.insert(.foregroundApp).inserted {
                    packageExposures.append(.foregroundApp)
                }
            } else {
                finalEntryPoints = []
            }
        } else {
            // Package has explicit entrypoints, but none map to canonical executable HanlinEntryPointKind
            // (e.g. exposure-only package such as quickLook, capture, safariExtension).
            // Do NOT fabricate a foreground .app entrypoint.
            finalEntryPoints = []
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

        let entrypointRuntimes = Set(finalEntryPoints.compactMap(\.runtimeProfile))
        let hasNativeScript = entrypointRuntimes.contains(.hanlinNativeScript)
            || manifestDeclaredPackageRuntime == .hanlinNativeScript
        let hasOtherRuntime = entrypointRuntimes.contains { $0 != .hanlinNativeScript }
            || (manifestDeclaredPackageRuntime != nil && manifestDeclaredPackageRuntime != .hanlinNativeScript)

        let implementation: HanlinAppImplementation
        if hasNativeScript && !hasOtherRuntime {
            implementation = .nativeScript(packageID: record.packageID)
        } else if hasNativeScript && hasOtherRuntime {
            let modID = (try? HanlinModuleID(validating: record.packageID.rawValue))
                ?? (try! HanlinModuleID(validating: "package.hybrid"))
            implementation = .hybrid(moduleID: modID, packageID: record.packageID)
        } else {
            implementation = .script(packageID: record.packageID)
        }

        let isNativeScript = hasNativeScript
        let isExpo = entrypoints.contains { $0.runtimeProfile == .hanlinExpo }
            || manifestDeclaredPackageRuntime == .hanlinExpo

        let category: HanlinAppCategory = {
            if let catVal = manifest?.unknownFields["category"],
               case let .string(catStr) = catVal,
               let cat = HanlinAppCategory(rawValue: catStr) {
                return cat
            }
            return .utilities
        }()

        let isBeta: Bool = {
            if let betaVal = manifest?.unknownFields["isBeta"],
               case let .bool(b) = betaVal {
                return b
            }
            return false
        }()

        let iconDescriptor: HanlinIconDescriptor = if let icon = manifest?.icon, !icon.isEmpty {
            .systemSymbol(name: icon)
        } else if let iconImage = manifest?.iconImage, !iconImage.isEmpty {
            .packageResource(path: iconImage)
        } else if isNativeScript {
            .systemSymbol(name: "applescript")
        } else if isExpo {
            .systemSymbol(name: "sparkles")
        } else {
            .systemSymbol(name: "scroll")
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

        var packageActions: [HanlinActionDescriptor] = []
        if let actionsField = manifest?.unknownFields["actions"],
           case let .array(actionItems) = actionsField {
            for item in actionItems {
                if case let .object(actionObj) = item,
                   case let .string(actionIDStr) = actionObj["id"],
                   let actionID = try? HanlinActionID(validating: actionIDStr) {
                    let titleStr: String = {
                        if case let .string(s) = actionObj["title"] { return s }
                        return actionIDStr
                    }()
                    let capIDStr: String = {
                        if case let .string(s) = actionObj["capability"] { return s }
                        return "inter-app.share"
                    }()
                    let capID = (try? HanlinCapabilityID(validating: capIDStr))
                        ?? (try! HanlinCapabilityID(validating: "inter-app.share"))
                    let handler: String? = {
                        if case let .string(value) = actionObj["handler"] { return value }
                        if case let .string(value) = actionObj["entrypoint"] { return value }
                        return nil
                    }()
                    let titleVal = (try? LocalizedValue(["en": titleStr]))
                        ?? (try! LocalizedValue(["en": actionIDStr]))
                    if let schema = try? HanlinJSONSchemaDocument(dialect: .draft2020_12, root: .object([:])) {
                        packageActions.append(HanlinActionDescriptor(
                            id: actionID,
                            title: titleVal,
                            inputSchema: schema,
                            outputSchema: nil,
                            capabilities: [capID],
                            handler: handler,
                            risk: .read
                        ))
                    }
                }
            }
        }

        var packageSkills: [HanlinSkillDescriptor] = []
        if let skillsField = manifest?.unknownFields["skills"],
           case let .array(skillItems) = skillsField {
            for item in skillItems {
                if case let .object(skillObj) = item,
                   case let .string(skillIDStr) = skillObj["id"],
                   let skillID = try? HanlinSkillID(validating: skillIDStr) {
                    let titleStr: String = {
                        if case let .string(s) = skillObj["title"] { return s }
                        return skillIDStr
                    }()
                    let summaryStr: String = {
                        if case let .string(s) = skillObj["summary"] { return s }
                        if case let .string(s) = skillObj["description"] { return s }
                        return titleStr
                    }()
                    let titleVal = (try? LocalizedValue(["en": titleStr]))
                        ?? (try! LocalizedValue(["en": skillIDStr]))
                    let summaryVal = (try? LocalizedValue(["en": summaryStr]))
                        ?? titleVal

                    let instructionSource: HanlinSkillInstructionSource = {
                        if case let .string(text) = skillObj["instructions"] {
                            return .inline(text)
                        }
                        if case let .object(instObj) = skillObj["instructions"] {
                            if case let .string(text) = instObj["inline"] {
                                return .inline(text)
                            }
                            if case let .string(path) = instObj["resource"] ?? instObj["path"] {
                                return .resource(path: path)
                            }
                        }
                        if case let .string(path) = skillObj["resource"] {
                            return .resource(path: path)
                        }
                        return .inline("")
                    }()

                    var keywords: [String] = []
                    if case let .array(kwItems) = skillObj["keywords"] {
                        for kw in kwItems {
                            if case let .string(s) = kw { keywords.append(s) }
                        }
                    }

                    var triggerHints: [String] = []
                    if case let .array(thItems) = skillObj["triggerHints"] ?? skillObj["examples"] {
                        for th in thItems {
                            if case let .string(s) = th { triggerHints.append(s) }
                        }
                    }

                    var preferredTools: [String] = []
                    if case let .array(ptItems) = skillObj["preferredToolIDs"] ?? skillObj["preferredTools"] {
                        for pt in ptItems {
                            if case let .string(s) = pt { preferredTools.append(s) }
                        }
                    }

                    packageSkills.append(HanlinSkillDescriptor(
                        id: skillID,
                        title: titleVal,
                        summary: summaryVal,
                        instructions: instructionSource,
                        keywords: keywords,
                        triggerHints: triggerHints,
                        preferredToolIDs: preferredTools
                    ))
                }
            }
        }

        let descriptor = HanlinAppDescriptor(
            schemaVersion: .init(major: 1, minor: 0),
            descriptorRevision: try HanlinDescriptorRevision(1),
            id: appID,
            name: name,
            summary: summary,
            description: summary,
            version: record.version,
            apiVersion: .init(major: 1, minor: 0),
            icon: iconDescriptor,
            appearance: .init(accentHex: accentHex, isBeta: isBeta),
            category: category,
            implementation: implementation,
            entryPoints: finalEntryPoints,
            supportedExposures: packageExposures,
            actions: packageActions,
            skills: packageSkills,
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
