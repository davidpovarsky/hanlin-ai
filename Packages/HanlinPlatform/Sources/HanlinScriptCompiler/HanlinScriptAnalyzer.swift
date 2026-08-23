import CryptoKit
import Foundation
import HanlinPlatformContracts
import HanlinScriptContracts

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
        let entrypoints = discoverEntrypoints(
            manifest: package.manifest,
            sourcePaths: sourcePaths
        )
        var edges: [HanlinPackageDependencyEdge] = []
        var unresolved: Set<String> = []
        var findings: [HanlinCompatibilityFinding] = []
        var importedSymbols: Set<String> = []

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

        var capabilities: [HanlinCapabilityID: HanlinCapabilityRequest] = [:]
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
                    required: true,
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

        return HanlinImportPreview(
            source: package.source,
            archive: package.inspection,
            manifest: package.manifest,
            entrypoints: entrypoints.map { descriptor in
                var requested = descriptor.requiredCapabilities
                requested.append(contentsOf: capabilities.values.filter { candidate in
                    !requested.contains { $0.capabilityID == candidate.capabilityID }
                })
                return .init(
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
                    compatibility: descriptor.compatibility
                )
            },
            dependencyGraph: .init(
                modules: sourcePaths,
                edges: edges.sorted {
                    ($0.importer, $0.specifier) < ($1.importer, $1.specifier)
                },
                unresolvedSpecifiers: unresolved.sorted()
            ),
            requestedCapabilities: capabilities.values.sorted {
                $0.capabilityID.rawValue < $1.capabilityID.rawValue
            },
            findings: findings.sorted {
                ($0.sourcePath ?? "", $0.symbol ?? "", $0.message)
                    < ($1.sourcePath ?? "", $1.symbol ?? "", $1.message)
            },
            sourceBytes: package.source.byteCount,
            extractedBytes: extractedBytes
        )
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
            let standardizedRootPath = root.standardizedFileURL.path()
            let rootPath = standardizedRootPath.hasSuffix("/") && standardizedRootPath.count > 1
                ? String(standardizedRootPath.dropLast())
                : standardizedRootPath
            let filePath = url.standardizedFileURL.path()
            guard filePath.hasPrefix(rootPath + "/") else {
                throw HanlinPackageCenterError.stagingFailed
            }
            let path = String(filePath.dropFirst(rootPath.count + 1))
                .replacingOccurrences(of: "\\", with: "/")
            result[path] = try Data(contentsOf: url)
        }
        return result
    }

    private func discoverEntrypoints(
        manifest: HanlinScriptingManifest,
        sourcePaths: [String]
    ) -> [HanlinPackageEntrypointDescriptor] {
        let available = Set(sourcePaths)
        var candidates: [(String, HanlinPackageEntrypointKind, Set<HanlinExecutionContext>, String)] = []
        let appPath = manifest.entry.flatMap { available.contains($0) ? $0 : nil }
            ?? ["index.tsx", "index.ts", "index.jsx", "index.js", "index.py"].first { available.contains($0) }
        if let appPath {
            candidates.append((appPath, .app, [.mainApplication], "foreground-app-v1"))
        }
        let conventions: [(String, HanlinPackageEntrypointKind, HanlinExecutionContext, String)] = [
            ("assistant_tool.tsx", .assistantTool, .mainApplication, "assistant-tool-v1"),
            ("assistant_tool.ts", .assistantTool, .mainApplication, "assistant-tool-v1"),
            ("widget.tsx", .widget, .widget, "widget-v1"),
            ("widget.ts", .widget, .widget, "widget-v1"),
            ("app_intents.tsx", .appIntent, .appIntent, "app-intent-v1"),
            ("intent.tsx", .appIntent, .appIntent, "app-intent-v1"),
            ("live_activity.tsx", .liveActivity, .liveActivity, "live-activity-v1")
        ]
        var kinds = Set(candidates.map { $0.1 })
        for (path, kind, context, policy) in conventions
            where available.contains(path) && kinds.insert(kind).inserted
        {
            candidates.append((path, kind, [context], policy))
        }
        return candidates.map { path, kind, contexts, policy in
            let profile: HanlinRuntimeProfile = path.lowercased().hasSuffix(".py")
                ? .hanlinPython : .scriptingJSC
            return .init(
                id: kind.rawValue,
                kind: kind,
                sourcePath: path,
                supportedContexts: contexts,
                runtimePolicyID: policy,
                runtimeProfile: profile,
                compatibility: .partial
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
        let candidates = [base, "\(base).ts", "\(base).tsx", "\(base).js", "\(base).jsx", "\(base).json",
                          "\(base)/index.ts", "\(base)/index.tsx", "\(base)/index.js", "\(base)/index.jsx"]
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
            (["FileManager"], "files"),
            (["fetch", "Request", "Response", "Headers"], "network"),
            (["Assistant", "AssistantTool"], "assistant"),
            (["Location", "addLocationListener"], "location"),
            (["Notification"], "notifications"),
            (["Health"], "health"),
            (["Pasteboard"], "pasteboard"),
            (["OpenURL", "Safari"], "open-url")
        ]
        guard let raw = mapping.first(where: { $0.0.contains(symbol) })?.1 else { return nil }
        return try? HanlinCapabilityID(validating: raw)
    }

    private static func isModule(_ path: String) -> Bool {
        ["ts", "tsx", "js", "jsx", "json", "py"].contains(
            URL(filePath: path).pathExtension.lowercased()
        )
    }

    private static func isSource(_ path: String) -> Bool {
        ["ts", "tsx", "js", "jsx", "py"].contains(
            URL(filePath: path).pathExtension.lowercased()
        )
    }
}
