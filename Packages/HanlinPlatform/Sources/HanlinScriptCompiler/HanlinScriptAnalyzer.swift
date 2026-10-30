import CryptoKit
import Foundation
import HanlinPlatformContracts
import HanlinScriptContracts
import HanlinWidgetCompiler

public struct HanlinAPISymbolRecord: Codable, Hashable, Sendable {
    public let symbol: String
    public let state: HanlinCompatibilityState
    public let requiredCapability: HanlinCapabilityID?
    public let allowedContexts: Set<HanlinExecutionContext>
    public let rationale: String?

    public init(
        symbol: String,
        state: HanlinCompatibilityState,
        requiredCapability: HanlinCapabilityID? = nil,
        allowedContexts: Set<HanlinExecutionContext> = [],
        rationale: String? = nil
    ) {
        self.symbol = symbol
        self.state = state
        self.requiredCapability = requiredCapability
        self.allowedContexts = allowedContexts
        self.rationale = rationale
    }
}

public struct HanlinCompatibilityInventory: Codable, Hashable, Sendable {
    public let schemaVersion: UInt32
    public let baselineID: String
    public let baselineDigest: String
    public let symbols: [HanlinAPISymbolRecord]

    public init(
        schemaVersion: UInt32 = 1,
        baselineID: String,
        baselineDigest: String,
        symbols: [HanlinAPISymbolRecord]
    ) {
        self.schemaVersion = schemaVersion
        self.baselineID = baselineID
        self.baselineDigest = baselineDigest
        self.symbols = symbols
    }
}

public struct HanlinScriptAnalyzer: Sendable {
    private static let nativeScriptRuntimeVersion = "9.1.0"
    private static let nativeScriptSwiftUIVersion = "4.0.2"
    private static let expoSDKVersion = "58.0.3"
    private static let expoUIVersion = "58.0.3"
    private static let expoUIBridgeVersion = "3.0.0"
    private static let reactNativeVersion = "0.88.0-rc.0"
    private let inventory: HanlinCompatibilityInventory
    private let symbols: [String: HanlinAPISymbolRecord]
    private var fileManager: FileManager { .default }

    public init(
        inventory: HanlinCompatibilityInventory
    ) {
        self.inventory = inventory
        symbols = Dictionary(
            inventory.symbols.map { ($0.symbol, $0) },
            uniquingKeysWith: { current, _ in current }
        )
    }

    public func analyze(_ package: HanlinStagedPackage) throws -> HanlinImportPreview {
        let files = try packageFiles(root: package.packageRoot)
        let sourcePaths = files.keys.filter(Self.isModule).sorted()
        let nativeScriptDeclared = package.manifest.hanlinRuntime == HanlinRuntimeProfile.hanlinNativeScript.rawValue
            || package.manifest.unknownFields["hanlinRuntime"] == .string(HanlinRuntimeProfile.hanlinNativeScript.rawValue)
        let expoDeclared = package.manifest.hanlinRuntime == HanlinRuntimeProfile.hanlinExpo.rawValue
            || package.manifest.unknownFields["hanlinRuntime"] == .string(HanlinRuntimeProfile.hanlinExpo.rawValue)
            || package.manifest.declaredWidgetEngine == .expo
        let scriptWidgetDeclared = package.manifest.declaredWidgetEngine == .scriptwidget
        let entrypoints = discoverEntrypoints(
            manifest: package.manifest,
            sourcePaths: sourcePaths
        )
        var edges: [HanlinPackageDependencyEdge] = []
        var unresolved: Set<String> = []
        var findings: [HanlinCompatibilityFinding] = []
        var importedSymbols: Set<String> = []
        let conventionalWidgets = ["widget.jsx", "widget.tsx", "widget.ts", "widget.js", "widget.json"].filter { files[$0] != nil }
        if !package.manifest.isWidgetOnlyPackage, conventionalWidgets.count > 1 {
            findings.append(.init(state: .unsupported, severity: .error, sourcePath: "script.json",
                message: "Ambiguous widget entrypoints: \(conventionalWidgets.joined(separator: ", ")). Supply one widget entrypoint; source order never selects an engine or program."))
        }
        if package.manifest.declaredWidgetEngine != nil && !entrypoints.contains(where: { $0.kind == .widget }) {
            findings.append(.init(state: .unsupported, severity: .error, sourcePath: "script.json", message: "widgetEngine requires a declared or discoverable widget entrypoint."))
        }

        do {
            try package.manifest.validateWidgetMetadata()
        } catch {
            findings.append(.init(state: .unsupported, severity: .error, sourcePath: "script.json",
                message: "Invalid widget manifest: \(error). Declare a supported engine and matching runtime explicitly."))
        }
        if let entry = package.manifest.entry,
           HanlinArchivePolicy.normalizedRelativePath(entry) != entry || files[entry] == nil {
            findings.append(.init(state: .unsupported, severity: .error, sourcePath: "script.json", message: "The declared entry must be a canonical existing package-relative source path."))
        }

        for path in sourcePaths where Self.isSource(path) {
            guard let data = files[path], let source = String(data: data, encoding: .utf8) else {
                findings.append(.init(
                    state: .unsupported,
                    severity: .error,
                    sourcePath: path,
                    message: "Source file is not valid UTF-8."
                ))
                continue
            }
            if !nativeScriptDeclared && !expoDeclared && !scriptWidgetDeclared {
                if Self.matches(#"\bimport\s*\("#, source) {
                    findings.append(.init(
                        state: .unsupported,
                        severity: .error,
                        sourcePath: path,
                        message: "Dynamic import is not supported in installed packages."
                    ))
                }
                if Self.matches(#"\beval\s*\("#, source) {
                    findings.append(.init(
                        state: .unsupported,
                        severity: .error,
                        sourcePath: path,
                        message: "eval is forbidden by the package module policy."
                    ))
                }
                importedSymbols.formUnion(Self.scriptingImports(in: source))
                importedSymbols.formUnion(Self.ambientScriptingSymbols(in: source))
                for specifier in Self.moduleSpecifiers(in: source) {
                    let resolved = resolve(
                        specifier: specifier,
                        importer: path,
                        modulePaths: Set(sourcePaths)
                    )
                    edges.append(.init(
                        importer: path,
                        specifier: specifier,
                        resolvedPath: resolved
                    ))
                    if resolved == nil && specifier != "scripting" {
                        unresolved.insert(specifier)
                        findings.append(.init(
                            state: .unsupported,
                            severity: .error,
                            sourcePath: path,
                            message: specifier.hasPrefix(".")
                                ? "Package-local module '\(specifier)' cannot be resolved."
                                : "Bare module '\(specifier)' is not allowed."
                        ))
                    }
                }
            }
        }

        if nativeScriptDeclared {
            Self.validatePreparedNativeScriptApplication(
                files: files,
                entrypoints: entrypoints,
                findings: &findings
            )
        } else if expoDeclared {
            Self.validatePreparedExpoApplication(
                files: files,
                entrypoints: entrypoints,
                declaredCapabilities: package.manifest.declaredCapabilities,
                findings: &findings
            )
        }

        for entrypoint in entrypoints where entrypoint.kind == .widget && entrypoint.widgetEngine != .legacy && entrypoint.widgetEngine != nil {
            do {
                _ = try HanlinWidgetCompiler.prepare(manifest: package.manifest, entryPath: entrypoint.sourcePath, files: files)
            } catch {
                findings.append(.init(state: .unsupported, severity: .error, sourcePath: entrypoint.sourcePath,
                    message: "Widget preparation failed: \(error)"))
            }
        }

        var capabilities: [HanlinCapabilityID: HanlinCapabilityRequest] = [:]
        for declaredCapability in package.manifest.declaredCapabilities {
            let purpose = declaredCapability.rawValue == "ios-native-api"
                ? "Broad native Objective-C/UIKit and JSI access."
                : "Declared in package manifest."
            capabilities[declaredCapability] = .init(
                capabilityID: declaredCapability,
                required: false,
                purpose: purpose
            )
        }
        for symbol in importedSymbols.sorted() {
            guard let record = symbols[symbol] else {
                findings.append(.init(
                    state: .unsupported,
                    severity: .error,
                    symbol: symbol,
                    message: "The imported symbol is absent from the authorized baseline."
                ))
                continue
            }
            findings.append(.init(
                state: record.state,
                severity: record.state == .unsupported ? .error : .information,
                symbol: symbol,
                message: "Scripting symbol '\(symbol)' is \(record.state.rawValue).",
                rationale: record.rationale
            ))
            let capability = record.requiredCapability ?? Self.inferredCapability(for: symbol)
            if let capability {
                capabilities[capability] = .init(
                    capabilityID: capability,
                    required: false,
                    purpose: "Required by imported Scripting symbol '\(symbol)'."
                )
            }
        }

        if entrypoints.isEmpty {
            findings.append(.init(
                state: .unsupported,
                severity: .error,
                message: "No supported Scripting entrypoint was found."
            ))
        }
        let resources = files.filter { !Self.isModule($0.key) }
        let extractedBytes = files.values.reduce(Int64(0)) { partial, data in
            partial > Int64.max - Int64(data.count) ? Int64.max : partial + Int64(data.count)
        }
        _ = resources // Resource descriptors are produced by the install plan in the next stage.

        let resolvedEntrypoints = entrypoints.map { descriptor in
            var requested = descriptor.requiredCapabilities
            requested.append(contentsOf: capabilities.values.filter { candidate in
                !requested.contains { $0.capabilityID == candidate.capabilityID }
            })
            return HanlinPackageEntrypointDescriptor(
                id: descriptor.id,
                kind: descriptor.kind,
                sourcePath: descriptor.sourcePath,
                exportedSymbol: descriptor.exportedSymbol,
                supportedContexts: descriptor.supportedContexts,
                requiredCapabilities: requested.sorted {
                    $0.capabilityID.rawValue < $1.capabilityID.rawValue
                },
                runtimePolicyID: descriptor.runtimePolicyID,
                runtimeProfile: descriptor.runtimeProfile,
                artifactDigest: descriptor.artifactDigest,
                compatibility: descriptor.compatibility,
                widgetEngine: descriptor.widgetEngine
            )
        }
        let approvalState = HanlinCapabilityApprovalState(
            requests: resolvedEntrypoints.flatMap(\.requiredCapabilities)
        )
        return HanlinImportPreview(
            source: package.source,
            archive: package.inspection,
            manifest: package.manifest,
            entrypoints: resolvedEntrypoints,
            dependencyGraph: .init(
                modules: sourcePaths,
                edges: edges.sorted {
                    ($0.importer, $0.specifier) < ($1.importer, $1.specifier)
                },
                unresolvedSpecifiers: unresolved.sorted()
            ),
            requestedCapabilities: approvalState.requests,
            findings: findings.sorted {
                ($0.sourcePath ?? "", $0.symbol ?? "", $0.message)
                    < ($1.sourcePath ?? "", $1.symbol ?? "", $1.message)
            },
            sourceBytes: package.source.byteCount,
            extractedBytes: extractedBytes
        )
    }

    private static func validatePreparedNativeScriptApplication(
        files: [String: Data],
        entrypoints: [HanlinPackageEntrypointDescriptor],
        findings: inout [HanlinCompatibilityFinding]
    ) {
        let appEntrypoints = entrypoints.filter { $0.kind == .app }
        guard appEntrypoints.count == 1, let entrypoint = appEntrypoints.first else {
            findings.append(.init(
                state: .unsupported,
                severity: .error,
                message: "A NativeScript package must declare exactly one foreground app entrypoint."
            ))
            return
        }
        let packageJSONPath = URL(filePath: entrypoint.sourcePath)
            .deletingLastPathComponent()
            .appending(path: "package.json")
            .relativePath
        guard let packageJSONData = files[packageJSONPath],
              let packageJSON = try? JSONSerialization.jsonObject(with: packageJSONData) as? [String: Any],
              packageJSON["main"] as? String == URL(filePath: entrypoint.sourcePath).lastPathComponent,
              packageJSON["hanlinRuntime"] as? String == HanlinRuntimeProfile.hanlinNativeScript.rawValue else {
            findings.append(.init(
                state: .unsupported,
                severity: .error,
                sourcePath: packageJSONPath,
                message: "NativeScript requires a prepared app package.json with matching main and hanlinRuntime fields."
            ))
            return
        }
        if let contractValue = packageJSON["hanlinNativeScript"] {
            guard let contract = contractValue as? [String: Any],
                  let runtimeVersion = contract["runtimeVersion"] as? String,
                  let plugins = contract["plugins"] as? [String: Any] else {
                findings.append(.init(
                    state: .unsupported,
                    severity: .error,
                    sourcePath: packageJSONPath,
                    message: "NativeScript hanlinNativeScript must declare string runtimeVersion and object plugins fields."
                ))
                return
            }
            guard runtimeVersion == nativeScriptRuntimeVersion else {
                findings.append(.init(
                    state: .unsupported,
                    severity: .error,
                    sourcePath: packageJSONPath,
                    message: "This Hanlin build supports NativeScript \(nativeScriptRuntimeVersion), but the package requires \(runtimeVersion)."
                ))
                return
            }
            for (name, value) in plugins.sorted(by: { $0.key < $1.key }) {
                guard let version = value as? String else {
                    findings.append(.init(
                        state: .unsupported,
                        severity: .error,
                        sourcePath: packageJSONPath,
                        message: "NativeScript plugin \(name) must declare a string version."
                    ))
                    continue
                }
                if name != "@nativescript/swift-ui" || version != nativeScriptSwiftUIVersion {
                    let supported = name == "@nativescript/swift-ui"
                        ? "\(name) \(nativeScriptSwiftUIVersion)"
                        : "only @nativescript/swift-ui \(nativeScriptSwiftUIVersion)"
                    findings.append(.init(
                        state: .unsupported,
                        severity: .error,
                        sourcePath: packageJSONPath,
                        message: "This Hanlin build supports \(supported), but the package requires \(name) \(version)."
                    ))
                } else {
                    findings.append(.init(
                        state: .supported,
                        severity: .information,
                        sourcePath: packageJSONPath,
                        message: "NativeScript plugin @nativescript/swift-ui \(nativeScriptSwiftUIVersion) has embedded native provider support."
                    ))
                }
            }
        }
        var declaredCoreVersion: String?
        if let deps = packageJSON["dependencies"] as? [String: Any], let version = deps["@nativescript/core"] as? String {
            declaredCoreVersion = version
        } else if let devDeps = packageJSON["devDependencies"] as? [String: Any], let version = devDeps["@nativescript/core"] as? String {
            declaredCoreVersion = version
        }
        if let coreVersion = declaredCoreVersion {
            if isCoreVersionCompatible(coreVersion) {
                findings.append(.init(
                    state: .supported,
                    severity: .information,
                    sourcePath: packageJSONPath,
                    message: "NativeScript core @nativescript/core \(coreVersion) is supported by embedded runtime \(nativeScriptRuntimeVersion)."
                ))
            } else {
                findings.append(.init(
                    state: .unsupported,
                    severity: .error,
                    sourcePath: packageJSONPath,
                    message: "This Hanlin build supports @nativescript/core \(nativeScriptRuntimeVersion), but the package requires \(coreVersion)."
                ))
            }
        }
        findings.append(.init(
            state: .supported,
            severity: .information,
            sourcePath: entrypoint.sourcePath,
            message: "Prepared NativeScript application structure is valid."
        ))
    }

    private static func isCoreVersionCompatible(_ versionString: String) -> Bool {
        let trimmed = versionString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "*" || trimmed == "latest" {
            return true
        }
        var cleaned = trimmed
        if cleaned.hasPrefix("^") || cleaned.hasPrefix("~") || cleaned.hasPrefix("=") || cleaned.hasPrefix("v") {
            cleaned = String(cleaned.dropFirst())
        }
        if cleaned.hasPrefix("9.1") {
            return true
        }
        if trimmed.hasPrefix("^9.") {
            return true
        }
        return false
    }

    private static func validatePreparedExpoApplication(
        files: [String: Data],
        entrypoints: [HanlinPackageEntrypointDescriptor],
        declaredCapabilities: [HanlinCapabilityID] = [],
        findings: inout [HanlinCompatibilityFinding]
    ) {
        let appEntrypoints = entrypoints.filter { $0.kind == .app }
        let widgetEntrypoints = entrypoints.filter { $0.kind == .widget }

        guard appEntrypoints.count <= 1, let entrypoint = appEntrypoints.first ?? widgetEntrypoints.first else {
            findings.append(.init(
                state: .unsupported,
                severity: .error,
                message: "Expo requires exactly one foreground app entrypoint; additional supported exposures are allowed."
            ))
            return
        }
        for candidate in entrypoints where candidate.kind != .app {
            switch candidate.kind {
            case .widget:
                findings.append(.init(
                    state: .supported,
                    severity: .information,
                    sourcePath: candidate.sourcePath,
                    message: "Expo widget exposure '\(candidate.sourcePath)' is supported via host services bridge."
                ))
            default:
                findings.append(.init(
                    state: .unsupported,
                    severity: .error,
                    sourcePath: candidate.sourcePath,
                    message: "Expo exposure '\(candidate.kind.rawValue)' is unsupported because no native executor is available."
                ))
            }
        }
        let entryDir = URL(filePath: entrypoint.sourcePath).deletingLastPathComponent().relativePath
        let candidateA = entryDir.isEmpty || entryDir == "." ? "package.json" : "\(entryDir)/package.json"
        let packageJSONPath = files[candidateA] != nil ? candidateA : "package.json"
        guard let packageJSONData = files[packageJSONPath],
              let packageJSON = try? JSONSerialization.jsonObject(with: packageJSONData) as? [String: Any],
              packageJSON["hanlinRuntime"] as? String == HanlinRuntimeProfile.hanlinExpo.rawValue else {
            findings.append(.init(
                state: .unsupported,
                severity: .error,
                sourcePath: packageJSONPath,
                message: "Expo requires a prepared app package.json with hanlinRuntime set to hanlin-expo."
            ))
            return
        }
        if !widgetEntrypoints.isEmpty, packageJSON["hanlinExpo"] == nil {
            findings.append(.init(state: .unsupported, severity: .error, sourcePath: packageJSONPath,
                message: "Expo widgets require an explicit hanlinExpo runtimeVersion/plugins contract."))
        }
        if let contractValue = packageJSON["hanlinExpo"] {
            guard let contract = contractValue as? [String: Any],
                  let runtimeVersion = contract["runtimeVersion"] as? String,
                  let plugins = contract["plugins"] as? [String: Any] else {
                findings.append(.init(
                    state: .unsupported,
                    severity: .error,
                    sourcePath: packageJSONPath,
                    message: "Expo hanlinExpo must declare string runtimeVersion and object plugins fields."
                ))
                return
            }
            guard isExpoVersionCompatible(runtimeVersion) else {
                findings.append(.init(
                    state: .unsupported,
                    severity: .error,
                    sourcePath: packageJSONPath,
                    message: "This Hanlin build supports Expo \(expoSDKVersion), but the package requires \(runtimeVersion)."
                ))
                return
            }
            if widgetEntrypoints.contains(where: { $0.widgetEngine == .expo }),
               runtimeVersion != expoSDKVersion || plugins["@expo/ui"] as? String != expoUIVersion {
                findings.append(.init(state: .unsupported, severity: .error, sourcePath: packageJSONPath,
                    message: "Native Expo widgets require the exact embedded runtime 58.0.3 and @expo/ui plugin 58.0.3."))
            }
            if let requiredBridgeVersion = contract["bridgeVersion"] as? String,
               !isVersion(requiredBridgeVersion, atMost: expoUIBridgeVersion) {
                findings.append(.init(
                    state: .unsupported,
                    severity: .error,
                    sourcePath: packageJSONPath,
                    message: "This Hanlin build provides @hanlin/expo-ui bridge \(expoUIBridgeVersion), but the package requires \(requiredBridgeVersion)."
                ))
            }
            for (name, value) in plugins.sorted(by: { $0.key < $1.key }) {
                guard let version = value as? String else {
                    findings.append(.init(
                        state: .unsupported,
                        severity: .error,
                        sourcePath: packageJSONPath,
                        message: "Expo plugin \(name) must declare a string version."
                    ))
                    continue
                }
                if name == "@nativescript/react-native" {
                    if version != "9.1.2" {
                        findings.append(.init(
                            state: .unsupported,
                            severity: .error,
                            sourcePath: packageJSONPath,
                            message: "This Hanlin build supports @nativescript/react-native 9.1.2, but the package requires \(version)."
                        ))
                    } else if !declaredCapabilities.contains(where: { $0.rawValue == "ios-native-api" }) {
                        findings.append(.init(
                            state: .unsupported,
                            severity: .error,
                            sourcePath: packageJSONPath,
                            message: "Expo package declaring '@nativescript/react-native' must declare 'ios-native-api' in capabilities."
                        ))
                    } else {
                        findings.append(.init(
                            state: .supported,
                            severity: .information,
                            sourcePath: packageJSONPath,
                            message: "Expo plugin @nativescript/react-native 9.1.2 has embedded native JSI & Fabric support."
                        ))
                    }
                    continue
                }
                if name == "react-native-worklets" {
                    if version != "0.13.1" {
                        findings.append(.init(
                            state: .unsupported,
                            severity: .error,
                            sourcePath: packageJSONPath,
                            message: "This Hanlin build supports react-native-worklets 0.13.1, but the package requires \(version)."
                        ))
                    } else {
                        findings.append(.init(
                            state: .supported,
                            severity: .information,
                            sourcePath: packageJSONPath,
                            message: "Expo plugin react-native-worklets 0.13.1 is supported as a build-embedded runtime dependency."
                        ))
                    }
                    continue
                }
                let supported = switch name {
                case "@expo/ui": isExpoVersionCompatible(version)
                case "@hanlin/expo-ui": isVersion(version, atMost: expoUIBridgeVersion)
                default: false
                }
                if !supported {
                    findings.append(.init(
                        state: .unsupported,
                        severity: .error,
                        sourcePath: packageJSONPath,
                        message: "This Hanlin build supports @expo/ui \(expoUIVersion) and @hanlin/expo-ui \(expoUIBridgeVersion), but the package requires \(name) \(version)."
                    ))
                } else {
                    findings.append(.init(
                        state: .supported,
                        severity: .information,
                        sourcePath: packageJSONPath,
                        message: "Expo plugin \(name) \(version) has embedded native SwiftUI support."
                    ))
                }
            }
        }
        if let deps = packageJSON["dependencies"] as? [String: Any], deps["@nativescript/react-native"] != nil, !declaredCapabilities.contains(where: { $0.rawValue == "ios-native-api" }) {
            findings.append(.init(
                state: .unsupported,
                severity: .error,
                sourcePath: packageJSONPath,
                message: "Expo package declaring '@nativescript/react-native' must declare 'ios-native-api' in capabilities."
            ))
        }
        var declaredUIVersion: String?
        if let deps = packageJSON["dependencies"] as? [String: Any], let version = deps["@expo/ui"] as? String {
            declaredUIVersion = version
        } else if let devDeps = packageJSON["devDependencies"] as? [String: Any], let version = devDeps["@expo/ui"] as? String {
            declaredUIVersion = version
        }
        if let uiVersion = declaredUIVersion {
            if isExpoVersionCompatible(uiVersion) {
                findings.append(.init(
                    state: .supported,
                    severity: .information,
                    sourcePath: packageJSONPath,
                    message: "Expo UI @expo/ui \(uiVersion) is supported by embedded runtime \(expoUIVersion)."
                ))
            } else {
                findings.append(.init(
                    state: .unsupported,
                    severity: .error,
                    sourcePath: packageJSONPath,
                    message: "This Hanlin build supports @expo/ui \(expoUIVersion), but the package requires \(uiVersion)."
                ))
            }
        }
        findings.append(.init(
            state: .supported,
            severity: .information,
            sourcePath: entrypoint.sourcePath,
            message: "Prepared Expo application structure is valid."
        ))
    }

    private static func isExpoVersionCompatible(_ versionString: String) -> Bool {
        let trimmed = versionString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "*" || trimmed == "latest" {
            return true
        }
        var cleaned = trimmed
        if cleaned.hasPrefix("^") || cleaned.hasPrefix("~") || cleaned.hasPrefix("=") || cleaned.hasPrefix("v") {
            cleaned = String(cleaned.dropFirst())
        }
        if cleaned.hasPrefix("58.") || trimmed.hasPrefix("^58.") {
            return true
        }
        return false
    }

    private static func isVersion(_ required: String, atMost installed: String) -> Bool {
        func components(_ value: String) -> [Int]? {
            var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("^") || trimmed.hasPrefix("~") || trimmed.hasPrefix("=") || trimmed.hasPrefix("v") {
                trimmed.removeFirst()
            }
            let pieces = trimmed.split(separator: ".").prefix(3)
            guard !pieces.isEmpty, pieces.allSatisfy({ Int($0) != nil }) else { return nil }
            let values = pieces.compactMap { Int($0) }
            return values + Array(repeating: 0, count: max(0, 3 - values.count))
        }
        guard let requiredComponents = components(required), let installedComponents = components(installed) else {
            return false
        }
        for (requiredPart, installedPart) in zip(requiredComponents, installedComponents) {
            if requiredPart != installedPart { return requiredPart < installedPart }
        }
        return true
    }

    private func packageFiles(root: URL) throws -> [String: Data] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return [:]
        }
        var result: [String: Data] = [:]
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(keys))
            guard values.isSymbolicLink != true else {
                throw HanlinPackageCenterError.unsafeArchive([.init(
                    code: .symbolicLink,
                    severity: .error,
                    entry: url.lastPathComponent,
                    message: "Extracted package contains a symbolic link."
                )])
            }
            guard values.isRegularFile == true else { continue }
            let depth = enumerator.level
            guard depth > 0, url.pathComponents.count >= depth else {
                throw HanlinPackageCenterError.stagingFailed
            }
            let relative = url.pathComponents.suffix(depth).joined(separator: "/")
                .replacingOccurrences(of: "\\", with: "/")
            guard let path = HanlinArchivePolicy.normalizedRelativePath(relative) else {
                throw HanlinPackageCenterError.stagingFailed
            }
            result[path] = try Data(contentsOf: url)
        }
        return result
    }

    private func discoverEntrypoints(
        manifest: HanlinScriptingManifest,
        sourcePaths: [String]
    ) -> [HanlinPackageEntrypointDescriptor] {
        let available = Set(sourcePaths)
        var candidates: [(String, HanlinPackageEntrypointKind, Set<HanlinExecutionContext>, String, HanlinWidgetEngine?)] = []
        let isWidgetOnly = manifest.isWidgetOnlyPackage

        if !isWidgetOnly {
            let appPath = manifest.entry.flatMap { available.contains($0) ? $0 : nil }
                ?? ["index.tsx", "index.ts", "index.jsx", "index.js", "index.py"].first { available.contains($0) }
            if let appPath {
                candidates.append((appPath, .app, [.mainApplication], "foreground-app-v1", nil))
            }
        }

        // Widget entrypoint from manifest.entry when widget-only
        if isWidgetOnly, let entry = manifest.entry, available.contains(entry) {
            let engine = manifest.declaredWidgetEngine ?? .legacy
            candidates.append((entry, .widget, [.widget], "widget-v1", engine))
        }

        let conventions: [(String, HanlinPackageEntrypointKind, HanlinExecutionContext, String, HanlinWidgetEngine?)] = [
            ("assistant_tool.tsx", .assistantTool, .mainApplication, "assistant-tool-v1", nil),
            ("assistant_tool.ts", .assistantTool, .mainApplication, "assistant-tool-v1", nil),
            ("embedded_result.tsx", .embeddedResult, .mainApplication, "embedded-result-v1", nil),
            ("embedded_result.ts", .embeddedResult, .mainApplication, "embedded-result-v1", nil),
            ("chat_card.tsx", .embeddedResult, .mainApplication, "embedded-result-v1", nil),
            ("chat_card.ts", .embeddedResult, .mainApplication, "embedded-result-v1", nil),
            ("widget.jsx", .widget, .widget, "widget-v1", .legacy),
            ("widget.tsx", .widget, .widget, "widget-v1", .legacy),
            ("widget.ts", .widget, .widget, "widget-v1", .legacy),
            ("widget.js", .widget, .widget, "widget-v1", .legacy),
            ("widget.json", .widget, .widget, "widget-v1", .legacy),
            ("app_intents.tsx", .appIntent, .appIntent, "app-intent-v1", nil),
            ("intent.tsx", .appIntent, .appIntent, "app-intent-v1", nil),
            ("intent.json", .appIntent, .appIntent, "app-intent-v1", nil),
            ("live_activity.tsx", .liveActivity, .liveActivity, "live-activity-v1", nil),
            ("translation_ui_provider.tsx", .translationUI, .translationUI, "translation-ui-v1", nil),
            ("translation_ui_provider.ts", .translationUI, .translationUI, "translation-ui-v1", nil),
            ("translation.json", .translationUI, .translationUI, "translation-ui-v1", nil),
            ("translation_ui.json", .translationUI, .translationUI, "translation-ui-v1", nil)
        ]
        var kinds = Set(candidates.map { $0.1 })
        for (path, kind, context, policy, defaultEngine) in conventions
            where available.contains(path) && kinds.insert(kind).inserted
        {
            let engine = (kind == .widget) ? (manifest.declaredWidgetEngine ?? defaultEngine) : nil
            candidates.append((path, kind, [context], policy, engine))
        }
        return candidates.map { path, kind, contexts, policy, engine in
            let requestedRuntime = manifest.hanlinRuntime ?? manifest.unknownFields["hanlinRuntime"].flatMap { value -> String? in
                if case let .string(rawValue) = value { rawValue } else { nil }
            }
            let profile: HanlinRuntimeProfile = if requestedRuntime == HanlinRuntimeProfile.hanlinNativeScript.rawValue {
                .hanlinNativeScript
            } else if requestedRuntime == HanlinRuntimeProfile.hanlinExpo.rawValue || engine == .expo {
                .hanlinExpo
            } else if path.lowercased().hasSuffix(".py") {
                .hanlinPython
            } else {
                .scriptingJSC
            }
            return .init(
                id: kind.rawValue,
                kind: kind,
                sourcePath: path,
                supportedContexts: contexts,
                runtimePolicyID: policy,
                runtimeProfile: profile,
                compatibility: .partial,
                widgetEngine: engine
            )
        }.sorted { ($0.kind.rawValue, $0.sourcePath) < ($1.kind.rawValue, $1.sourcePath) }
    }

    private func resolve(
        specifier: String,
        importer: String,
        modulePaths: Set<String>
    ) -> String? {
        if specifier == "scripting" { return "virtual:scripting" }
        guard specifier.hasPrefix(".") else { return nil }
        let parent = importer.split(separator: "/").dropLast().map(String.init)
        var components = parent
        for component in specifier.split(separator: "/") {
            switch component {
            case ".": continue
            case "..":
                guard !components.isEmpty else { return nil }
                components.removeLast()
            default: components.append(String(component))
            }
        }
        let base = components.joined(separator: "/")
        let candidates = [base, "\(base).ts", "\(base).tsx", "\(base).js", "\(base).jsx", "\(base).mjs", "\(base).json",
                          "\(base)/index.ts", "\(base)/index.tsx", "\(base)/index.js", "\(base)/index.jsx", "\(base)/index.mjs"]
        return candidates.first(where: modulePaths.contains)
    }

    private static func moduleSpecifiers(in source: String) -> [String] {
        let boundImports = captures(
            #"(?:from\s+|import\s*\(|require\s*\()\s*[\"']([^\"']+)[\"']"#,
            source
        )
        let sideEffectImports = captures(
            #"import\s*[\"']([^\"']+)[\"']"#,
            source
        )
        return Array(Set(boundImports + sideEffectImports)).sorted()
    }

    private static func scriptingImports(in source: String) -> Set<String> {
        let clauses = captures(
            #"import\s*\{([^}]+)\}\s*from\s*[\"']scripting[\"']"#,
            source
        )
        return Set(clauses.flatMap { clause in
            clause.split(separator: ",").compactMap { part in
                let name = part.trimmingCharacters(in: .whitespacesAndNewlines)
                    .split(separator: " ").first.map(String.init)
                return name?.isEmpty == false ? name : nil
            }
        })
    }

    private static func ambientScriptingSymbols(in source: String) -> Set<String> {
        let candidates = [
            "Assistant", "AssistantTool", "CacheStorage", "Dialog", "DocumentPicker", "EditorController", "FileManager", "Health",
            "IntentMemoryStorage", "Location", "Notification", "OpenURL", "Pasteboard", "Photos", "Reminder",
            "QuickLook", "Safari", "Storage", "addLocationListener"
        ]
        return Set(candidates.filter { symbol in
            matches("\\b\(NSRegularExpression.escapedPattern(for: symbol))\\b", source)
        })
    }

    private static func captures(_ pattern: String, _ source: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(source.startIndex..., in: source)
        return expression.matches(in: source, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: source)
            else { return nil }
            return String(source[range])
        }
    }

    private static func matches(_ pattern: String, _ source: String) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return false }
        return expression.firstMatch(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        ) != nil
    }

    private static func inferredCapability(for symbol: String) -> HanlinCapabilityID? {
        let mapping: [(Set<String>, String)] = [
            (["Storage", "CacheStorage", "IntentMemoryStorage"], "storage"),
            (["DocumentPicker", "FileManager", "QuickLook"], "files"),
            (["fetch", "Request", "Response", "Headers"], "network"),
            (["Assistant", "AssistantTool"], "assistant"),
            (["Location", "addLocationListener"], "location"),
            (["Notification"], "notifications"),
            (["Reminder"], "reminders"),
            (["Health"], "health"),
            (["Photos"], "photos"),
            (["Pasteboard"], "pasteboard"),
            (["OpenURL", "Safari"], "open-url")
        ]
        guard let raw = mapping.first(where: { $0.0.contains(symbol) })?.1 else { return nil }
        return try? HanlinCapabilityID(validating: raw)
    }

    private static func isModule(_ path: String) -> Bool {
        ["ts", "tsx", "js", "jsx", "mjs", "json", "py"].contains(
            URL(filePath: path).pathExtension.lowercased()
        )
    }

    private static func isSource(_ path: String) -> Bool {
        ["ts", "tsx", "js", "jsx", "mjs", "py"].contains(
            URL(filePath: path).pathExtension.lowercased()
        )
    }
}
