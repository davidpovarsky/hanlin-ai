import CryptoKit
import Foundation
import HanlinPlatformContracts
import HanlinScriptContracts
#if canImport(JavaScriptCore)
import JavaScriptCore
#endif

public struct HanlinWidgetPackageMetadata: Codable, Sendable {
    public enum SourceFormat: String, Codable, Sendable { case jsx, tsx, javascript; case expoLayout = "expo-layout" }
    public let abiVersion: UInt32
    public let sourceFormat: SourceFormat
    public let actions: [HanlinWidgetActionDeclaration]
    public let families: [String]
}

public enum HanlinWidgetCompiler {
    public static func prepare(
        manifest: HanlinScriptingManifest, entryPath: String, files: [String: Data]
    ) throws -> HanlinWidgetProgram {
        try manifest.validateWidgetMetadata()
        guard let engine = manifest.declaredWidgetEngine, engine != .legacy,
              let field = manifest.unknownFields["hanlinWidget"] else { throw HanlinWidgetProgramError.invalidProgram }
        let metadata = try JSONDecoder().decode(HanlinWidgetPackageMetadata.self, from: field.canonicalJSONData())
        guard metadata.abiVersion == HanlinWidgetProgram.abiVersion,
              let source = files[entryPath], source.count <= 512 * 1_024 else { throw HanlinWidgetProgramError.invalidSource }
        var sources: [String: String] = [:]
        for (path, data) in files where ["js", "jsx", "ts", "tsx"].contains(URL(filePath: path).pathExtension) {
            guard data.count <= 512 * 1_024, let text = String(data: data, encoding: .utf8) else { throw HanlinWidgetProgramError.invalidSource }
            sources[path] = text
        }
        guard sources.values.reduce(0, { $0 + $1.utf8.count }) <= 2 * 1_024 * 1_024,
              let babelURL = Bundle.module.url(forResource: "core", withExtension: "js"),
              let adapterURL = Bundle.module.url(forResource: "prepare-widget", withExtension: "js") else {
            throw HanlinWidgetProgramError.missingCompiler
        }
        let babel = try String(contentsOf: babelURL, encoding: .utf8)
        let adapter = try String(contentsOf: adapterURL, encoding: .utf8)
#if canImport(JavaScriptCore)
        // One invocation owns the VM; neither compiler contexts nor JSValues are cached.
        guard let context = JSContext() else { throw HanlinWidgetProgramError.missingCompiler }
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        let active: @convention(block) () -> Bool = { ContinuousClock.now < deadline }
        context.setObject(active, forKeyedSubscript: "__scriptWidgetCompileActive" as NSString)
        context.evaluateScript(babel)
        context.evaluateScript(adapter)
        let actionsData = try JSONEncoder().encode(metadata.actions)
        let actionObjects = try JSONSerialization.jsonObject(with: actionsData)
        let result = context.objectForKeyedSubscript("__hanlinCompileWidget")?.call(withArguments: [[
            "engine": engine.rawValue, "format": metadata.sourceFormat.rawValue,
            "entry": entryPath, "files": sources, "actions": actionObjects
        ]])
        if let exception = context.exception { throw HanlinWidgetProgramError.compilationFailed(exception.toString() ?? "Unknown compiler exception") }
        guard ContinuousClock.now < deadline, let javaScript = result?.toString(), !javaScript.isEmpty else {
            throw HanlinWidgetProgramError.compilationFailed("Compiler produced no output or exceeded its budget")
        }
        let program = HanlinWidgetProgram(engine: engine, sourceSHA256: digest(source),
            compilerSHA256: digest(Data((babel + adapter).utf8)), javaScript: javaScript,
            actions: metadata.actions, families: metadata.families,
            resources: files.filter { !sources.keys.contains($0.key) && !["script.json", "package.json"].contains($0.key) })
        try program.validate(engine: engine)
        return program
#else
        throw HanlinWidgetProgramError.missingCompiler
#endif
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
