import Foundation
import CryptoKit
import HanlinExpoNativeAPI
import HanlinPlatformContracts
import Testing
@testable import AI_Hanlin

@MainActor
@Suite("Autonomous runtime policy and canonical Skill execution", .serialized)
struct HanlinAutonomousRuntimeTests {
    @Test("Embedded Node performs real TLS GET and POST through fetch and node:https")
    func embeddedNodeHTTPSRoundTrips() async throws {
        let result = try await AppRuntimeCore.shared.node.networkDiagnostics(rounds: 2)
        print("HANLIN_NODE_HTTPS_DIAGNOSTIC \(result.stdout) \(result.stderr)")
        #expect(result.exitCode == 0, "\(result.stderr)")
        let report = try #require(JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any])
        let requests = try #require(report["requests"] as? [[String: Any]])
        #expect(requests.count == 8)
        let supportsWebAssembly = try #require(report["webAssemblyAvailable"] as? Bool)
        #expect(report["fetchImplementation"] as? String == (supportsWebAssembly ? "node-undici" : "node-fetch@3.3.2+native-web-api"))
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
            assert sys.argv[1:] == ['\(nonce)', 'עברית'], repr(sys.argv)
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
            if (JSON.stringify(process.argv.slice(2)) !== JSON.stringify([nonce, 'עברית'])) throw new Error('Skill argv changed: ' + JSON.stringify(process.argv));
            const resourceDir = process.env.SKILL_RESOURCE_DIR;
            if (!resourceDir) throw new Error('Skill resource directory is missing');
            fs.writeFileSync(path.join(resourceDir, 'executed-' + nonce), 'actual-node-execution');
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

    @Test("Named Node fs and fs/promises imports resolve files in the execution workspace")
    func namedNodeFileAccessUsesWorkspace() async throws {
        let nonce = "עברית-" + UUID().uuidString.lowercased()
        let workspace = try RuntimeFileLayout.default.workspace(client: .tools, identifier: "named-fs-" + UUID().uuidString.lowercased())
        defer { try? FileManager.default.removeItem(at: workspace) }
        try nonce.write(to: workspace.appendingPathComponent("probe.txt"), atomically: true, encoding: .utf8)
        let source = """
        import fs, { readFileSync } from 'node:fs';
        import { readFile } from 'node:fs/promises';
        const values = [fs.readFileSync('probe.txt', 'utf8'), readFileSync('probe.txt', 'utf8'), await readFile('probe.txt', 'utf8')];
        console.log(JSON.stringify(values));
        export default values;
        """
        let result = try await AppRuntimeCore.shared.node.executeJavaScript(.init(source: source, workspace: workspace))
        #expect(result.exitCode == 0, "\(result.stderr)")
        let values = try #require(JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String])
        #expect(values == [nonce, nonce, nonce])
    }

    @Test("Native package setup executes real Node work without an internal approval record")
    func nativeLifecycleExecutesWithoutApproval() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let nonce = UUID().uuidString.lowercased()
        let script = "import fs from 'node:fs'; fs.writeFileSync(new URL('./setup-result', import.meta.url), process.argv[2]);"
        try script.write(to: root.appendingPathComponent("setup.mjs"), atomically: true, encoding: .utf8)
        let plan = LifecycleExecutionPlan(
            packageName: "autonomous-setup-\(nonce)", packageVersion: "1.0.0",
            integrity: "sha512-" + Data(SHA512.hash(data: Data(script.utf8))).base64EncodedString(),
            scriptHash: SHA256.hash(data: Data(script.utf8)).map { String(format: "%02x", $0) }.joined(),
            actions: [.init(script: "postinstall", kind: "node", command: nil, arguments: ["setup.mjs", nonce])],
            rejected: [], requiresApproval: true, executable: true
        )
        let broker = AppRuntimeCore.shared.lifecycle
        let approvedBefore = try await broker.isApproved(plan)
        #expect(!approvedBefore)
        try await broker.execute(plan, packageRoot: root)
        #expect(try String(contentsOf: root.appendingPathComponent("setup-result"), encoding: .utf8) == nonce)
        let approvedAfter = try await broker.isApproved(plan)
        #expect(!approvedAfter, "Execution must not invent a persisted human approval")
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
