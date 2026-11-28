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
        let widgetFiles = try AuthoringOwnership.project(manifest: manifest, entryPath: entryPath, files: files)
        return try prepare(engine: engine, metadata: metadata, entryPath: entryPath, files: widgetFiles,
                           includesOriginalWidgetManifest: true)
    }

    /// Host targets refer to an installed appIntent action. The authoring
    /// compiler never embeds a foreground runtime or executable source in a tap.
    public static func validateHostActionTargets(_ actions: [HanlinWidgetActionDeclaration],
        manifest: HanlinScriptingManifest, entrypoints: [HanlinPackageEntrypointDescriptor]) throws {
        for action in actions {
            guard action.kind == .hostAction else {
                guard action.hostAction == nil else {
                    throw HanlinWidgetProgramError.compilationFailed("Only hostAction may declare a Host target: " + action.id)
                }
                continue
            }
            guard action.handler == nil, action.stateKey == nil, let target = action.hostAction,
                  !target.entrypointID.isEmpty,
                  (try? HanlinActionID(validating: target.actionName)) != nil else {
                throw HanlinWidgetProgramError.compilationFailed("Invalid Host action target: " + action.id)
            }
            let entries = entrypoints.filter { $0.id == target.entrypointID && $0.kind == .appIntent }
            guard entries.count == 1, let entrypoint = entries.first,
                  entrypoint.runtimeProfile == .hanlinExpo || entrypoint.runtimeProfile == .hanlinNativeScript,
                  entrypoint.exportedSymbol == nil || entrypoint.exportedSymbol == target.actionName,
                  case let .array(declarations)? = manifest.unknownFields["actions"] else {
                throw HanlinWidgetProgramError.compilationFailed("Host action must name a declared appIntent and action: " + action.id)
            }
            let targets = declarations.compactMap { declaration -> HanlinObject<HanlinJSONValue>? in
                guard case let .object(fields) = declaration,
                      fields["id"] == .string(target.actionName) else { return nil }
                return fields
            }
            guard targets.count == 1, let declaration = targets.first else {
                throw HanlinWidgetProgramError.compilationFailed("Host action must name one declared package action: " + action.id)
            }
            if entrypoint.runtimePolicyID == "prepared-foreground-action-v1" {
                // Match installed action registration: a non-string handler
                // does not mask the legacy string entrypoint alias.
                let declared: String?
                if case let .string(value)? = declaration["handler"] { declared = value }
                else if case let .string(value)? = declaration["entrypoint"] { declared = value }
                else { declared = nil }
                let handler = declared.map { path in
                    if entrypoints.contains(where: { $0.sourcePath == path }) { return path }
                    let installedPath = "source/" + path
                    return entrypoints.contains(where: { $0.sourcePath == installedPath }) ? installedPath : path
                }
                guard handler == entrypoint.sourcePath else {
                    throw HanlinWidgetProgramError.compilationFailed("Host action handler must match its declared appIntent source: " + action.id)
                }
            }
        }
    }

    public static func preparePresentation(_ declaration: HanlinNativePresentationMetadata,
                                           files: [String: Data]) throws -> HanlinWidgetProgram {
        guard !declaration.actions.contains(where: { $0.kind == .hostAction }) else {
            throw HanlinWidgetProgramError.compilationFailed("Host actions are widget and Live Activity handoffs; native presentations use their local actions.")
        }
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

    /// A canonical source-bearing app has two consumers of its archive. Keep
    /// all bytes for installation; subtract only proven app/editor inputs from
    /// this Widget compilation. Inventory hashes do not establish ownership.
    private enum AuthoringOwnership {
        private typealias Object = HanlinObject<HanlinJSONValue>

        static func project(manifest: HanlinScriptingManifest, entryPath: String,
                            files: [String: Data]) throws -> [String: Data] {
            let native = manifest.hanlinRuntime == "hanlin-nativescript" && manifest.declaredWidgetEngine == .scriptwidget
            let expo = manifest.hanlinRuntime == "hanlin-expo" && manifest.declaredWidgetEngine == .expo
            guard manifest.runInApp, native || expo, let envelope = files["hanlin.authoring.json"],
                  let author = try? object(envelope), author["schemaVersion"] == .integer(1),
                  author["sourceRoot"] == .string("source") else { return files }

            let engine = native ? "nativescript" : "expo"
            guard author["engine"] == .string(engine),
                  let scriptBytes = files["script.json"],
                  let sourceScriptBytes = files["source/script.json"] else { throw invalid("authoring identity") }
            // projectInput overlays an optional retained descriptor on the
            // outer envelope when rebuilding an already source-bearing package.
            let inner: Object
            if let bytes = files["source/hanlin.authoring.json"] { inner = try object(bytes) }
            else { inner = [:] }
            let sourceEntry = try path(string(author["entry"]))
            let config = try path(string(author["tsconfig"]))
            guard inner["schemaVersion"] == nil || inner["schemaVersion"] == .integer(1),
                  inner["engine"] == nil || inner["engine"] == .string(engine),
                  (inner["entry"] ?? author["entry"]) == .string(sourceEntry),
                  (inner["tsconfig"] ?? author["tsconfig"]) == .string(config),
                  files["source/" + sourceEntry] != nil,
                  try JSONDecoder().decode(HanlinScriptingManifest.self, from: scriptBytes) == manifest else {
                throw invalid("retained project identity")
            }
            var script = try object(scriptBytes)
            var sourceScript = try object(sourceScriptBytes)
            guard sourceScript["hanlinRuntime"] == .string("hanlin-" + engine) else {
                throw invalid("retained runtime")
            }
            for key in ["entry", "runInApp", "hanlinRuntime"] { script[key] = nil; sourceScript[key] = nil }
            guard script == sourceScript else { throw invalid("retained manifest") }

            // The original readers enumerate visible files only. A hidden row
            // may be in the producer inventory, but is not claimed rehashed.
            let retained = try inventory(author["sourceHashes"], prefix: "source/", files: files)
            let compiled = try inventory(author["compiledHashes"], prefix: "", files: files)
            let visible = Set(files.keys.filter(isVisible))
            for name in visible {
                _ = try path(name)
                var parts = name.split(separator: "/")
                while parts.count > 1 {
                    parts.removeLast()
                    guard !visible.contains(parts.joined(separator: "/")) else { throw invalid("file/directory overlap") }
                }
            }
            guard Set(retained.map { Data(("source/" + $0).utf8) }) == Set(visible.filter { $0.hasPrefix("source/") }.map { Data($0.utf8) }),
                  Set(compiled.map { Data($0.utf8) }) == Set(visible.filter {
                      !$0.hasPrefix("source/") && $0 != "hanlin.authoring.json" && $0 != "hanlin.validation.json"
                  }.map { Data($0.utf8) }) else { throw invalid("incomplete visible inventory") }
            _ = try path(entryPath)
            guard !entryPath.hasPrefix("source/"), files[entryPath] != nil else { throw invalid("Widget/editor overlap") }

            var shared = Set<String>()
            let selectors: [HanlinJSONValue]
            if let value = inner["resources"] {
                guard case let .array(values) = value else { throw invalid("resources") }
                selectors = values
            } else { selectors = [] }
            for value in selectors {
                let selector = try resourcePath(string(value))
                let matches = retained.filter { selector.isEmpty || $0 == selector || $0.hasPrefix(selector + "/") }
                guard !matches.isEmpty || !isVisible(selector) else { throw invalid("missing resource") }
                for name in matches {
                    guard !name.hasPrefix("source/"), name != "source",
                          files[name] == files["source/" + name] else { throw invalid("resource/editor overlap or changed copy") }
                    shared.insert(name)
                }
            }
            let resourceCopies = shared
            // Native presentation sources/dependencies are also copied to the
            // package root by the same producer. Preserve all byte-exact copies,
            // including helpers whose dynamic import name is computed at runtime.
            for name in retained where !name.hasPrefix("source/") && files[name] == files["source/" + name] {
                shared.insert(name)
            }
            if let value = script["nativePresentations"] {
                guard case let .object(presentations) = value else { throw invalid("presentations") }
                for (_, value) in presentations {
                    guard case let .object(presentation) = value else { throw invalid("presentation") }
                    let name = try path(string(presentation["sourcePath"]))
                    guard shared.contains(name) else { throw invalid("presentation ownership") }
                }
            }
            shared.insert(entryPath)

            let appRoot = native ? "nativescript/app" : ""
            let appEntry = native ? "nativescript/app/bundle.mjs" : "bundle.js"
            guard manifest.entry == appEntry else { throw invalid("prepared app entry") }
            let sourcePackage: Object
            if let bytes = files["source/package.json"] { sourcePackage = try object(bytes) }
            else { sourcePackage = [:] }
            let appPackage = try package(at: appRoot, engine: engine, source: sourcePackage, files: files)
            let tools = try assistantRoots(script: script, inner: inner, sourceEntry: sourceEntry,
                                           appRoot: appRoot, native: native, retained: retained)
            var excluded = Set(retained.map { "source/" + $0 })

            if native {
                let outputs = try moduleOutputs(root: appRoot, retained: retained, files: files)
                guard let entryOutput = outputs[sourceEntry], let wrapper = files[appEntry],
                      try importSpecifier(wrapper, prefix: "import ", suffix: ";\n") == "./modules/" + entryOutput else {
                    throw invalid("prepared NativeScript entry module")
                }
                excluded.insert(appEntry)
                excluded.insert(appRoot + "/package.json")
                for output in outputs.values {
                    excluded.insert(appRoot + "/modules/" + output)
                    excluded.insert(appRoot + "/modules/" + output + ".map")
                }
                for tool in tools {
                    let toolPackage = try package(at: tool.root, engine: engine, source: sourcePackage, files: files)
                    guard toolPackage == appPackage, let output = outputs[tool.source],
                          let wrapper = files[tool.root + "/bundle.mjs"],
                          let firstLine = String(data: wrapper, encoding: .utf8)?.split(separator: "\n", omittingEmptySubsequences: false).first,
                          try importSpecifier(Data((String(firstLine) + "\n").utf8), prefix: "import * as tool from ", suffix: ";\n") == "./modules/" + output else {
                        throw invalid("prepared assistant module")
                    }
                    excluded.insert(tool.root + "/bundle.mjs")
                    excluded.insert(tool.root + "/package.json")
                    for output in outputs.values {
                        for suffix in [output, output + ".map"] {
                            let original = appRoot + "/modules/" + suffix
                            let copy = tool.root + "/modules/" + suffix
                            guard files[copy] == files[original] else { throw invalid("assistant module copy") }
                            excluded.insert(copy)
                        }
                    }
                }
                // The producer copies each declared resource both at the root
                // and into every native app's modules directory. Preserve every
                // alias before subtracting emitted modules with the same name.
                for root in [appRoot] + tools.map(\.root) {
                    for name in resourceCopies {
                        guard files[root + "/modules/" + name] == files[name] else { throw invalid("native resource copy") }
                    }
                    for name in shared {
                        let alias = root + "/modules/" + name
                        if let bytes = files[alias], bytes == files[name] { excluded.remove(alias) }
                    }
                }
            } else {
                for root in [appRoot] + tools.map(\.root) {
                    let prepared = try package(at: root, engine: engine, source: sourcePackage, files: files)
                    guard prepared == appPackage else { throw invalid("assistant package copy") }
                    let bundle = joined(root, "bundle.js")
                    guard files[bundle] != nil, files[bundle + ".map"] != nil else { throw invalid("Metro output pair") }
                    excluded.insert(bundle)
                    excluded.insert(bundle + ".map")
                }
            }
            // Declaring an app output as shared keeps its original parser and
            // size limits. No hash row grants permission to erase that resource.
            excluded.subtract(shared)
            return files.filter { !excluded.contains($0.key) }
        }

        private static func inventory(_ value: HanlinJSONValue?, prefix: String,
                                      files: [String: Data]) throws -> Set<String> {
            guard case let .object(rows)? = value, !rows.isEmpty else { throw invalid("inventory") }
            var visible = Set<String>()
            for (name, value) in rows {
                _ = try path(name)
                let expected = try string(value)
                guard HanlinWidgetProgram.isSHA256(expected) else { throw invalid("inventory digest") }
                guard isVisible(name) else { continue }
                guard visible.insert(name).inserted, let bytes = files[prefix + name], HanlinWidgetCompiler.digest(bytes) == expected else {
                    throw invalid("inventory bytes or aliased path")
                }
            }
            return visible
        }

        private static func moduleOutputs(root: String, retained: Set<String>, files: [String: Data]) throws -> [String: String] {
            // sourceRoot is a debugger location (possibly a URL), not an input
            // ownership boundary. Do not resolve it; bind the actual module path
            // and retained source bytes instead.
            var outputs: [String: String] = [:]
            for name in retained {
                let url = URL(fileURLWithPath: name)
                let ext = url.pathExtension
                guard ["ts", "tsx", "mts", "cts", "js", "jsx", "mjs", "cjs"].contains(ext),
                      ![".d.ts", ".d.mts", ".d.cts"].contains(where: { name.hasSuffix($0) }) else { continue }
                let stem = String(name.dropLast(ext.count))
                let extensions = ext == "mts" || ext == "mjs" ? ["mjs"] : ext == "cts" || ext == "cjs" ? ["cjs"] : ["js", "mjs"]
                for output in extensions.map({ stem + $0 }) {
                    let file = root + "/modules/" + output
                    guard files[file] != nil, let mapBytes = files[file + ".map"],
                          let map = try? object(mapBytes), map["version"] == .integer(3),
                          map["file"] == .string(URL(fileURLWithPath: output).lastPathComponent),
                          case .string(_)? = map["sourceRoot"],
                          case let .array(sources)? = map["sources"], sources.count == 1,
                          case let .string(source) = sources[0], source == name || source.hasSuffix("/" + name),
                          case let .array(contents)? = map["sourcesContent"], contents.count == 1,
                          case let .string(content) = contents[0], Data(content.utf8) == files["source/" + name] else { continue }
                    guard outputs.updateValue(output, forKey: name) == nil else { throw invalid("ambiguous emitted module") }
                }
            }
            return outputs
        }

        private struct AssistantRoot { let root: String; let source: String }

        private static func assistantRoots(script: Object, inner: Object, sourceEntry: String,
                                           appRoot: String, native: Bool, retained: Set<String>) throws -> [AssistantRoot] {
            let declarations: [HanlinJSONValue]
            if let value = script["entrypoints"] {
                guard case let .array(entries) = value else { throw invalid("entrypoints") }
                declarations = entries
            } else { declarations = [] }
            let sources: Object
            if let value = inner["assistantTools"] {
                guard case let .object(entries) = value else { throw invalid("assistant sources") }
                sources = entries
            } else { sources = [:] }
            var identifiers = Set<String>()
            var roots: [AssistantRoot] = []
            for value in declarations {
                guard case let .object(entry) = value else { throw invalid("entrypoint") }
                guard entry["kind"] == .string("assistantTool") else { continue }
                let id = try string(entry["id"])
                let source = try path(string(sources[id]))
                let output = try path(string(entry["sourcePath"]))
                let parts = output.split(separator: "/")
                guard !id.isEmpty, id != "app", id != "widget", identifiers.insert(id).inserted,
                      retained.contains(source), source != sourceEntry,
                      parts.count > 1, parts.last.map({ String($0) }) == (native ? "bundle.mjs" : "bundle.js") else { throw invalid("assistant entry") }
                let root = parts.dropLast().joined(separator: "/")
                guard !overlaps(root, "source"), (!native || !overlaps(root, appRoot)),
                      !roots.contains(where: { overlaps($0.root, root) }) else { throw invalid("assistant root overlap") }
                roots.append(.init(root: root, source: source))
            }
            guard identifiers == Set(sources.keys) else { throw invalid("assistant source inventory") }
            return roots
        }

        private static func package(at root: String, engine: String, source: Object, files: [String: Data]) throws -> Object {
            guard let bytes = files[joined(root, "package.json")] else { throw invalid("prepared package") }
            let prepared = try object(bytes)
            guard prepared["main"] == .string(engine == "expo" ? "bundle.js" : "bundle.mjs"),
                  prepared["hanlinRuntime"] == .string("hanlin-" + engine),
                  prepared["name"] == source["name"], prepared["version"] == source["version"],
                  engine != "nativescript" || prepared["type"] == .string("module") else { throw invalid("prepared package identity") }
            return prepared
        }

        private static func importSpecifier(_ bytes: Data, prefix: String, suffix: String) throws -> String {
            guard let text = String(data: bytes, encoding: .utf8), text.hasPrefix(prefix), text.hasSuffix(suffix) else {
                throw invalid("prepared wrapper")
            }
            let quoted = text.dropFirst(prefix.count).dropLast(suffix.count)
            return try string(HanlinJSONValue.decodeCanonicalJSON(Data(quoted.utf8), limits: .unbounded))
        }

        private static func object(_ data: Data) throws -> Object {
            guard case let .object(value) = try HanlinJSONValue.decodeCanonicalJSON(data, limits: .unbounded) else {
                throw invalid("metadata object")
            }
            return value
        }

        private static func string(_ value: HanlinJSONValue?) throws -> String {
            guard case let .string(value)? = value else { throw invalid("metadata string") }
            return value
        }

        private static func path(_ value: String) throws -> String {
            guard !value.isEmpty, !value.hasPrefix("/"), !value.contains("\\"), !value.contains(":"),
                  !value.unicodeScalars.contains(where: { $0.value < 32 }),
                  value.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
                throw invalid("relative path")
            }
            return value
        }

        private static func resourcePath(_ value: String) throws -> String {
            guard !value.isEmpty, !value.hasPrefix("/"), !value.contains("\\"), !value.contains(":"),
                  !value.unicodeScalars.contains(where: { $0.value < 32 }) else { throw invalid("resource path") }
            var parts: [Substring] = []
            for part in value.split(separator: "/") {
                if part == "." { continue }
                if part == ".." {
                    guard !parts.isEmpty else { throw invalid("escaping resource") }
                    parts.removeLast()
                } else { parts.append(part) }
            }
            return parts.joined(separator: "/")
        }

        private static func isVisible(_ path: String) -> Bool { !path.split(separator: "/").contains { $0.hasPrefix(".") } }
        private static func joined(_ root: String, _ name: String) -> String { root.isEmpty ? name : root + "/" + name }
        private static func overlaps(_ left: String, _ right: String) -> Bool { left == right || left.hasPrefix(right + "/") || right.hasPrefix(left + "/") }
        private static func invalid(_ reason: String) -> HanlinWidgetProgramError {
            .compilationFailed("Mixed Widget input ownership is invalid: " + reason)
        }
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
        var deadline: ContinuousClock.Instant? = engine == .scriptwidget
            ? ContinuousClock.now.advanced(by: .seconds(HanlinOriginalScriptWidgetSession.compileTimeout)) : nil
        // Upstream starts this deadline for each compiler invocation. A package
        // can contain independently compiled modules and $import sources.
        let begin: @convention(block) () -> Void = {
            deadline = engine == .scriptwidget
                ? ContinuousClock.now.advanced(by: .seconds(HanlinOriginalScriptWidgetSession.compileTimeout)) : nil
        }
        let active: @convention(block) () -> Bool = { deadline.map { ContinuousClock.now < $0 } ?? true }
        context.setObject(begin, forKeyedSubscript: "__scriptWidgetBeginCompile" as NSString)
        context.setObject(active, forKeyedSubscript: "__scriptWidgetCompileActive" as NSString)
        context.evaluateScript(babel)
        context.evaluateScript(adapter)
        guard active() else {
            throw HanlinWidgetProgramError.compilationFailed("Compiler exceeded the original ScriptWidget time limit")
        }
        let actionsData = try JSONEncoder().encode(metadata.actions)
        let actionObjects = try JSONSerialization.jsonObject(with: actionsData)
        let result = context.objectForKeyedSubscript("__hanlinCompileWidget")?.call(withArguments: [[
            "engine": engine.rawValue, "format": metadata.sourceFormat.rawValue,
            "entry": entryPath, "files": sources, "actions": actionObjects,
            "sourceByteLimit": engine == .scriptwidget ? HanlinOriginalScriptWidgetSession.maximumSourceBytes as Any : NSNull()
        ]])
        if let exception = context.exception { throw HanlinWidgetProgramError.compilationFailed(exception.toString() ?? "Unknown compiler exception") }
        // Every original transform checked its own deadline. Packaging the
        // resulting modules must not be charged to the last module's clock.
        guard let javaScript = result?.toString(), !javaScript.isEmpty else {
            throw HanlinWidgetProgramError.compilationFailed("Compiler produced no output")
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
                guard let text = output?.toString() else { throw HanlinWidgetProgramError.invalidSource }
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
