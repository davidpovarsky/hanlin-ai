import Foundation
import HanlinExpoNativeAPI
import HanlinPlatformContracts
import Testing
@testable import AI_Hanlin

@MainActor
@Suite("Autonomous runtime policy and canonical Skill execution", .serialized)
struct HanlinAutonomousRuntimeTests {
    @Test("Embedded Node performs real TLS GET and POST through fetch and node:https")
    func embeddedNodeHTTPSRoundTrips() async throws {
        let result = try await AppRuntimeCore.shared.node.networkDiagnostics(rounds: 1)
        print("HANLIN_NODE_HTTPS_DIAGNOSTIC \(result.stdout) \(result.stderr)")
        #expect(result.exitCode == 0, "\(result.stderr)")
        let report = try #require(JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any])
        let requests = try #require(report["requests"] as? [[String: Any]])
        #expect(requests.count == 4)
        #expect(report["passed"] as? Bool == true, "\(result.stdout)")
        #expect(requests.allSatisfy { $0["nonceMatched"] as? Bool == true })
    }

    @Test("A real JS/Python/TS Skill resource is read without executing, then executed through its catalog source",
          arguments: ["js", "py", "ts"])
    func canonicalSkillResourceReadAndExecute(fileExtension: String) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let nonce = UUID().uuidString.lowercased()
        let skillID = try HanlinSkillID(validating: "runtime-probe-\(nonce)")
        let relativePath = "scripts/probe.\(fileExtension)"
        let file = root.appendingPathComponent("probe.\(fileExtension)")
        let sentinel = root.appendingPathComponent("executed-\(nonce)")
        let source: String
        if fileExtension == "py" {
            source = """
            import os, sys
            assert '\(nonce)' in sys.argv and 'עברית' in sys.argv
            with open(os.path.join(os.environ['SKILL_RESOURCE_DIR'], 'executed-\(nonce)'), 'w') as f:
                f.write('actual-python-execution')
            print('SKILL_EXECUTED=\(nonce)')
            """
        } else {
            let annotation = fileExtension == "ts" ? ": string" : ""
            source = """
            import fs from 'node:fs';
            import path from 'node:path';
            const nonce\(annotation) = '\(nonce)';
            if (!process.argv.includes(nonce) || !process.argv.includes('עברית')) throw new Error('Skill argv lost');
            fs.writeFileSync(path.join(process.env.SKILL_RESOURCE_DIR, 'executed-' + nonce), 'actual-node-execution');
            console.log('SKILL_EXECUTED=' + nonce);
            export default { nonce };
            """
        }
        try source.write(to: file, atomically: true, encoding: .utf8)
        // A stale same-ID store directory must not override the selected package
        // resolver, or supply a missing file from another source/generation.
        try SkillStore.shared.saveCustomSkill(id: skillID, title: "Unselected Store Source", description: "Resolver collision", instructions: "Not the selected source")
        defer { SkillStore.shared.deleteCustomSkill(skillID: skillID) }
        try SkillStore.shared.addOrUpdateTextResource(for: skillID, relativePath: relativePath, content: "WRONG_STORE_SOURCE")
        try SkillStore.shared.addOrUpdateTextResource(for: skillID, relativePath: "references/stale.md", content: "WRONG_STALE_SOURCE")
        let catalog = HanlinSkillCatalog()
        catalog.register(
            skill: try HanlinSkillDescriptor(id: skillID, title: "Runtime Probe", summary: "Canonical resource", instructions: .inline("Read, then execute the resource.")),
            tier: .installedPackage,
            resourceResolver: { path in path == relativePath ? file : nil }
        )
        let session = AssistantCapabilitySession()
        session.recordSkillLoaded(id: skillID, instructionText: "Read, then execute the resource.")
        let readArguments = try JSONSerialization.data(withJSONObject: ["skill_id": skillID.rawValue, "relative_path": relativePath])
        let read = await ReadSkillResourceTool.execute(argumentsJSON: String(decoding: readArguments, as: UTF8.self), session: session, catalog: catalog)
        #expect(read.contains("SKILL_EXECUTED"))
        #expect(!FileManager.default.fileExists(atPath: sentinel.path), "Reading script text must never execute it")
        let missingArguments = try JSONSerialization.data(withJSONObject: ["skill_id": skillID.rawValue, "relative_path": "references/stale.md"])
        let missing = await ReadSkillResourceTool.execute(argumentsJSON: String(decoding: missingArguments, as: UTF8.self), session: session, catalog: catalog)
        #expect(missing.contains("not found"), "A missing selected-source resource must not fall through to a stale store")

        let arguments = try JSONSerialization.data(withJSONObject: [
            "skill_id": skillID.rawValue, "relative_path": relativePath,
            "arguments": [nonce, "עברית"], "timeout_seconds": 60
        ])
        let result = await ExecuteSkillResourceTool(catalog: catalog).execute(
            argumentsJSON: String(decoding: arguments, as: UTF8.self),
            context: NativeToolExecutionContext(localeIdentifier: "he", toolCallID: "same-call-id", capabilitySession: session)
        )
        #expect(result.outcome == .succeeded, "\(fileExtension): \(result.modelText)")
        #expect(result.modelText.contains("SKILL_EXECUTED=\(nonce)"))
        #expect(FileManager.default.fileExists(atPath: sentinel.path), "The actual runtime must execute the resource")
    }

    @Test("Native API remains available for active runtimes without an internal grant, and closes with the session")
    func nativeAPIGrantlessSessionAndTeardown() {
        HanlinExpoNativeAPIManager.revokeActiveSession()
        defer { HanlinExpoNativeAPIManager.revokeActiveSession() }
        #expect(!HanlinExpoNativeAPIManager.isAuthorized())
        HanlinExpoNativeAPIManager.registerSession(sessionID: "autonomous-a", packageID: "fixture-a", isGranted: false, generation: 1)
        #expect(HanlinExpoNativeAPIManager.isAuthorized())
        HanlinExpoNativeAPIManager.revokeSession(sessionID: "autonomous-a")
        #expect(!HanlinExpoNativeAPIManager.isAuthorized())
    }

    @Test("Removing grant checks retains stale-runtime rejection across package replacement")
    func nativeAPIStaleRuntimeIsRejected() {
        let oldRuntime = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
        let newRuntime = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
        defer {
            HanlinExpoNativeAPIManager.revokeActiveSession()
            oldRuntime.deallocate()
            newRuntime.deallocate()
        }
        HanlinExpoNativeAPIManager.registerSession(sessionID: "autonomous-old", packageID: "fixture-old", isGranted: false, generation: 1)
        HanlinExpoNativeAPIManager.bindRuntime(oldRuntime, forSessionID: "autonomous-old")
        #expect(HanlinExpoNativeAPIManager.isAuthorized(forRuntime: oldRuntime))
        HanlinExpoNativeAPIManager.registerSession(sessionID: "autonomous-new", packageID: "fixture-new", isGranted: false, generation: 2)
        HanlinExpoNativeAPIManager.bindRuntime(newRuntime, forSessionID: "autonomous-new")
        #expect(!HanlinExpoNativeAPIManager.isAuthorized(forRuntime: oldRuntime))
        #expect(HanlinExpoNativeAPIManager.isAuthorized(forRuntime: newRuntime))
    }
}
