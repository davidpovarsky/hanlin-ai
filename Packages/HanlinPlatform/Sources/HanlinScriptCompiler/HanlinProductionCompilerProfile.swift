import Foundation

public enum HanlinProductionCompilerProfileError: Error, Equatable, Sendable {
    case missingResource
    case invalidProfile
    case projectOptionsMismatch
}

/// The single compiler-options authority shared by the on-device compiler and
/// deterministic pre-device acceptance tests.
public enum HanlinProductionCompilerProfile {
    public static func projectOptions() throws -> HanlinVirtualCompilerOptions {
        let options = try document().compilerOptions
        return HanlinVirtualCompilerOptions(
            target: options.target,
            libraries: options.lib,
            module: options.module,
            moduleResolution: options.moduleResolution,
            strict: options.strict,
            sourceMap: options.sourceMap,
            skipLibCheck: options.skipLibCheck,
            jsxRuntime: options.jsx
        )
    }

    public static func configurationData(
        for project: HanlinVirtualTypeScriptProject
    ) throws -> Data {
        let profile = try document()
        guard project.options == (try projectOptions()) else {
            throw HanlinProductionCompilerProfileError.projectOptionsMismatch
        }
        let configuration = Configuration(
            compilerOptions: profile.compilerOptions,
            files: (project.sources + project.declarationFiles)
                .map(\.logicalPath)
                .sorted()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(configuration)
    }

    public static func resourceData() throws -> Data {
        guard let url = Bundle.module.url(
            forResource: "production-compiler-profile",
            withExtension: "json"
        ) else {
            throw HanlinProductionCompilerProfileError.missingResource
        }
        return try Data(contentsOf: url)
    }

    private static func document() throws -> Document {
        let value = try JSONDecoder().decode(Document.self, from: resourceData())
        guard value.schemaVersion == 1,
              value.compilerOptions.lib == ["ESNext"],
              value.compilerOptions.types.isEmpty,
              value.compilerOptions.strict,
              value.compilerOptions.moduleResolution == "Bundler",
              value.compilerOptions.paths["scripting"] == ["./virtual/scripting.d.ts"]
        else {
            throw HanlinProductionCompilerProfileError.invalidProfile
        }
        return value
    }

    private struct Document: Codable {
        let schemaVersion: UInt32
        let compilerOptions: CompilerOptions
    }

    private struct Configuration: Encodable {
        let compilerOptions: CompilerOptions
        let files: [String]
    }

    private struct CompilerOptions: Codable {
        let target: String
        let lib: [String]
        let module: String
        let moduleResolution: String
        let strict: Bool
        let sourceMap: Bool
        let inlineSources: Bool
        let skipLibCheck: Bool
        let jsx: String
        let jsxFactory: String
        let jsxFragmentFactory: String
        let allowJs: Bool
        let checkJs: Bool
        let resolveJsonModule: Bool
        let esModuleInterop: Bool
        let types: [String]
        let paths: [String: [String]]
        let rootDir: String
        let outDir: String
        let newLine: String
    }
}
