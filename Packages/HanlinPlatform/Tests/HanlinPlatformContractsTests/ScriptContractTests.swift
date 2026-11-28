import Foundation
import Testing
@testable import HanlinPlatformContracts

@Test
func scriptManifestValidatesAndEncodesDeterministically() throws {
    let manifest = try scriptManifest()
    try manifest.validate(support: scriptSupport)

    let encoded = try manifest.canonicalJSONData()
    let decoded = try HanlinScriptPackageManifest.decodeAndValidate(
        encoded,
        support: scriptSupport
    )

    #expect(decoded == manifest)
    #expect(try decoded.canonicalJSONData() == encoded)
    #expect(decoded.entrypoint.exportedTools.map(\.id.rawValue) == ["echo"])
}

@Test
func scriptManifestRejectsUnsafePathsDuplicateToolsAndUnsupportedABI() throws {
    let manifest = try scriptManifest()
    let tool = try #require(manifest.entrypoint.exportedTools.first)
    let unsafe = HanlinScriptEntrypoint(
        documentKind: .assistantTool,
        sourcePath: "C:/assistant_tool.ts",
        compiledPath: "/assistant_tool.js",
        compilerLane: manifest.entrypoint.compilerLane,
        compilerVersion: manifest.entrypoint.compilerVersion,
        compilerConfigurationHash: manifest.entrypoint.compilerConfigurationHash,
        sourceIntegrity: manifest.entrypoint.sourceIntegrity,
        compiledIntegrity: manifest.entrypoint.compiledIntegrity,
        exportedTools: [tool, tool]
    )
    let invalid = HanlinScriptPackageManifest(
        schemaVersion: manifest.schemaVersion,
        descriptorRevision: manifest.descriptorRevision,
        packageID: manifest.packageID,
        version: manifest.version,
        displayName: manifest.displayName,
        runtime: .init(
            kind: .quickJS,
            engine: "quickjs-ng",
            engineVersion: "0.16.1",
            abiVersion: .init(major: 2, minor: 0),
            cancellation: manifest.runtime.cancellation
        ),
        entrypoint: unsafe,
        integrity: manifest.integrity
    )

    #expect(throws: HanlinContractError.self) {
        try invalid.validate(support: scriptSupport)
    }
}

@Test
func standardJSONPromotesToRichValuesWithoutNumericCollapse() throws {
    let json = try HanlinJSONValue.decodeCanonicalJSON(
        Data(#"{"integer":1,"number":1.0,"negativeZero":-0.0}"#.utf8)
    )
    let value = try HanlinValue(jsonValue: json)
    guard case let .object(members) = value else {
        Issue.record("Expected an object")
        return
    }

    #expect(members["integer"] == .integer(1))
    #expect(members["number"] == .number(1.0))
    if case let .number(negativeZero)? = members["negativeZero"] {
        #expect(negativeZero.bitPattern == (-0.0).bitPattern)
    } else {
        Issue.record("Expected a binary64 negative zero")
    }
}

@Test
func runtimeProfilesDeclareHonestIsolationAndTrustCapabilities() {
    let jsc = HanlinRuntimeCapabilities.canonical(for: .scriptingJSC)
    #expect(jsc.persistentContext)
    #expect(!jsc.hardMemoryLimit)
    #expect(!jsc.hardInterruption)
    #expect(jsc.scriptUI)

    let quickJS = HanlinRuntimeCapabilities.canonical(for: .hanlinQuickJS)
    #expect(quickJS.hardMemoryLimit)
    #expect(quickJS.hardStackLimit)
    #expect(quickJS.hardInterruption)

    let node = HanlinRuntimeCapabilities.canonical(for: .hanlinNode)
    #expect(node.trustedCodeOnly)
    #expect(!node.extensionSafe)
    #expect(!node.scriptUI)

    #expect(HanlinPackageTrust.publisherVerified.satisfies(.integrityVerified))
    #expect(!HanlinPackageTrust.localUnverified.satisfies(.integrityVerified))
}


private let scriptSupport = HanlinScriptContractSupport(
    manifestVersion: .init(major: 1, minor: 0),
    abiVersion: .init(major: 1, minor: 0),
    engine: "quickjs-ng",
    engineVersion: "0.16.1",
    compilerLane: "scripting-original",
    compilerVersion: "7.0.2"
)

private func scriptManifest() throws -> HanlinScriptPackageManifest {
    let schema = try ContractFixtures.jsonSchema(.object([
        "additionalProperties": .bool(false),
        "properties": .object([
            "text": .object(["type": .string("string")])
        ]),
        "required": .array([.string("text")]),
        "type": .string("object")
    ]))
    let digest = String(repeating: "a", count: 64)
    return HanlinScriptPackageManifest(
        schemaVersion: .init(major: 1, minor: 0),
        descriptorRevision: try HanlinDescriptorRevision(1),
        packageID: try HanlinPackageID(validating: "com.hanlin.fixture.echo"),
        version: try HanlinPackageVersion(validating: "1.0.0"),
        displayName: try LocalizedValue(["en": "Echo fixture"]),
        runtime: .init(
            kind: .quickJS,
            engine: "quickjs-ng",
            engineVersion: "0.16.1",
            abiVersion: .init(major: 1, minor: 0),
            cancellation: .init(
                interruptibleExecution: true,
                deadlineEnforcement: true
            )
        ),
        entrypoint: .init(
            documentKind: .assistantTool,
            sourcePath: "assistant_tool.ts",
            compiledPath: "assistant_tool.js",
            compilerLane: "scripting-original",
            compilerVersion: "7.0.2",
            compilerConfigurationHash: digest,
            sourceIntegrity: .init(algorithm: .sha256, digest: digest),
            compiledIntegrity: .init(algorithm: .sha256, digest: digest),
            exportedTools: [.init(
                id: try HanlinToolID(validating: "echo"),
                title: try LocalizedValue(["en": "Echo"]),
                summary: try LocalizedValue(["en": "Returns a deterministic value."]),
                inputSchema: schema
            )]
        ),
        integrity: .init(algorithm: .sha256, digest: digest)
    )
}
