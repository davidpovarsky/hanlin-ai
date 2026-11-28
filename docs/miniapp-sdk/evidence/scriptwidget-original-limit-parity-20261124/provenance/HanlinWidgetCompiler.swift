import CryptoKit
import Foundation
import HanlinPlatformContracts
import HanlinScriptContracts
@preconcurrency import HanlinScriptWidgetOriginal
#if canImport(JavaScriptCore)
import JavaScriptCore
#endif

public struct HanlinWidgetPackageMetadata: Codable, Sendable {
    public enum SourceFormat: String, Codable, Sendable { case jsx, tsx, javascript; case expoLayout = "expo-layout" }
    public let abiVersion: UInt32
    public let sourceFormat: SourceFormat
    public let actions: [HanlinWidgetActionDeclaration]
    public let families: [String]
    public init(abiVersion: UInt32 = 1, sourceFormat: SourceFormat,
                actions: [HanlinWidgetActionDeclaration] = [], families: [String]) {
        self.abiVersion = abiVersion
        self.sourceFormat = sourceFormat
        self.actions = actions
        self.families = families
    }
}

public enum HanlinWidgetCompiler {
    public static func prepare(
        manifest: HanlinScriptingManifest, entryPath: String, files: [String: Data]
    ) throws -> HanlinWidgetProgram {
        try manifest.validateWidgetMetadata()
        guard let engine = manifest.declaredWidgetEngine, engine != .legacy,
              let field = manifest.unknownFields["hanlinWidget"] else { throw HanlinWidgetProgramError.invalidProgram }
        let metadata = try JSONDecoder().decode(HanlinWidgetPackageMetadata.self, from: field.canonicalJSONData(limits: .unbounded))
        return try prepare(engine: engine, metadata: metadata, entryPath: entryPath, files: files,
                           includesOriginalWidgetManifest: true)
    }

    public static func preparePresentation(_ declaration: HanlinNativePresentationMetadata,
                                           files: [String: Data]) throws -> HanlinWidgetProgram {
        guard declaration.engine != .legacy,
              HanlinPackagePath.normalizedRelativePath(declaration.sourcePath) == declaration.sourcePath,
              let format = HanlinWidgetPackageMetadata.SourceFormat(rawValue: declaration.sourceFormat) else {
            throw HanlinWidgetProgramError.invalidSource
        }
        // Native presentation sources are a self-contained editable module tree.
        // The foreground Metro/NativeScript artifact is not a compiler input.
        let directory = (declaration.sourcePath as NSString).deletingLastPathComponent
        let scoped = directory.isEmpty ? files : files.filter { $0.key.hasPrefix(directory + "/") }
        return try prepare(engine: declaration.engine,
            metadata: .init(sourceFormat: format, actions: declaration.actions, families: ["systemLarge"]),
            entryPath: declaration.sourcePath, files: scoped)
    }

    private static func prepare(engine: HanlinWidgetEngine, metadata: HanlinWidgetPackageMetadata,
                                entryPath: String, files: [String: Data],
                                includesOriginalWidgetManifest: Bool = false) throws -> HanlinWidgetProgram {
        let metadata = try includesOriginalWidgetManifest
            ? originalScriptWidgetActions(engine: engine, metadata: metadata, entryPath: entryPath, files: files)
            : metadata
        guard metadata.abiVersion == HanlinWidgetProgram.abiVersion,
              let source = files[entryPath],
              let entrySource = String(data: source, encoding: .utf8) else { throw HanlinWidgetProgramError.invalidSource }
        if engine == .scriptwidget { try HanlinOriginalScriptWidgetSession.validateSource(entrySource) }
        // The declared format, not the filename extension, identifies the entry.
        // Expo-layout expressions commonly use .json or another asset suffix.
        var sources: [String: String] = [entryPath: entrySource]
        for (path, data) in files where ["js", "jsx", "ts", "tsx"].contains(URL(filePath: path).pathExtension) {
            // The compiler follows only the widget's module closure. A large
            // unrelated foreground Expo bundle is not a widget source module.
            if let text = String(data: data, encoding: .utf8) { sources[path] = text }
        }
        guard let babelURL = Bundle.module.url(forResource: "core", withExtension: "js"),
              let adapterURL = Bundle.module.url(forResource: "prepare-widget", withExtension: "js") else {
            throw HanlinWidgetProgramError.missingCompiler
        }
        let babel = try String(contentsOf: babelURL, encoding: .utf8)
        let adapter = try String(contentsOf: adapterURL, encoding: .utf8)
#if canImport(JavaScriptCore)
        // One invocation owns the VM; neither compiler contexts nor JSValues are cached.
        guard let context = JSContext() else { throw HanlinWidgetProgramError.missingCompiler }
        let deadline: ContinuousClock.Instant? = engine == .scriptwidget
            ? ContinuousClock.now.advanced(by: .seconds(HanlinOriginalScriptWidgetSession.compileTimeout)) : nil
        let active: @convention(block) () -> Bool = { deadline.map { ContinuousClock.now < $0 } ?? true }
        context.setObject(active, forKeyedSubscript: "__scriptWidgetCompileActive" as NSString)
        context.evaluateScript(babel)
        context.evaluateScript(adapter)
        let actionsData = try JSONEncoder().encode(metadata.actions)
        let actionObjects = try JSONSerialization.jsonObject(with: actionsData)
        let result = context.objectForKeyedSubscript("__hanlinCompileWidget")?.call(withArguments: [[
            "engine": engine.rawValue, "format": metadata.sourceFormat.rawValue,
            "entry": entryPath, "files": sources, "actions": actionObjects,
            "sourceByteLimit": engine == .scriptwidget ? HanlinOriginalScriptWidgetSession.maximumSourceBytes as Any : NSNull()
        ]])
        if let exception = context.exception { throw HanlinWidgetProgramError.compilationFailed(exception.toString() ?? "Unknown compiler exception") }
        guard active(), let javaScript = result?.toString(), !javaScript.isEmpty else {
            throw HanlinWidgetProgramError.compilationFailed("Compiler produced no output or exceeded its budget")
        }
        if engine == .scriptwidget { try HanlinOriginalScriptWidgetSession.validatePreparedJavaScript(javaScript) }
        var imports: [String: String] = [:]
        if engine == .scriptwidget, context.objectForKeyedSubscript("__hanlinWidgetUsesModules")?.toBool() != true {
            for (path, code) in sources where path != entryPath {
                try HanlinOriginalScriptWidgetSession.validateSource(code)
                let output = context.objectForKeyedSubscript("__hanlinCompileWidget")?.call(withArguments: [[
                    "engine": "scriptwidget-import", "format": "jsx", "entry": path, "files": sources, "actions": []
                ]])
                if let exception = context.exception { throw HanlinWidgetProgramError.compilationFailed(exception.toString() ?? "Import compilation failed") }
                guard active(), let text = output?.toString() else { throw HanlinWidgetProgramError.invalidSource }
                try HanlinOriginalScriptWidgetSession.validatePreparedJavaScript(text)
                imports[path] = text
            }
        }
        var resources = files.filter { !sources.keys.contains($0.key) && !["script.json", "package.json"].contains($0.key) }
        if engine == .scriptwidget { resources[entryPath] = source }
        let program = HanlinWidgetProgram(engine: engine, sourceSHA256: digest(source),
            compilerSHA256: digest(Data((babel + adapter).utf8)), javaScript: javaScript,
            actions: metadata.actions, families: metadata.families,
            resources: resources, imports: imports)
        try program.validate(engine: engine)
        return program
#else
        throw HanlinWidgetProgramError.missingCompiler
#endif
    }

    private static func originalScriptWidgetActions(engine: HanlinWidgetEngine,
        metadata: HanlinWidgetPackageMetadata, entryPath: String, files: [String: Data]) throws -> HanlinWidgetPackageMetadata {
        guard engine == .scriptwidget, let data = files["widget.json"] else { return metadata }
        let original = try HanlinOriginalScriptWidgetControls.read(data, entryPath: entryPath)
        var actions = metadata.actions
        func append(_ action: HanlinWidgetActionDeclaration) throws {
            if let existing = actions.first(where: { $0.id == action.id }) {
                guard existing == action else {
                    throw HanlinWidgetProgramError.compilationFailed(
                        "The original widget.json action conflicts with hanlinWidget.actions: " + action.id)
                }
            } else { actions.append(action) }
        }
        for action in original.actions {
            try append(.init(id: action.id, kind: .function, handler: action.handler))
        }
        for control in original.controls {
            try append(.init(id: control.preparedActionID, kind: control.kind == .toggle ? .setValue : .function,
                             handler: control.handler, stateKey: control.stateKey))
        }
        return .init(abiVersion: metadata.abiVersion, sourceFormat: metadata.sourceFormat,
                     actions: actions, families: metadata.families)
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
