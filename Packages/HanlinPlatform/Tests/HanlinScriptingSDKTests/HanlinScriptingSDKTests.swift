import Foundation
import HanlinScriptingSDK
import Testing

@Suite("Generated Scripting SDK foundation")
struct HanlinScriptingSDKTests {
    @Test("Loads integrity-checked declarations and registration metadata")
    func generatedResources() throws {
        let declarations = try HanlinScriptingSDK.declarations()
        let source = try #require(String(data: declarations, encoding: .utf8))
        #expect(source.contains("declare namespace Script"))
        #expect(source.contains("declare namespace Navigation"))
        #expect(source.contains("useState"))
        #expect(!source.contains("skipLibCheck"))

        let declarationFiles = try HanlinScriptingSDK.declarationFiles()
        #expect(declarationFiles.map(\.name) == HanlinScriptingSDK.declarationFileNames)
        #expect(declarationFiles.count == 6)
        #expect(declarationFiles.map(\.name) == [
            "global.d.ts", "node.d.ts", "safari-ext.d.ts",
            "scripting.d.ts", "web-fetch.d.ts", "miniapps.d.ts"
        ])
        #expect(declarationFiles.allSatisfy { !$0.data.isEmpty })

        let miniApps = try #require(declarationFiles.first { $0.name == "miniapps.d.ts" })
        let miniAppsSource = try #require(String(data: miniApps.data, encoding: .utf8))
        #expect(miniAppsSource.contains("export interface MiniAppSharing"))
        #expect(miniAppsSource.contains("getContext(): Promise<MiniAppSharedContext>"))
        #expect(miniAppsSource.contains("declare global { const MiniApps: MiniAppSharing; }"))
        #expect(!source.contains("MiniAppSharing"))

        let foundation = try HanlinScriptingSDK.foundationDeclarations()
        #expect(String(data: foundation, encoding: .utf8)?.contains("export const Script") == true)

        let metadata = try HanlinScriptingSDK.metadata()
        #expect(metadata.typescriptVersion == "7.0.2")
        #expect(metadata.records.map(\.symbol) == metadata.records.map(\.symbol).sorted())
        #expect(metadata.records.allSatisfy { !$0.declarationEvidence.isEmpty })
        #expect(metadata.records.first { $0.symbol == "fetch" }?.capability == "network")
        #expect(metadata.records.first { $0.symbol == "URL" }?.state.rawValue == "supported")
    }

    @Test("Generated manifest is stable canonical JSON")
    func manifest() throws {
        let data = try HanlinScriptingSDK.manifestData()
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["schemaVersion"] as? Int == 1)
        let files = try #require(object["files"] as? [String: String])
        #expect(files.count == 8)
        #expect(Set(files.keys) == Set([
            "global.d.ts", "node.d.ts", "safari-ext.d.ts", "scripting.d.ts",
            "web-fetch.d.ts", "miniapps.d.ts",
            "scripting-foundation.d.ts", "runtime-registration.json"
        ]))
        #expect(data.last == 0x0A)
    }
}
