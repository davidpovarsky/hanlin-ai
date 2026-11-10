import CryptoKit
import SwiftData
import Testing
@testable import AI_Hanlin

@MainActor
@Suite("Runtime autonomy V3 persistence", .serialized)
struct RuntimeAutonomyV3Tests {
    @Test func linkedPythonExtensionCatalogReadsDoNotStartOrChangeTheOriginalService() async throws {
        let core = AppRuntimeCore.shared
        let before = await core.python.snapshot()
        let catalog = try PythonNativeExtensions.snapshot()
        let linked = try #require(catalog.first { $0.module == "_hanlin_native" })
        #expect(linked.distribution == "hanlin-native" && linked.version == "1.0.0")
        #expect(linked.pythonMajor == 3 && linked.pythonMinor == 14)
        #expect(!linked.initializationObserved || linked.registeredInittab)
        let result = await GetRuntimeCapabilitiesTool().execute(argumentsJSON: #"{"runtime":"python"}"#,
            context: NativeToolExecutionContext(localeIdentifier: "en"))
        #expect(result.outcome == .succeeded)
        #expect(result.modelText.contains(linked.module) && result.modelText.contains("registeredInittab"))
        let after = await core.python.snapshot()
        #expect(after.state == before.state && after.version == before.version)
    }

    @Test(.timeLimit(.minutes(2)))
    func actualNodeAndOriginalJavaScriptCoreCoexistWithTheVerifiedLaunchMode() async throws {
        let core = AppRuntimeCore.shared
        let workspace = try RuntimeFileLayout.default.workspace(client: .tools, identifier: "native-engine-coexist-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: workspace) }
        let first = try await core.javaScriptCore.execute(RuntimeExecutionRequest(
            source: "console.log('actual original JavaScriptCore before Node'); 17;", workspace: workspace))
        #expect(first.exitCode == 0 && first.stdout.contains("JavaScriptCore before Node"))
        let node = try await core.node.executeJavaScript(RuntimeExecutionRequest(source: """
            console.log('actual Node alongside JavaScriptCore');
            export default {
                jitless:process.execArgv.includes('--jitless'),
                wasmJitless:process.execArgv.includes('--wasm-jitless'),
                pointerCompression:Number(process.config.variables.v8_enable_pointer_compression)===1,
                sharedCage:Number(process.config.variables.v8_enable_pointer_compression_shared_cage)===1
            };
            """, workspace: workspace), moduleKind: "esm")
        #expect(node.exitCode == 0)
        guard case .object(let mode) = node.value else { Issue.record("Actual Node mode receipt missing"); return }
        for key in ["jitless", "wasmJitless", "pointerCompression", "sharedCage"] {
            #expect(mode[key] == .boolean(true), "Actual embedded launch mode mismatch: \(key)")
        }
        let after = try await core.javaScriptCore.execute(RuntimeExecutionRequest(
            source: "console.log('actual original JavaScriptCore after Node'); 19;", workspace: workspace))
        #expect(after.exitCode == 0 && after.stdout.contains("JavaScriptCore after Node"))
    }

    @Test(.timeLimit(.minutes(2)))
    func stoppingAnActualCompilerJobNeverLaunchesItsCompiledSource() async throws {
        let core = AppRuntimeCore.shared
        let service = TypeScriptRuntimeService(node: core.node)
        _ = try await core.ensureStarted(.node)
        let workspace = try RuntimeFileLayout.default.workspace(client: .tools, identifier: "typescript-compiler-stop-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: workspace) }
        let request = RuntimeExecutionRequest(source: "", workspace: workspace)
        let source = "/*" + String(repeating: "actual compiler source ", count: 600_000)
            + "*/\nconsole.log('compiled source must never launch'); export default 17;"
        var compilerID: UUID?
        let reporter: RuntimeJobProgress.Reporter = { record in
            guard record.state == .running, compilerID == nil else { return }
            compilerID = record.executionID
            _ = await service.stop()
        }
        do {
            _ = try await RuntimeJobProgress.$reporter.withValue(reporter) {
                try await service.compileAndExecute(source: source, request: request)
            }
            Issue.record("Stopped compiler incorrectly returned a compiled execution")
        } catch is CancellationError {
            let id = try #require(compilerID, "The actual compiler job must have entered running state")
            #expect(try await core.node.existingExecution(id: id)?.state == .cancelled)
            #expect(try await core.jobs.snapshot(id: request.id, kind: .node) == nil)
            #expect(await service.snapshot().state == .stopped)
        }
    }

    @Test(.timeLimit(.minutes(4)))
    func actualTypeScriptCompilerUsesLargeDurableInputAndRetrievableFullOutput() async throws {
        let core = AppRuntimeCore.shared
        let service = TypeScriptRuntimeService(node: core.node)
        let comment = String(repeating: "שלום🙂 ", count: 1_100_000)
        let source = "/*\(comment)*/\nexport const retainedCompilerValue: number = 17;"
        #expect(source.utf8.count > 10 * 1024 * 1024)
        let compiled = try await service.compile(source: source, fileName: "מקור.ts", tsconfig: [
            "compilerOptions": .object(["types": .array([]), "skipLibCheck": .boolean(true)])
        ])
        #expect(compiled.succeeded && compiled.javaScript?.contains("retainedCompilerValue") == true)
        let id = try #require(compiled.executionID)
        let journal = try #require(try await core.node.existingExecution(id: id))
        #expect(journal.state == .completed && journal.inputArtifact?.verified == true)
        #expect((journal.inputArtifact?.bytes ?? 0) > 10 * 1024 * 1024)
        let artifact = try #require(journal.result?.outputFiles?["stdout"])
        let bytes = try Data(contentsOf: URL(filePath: artifact.path))
        #expect(bytes.count > 10 * 1024 * 1024 && Int64(bytes.count) == artifact.bytes)
        #expect(SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() == artifact.sha256)
        let reopened = try JSONDecoder().decode(TypeScriptCompilationResult.self, from: bytes)
        #expect(reopened.executionID == id && reopened.sourceMap == compiled.sourceMap)
        #expect(reopened.javaScript == compiled.javaScript && reopened.compilerVersion == compiled.compilerVersion)
    }

    @Test(.timeLimit(.minutes(2)))
    func stoppingTypeScriptCancelsItsActualWorkerAndPreservesTheReceipt() async throws {
        let core = AppRuntimeCore.shared
        _ = try await core.ensureStarted(.node)
        let service = TypeScriptRuntimeService(node: core.node)
        _ = try await service.healthCheck()
        let workspace = try RuntimeFileLayout.default.workspace(client: .tools, identifier: "typescript-stop-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: workspace) }
        let request = RuntimeExecutionRequest(source: "", workspace: workspace)
        let task = Task {
            try await service.compileAndExecute(
                source: "console.log('actual TypeScript worker entered'); export default new Promise(resolve => setTimeout(() => resolve(17), 30000));",
                request: request
            )
        }
        defer { task.cancel() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        var entered = false
        while ContinuousClock.now < deadline {
            if let record = try await core.jobs.refresh(id: request.id, kind: .node), record.stdoutBytes > 0 { entered = true; break }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(entered, "The actual compiled TypeScript worker did not produce entry bytes")
        _ = await service.stop()
        let receipt = try #require(try await task.value.execution)
        #expect(receipt.wasCancelled && (receipt.outputFiles?["stdout"]?.bytes ?? 0) > 0)
        #expect(try await core.jobs.snapshot(id: request.id, kind: .node)?.state == .cancelled)
        #expect(await service.snapshot().state == .stopped)
    }

    @Test(.timeLimit(.minutes(2)))
    func typeScriptReportsTheActualCompilerAndItsOwnStoppedState() async throws {
        let core = AppRuntimeCore.shared
        _ = try await core.ensureStarted(.node)
        let service = TypeScriptRuntimeService(node: core.node)
        let health = try await service.healthCheck()
        let compiled = try await service.compile(source: "export const actualCompiler: number = 17;")
        let version = try #require(compiled.compilerVersion)
        #expect(!version.isEmpty && health.version == version && health.state == .ready)
        _ = await service.stop()
        let stopped = await service.snapshot()
        let node = await core.node.snapshot()
        #expect(stopped.state == .stopped && stopped.version == version)
        #expect(node.state == .ready || node.state == .executing)
        let restarted = try await service.healthCheck()
        #expect(restarted.state == .ready && restarted.version == version)
    }

    @Test(.timeLimit(.minutes(2)))
    func explicitNativeCommandModuleUsesActualPythonAndLinkedBsdWithFullArtifacts() async throws {
        let core = AppRuntimeCore.shared
        let workspace = try RuntimeFileLayout.default.workspace(client: .tools, identifier: "native-command-api-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: workspace) }
        let payload = Data(String(repeating: "שלום🙂\n", count: 900_000).utf8)
        #expect(payload.count > 10 * 1024 * 1024)
        try payload.write(to: workspace.appending(path: "input.bin"))
        try Data("import sys\nsys.stdout.buffer.write(sys.stdin.buffer.read())\nsys.stderr.write('actual Python CLI stderr')\nsys.exit(23)\n".utf8)
            .write(to: workspace.appending(path: "actual-copy.py"))
        let source = """
        import {runCommand,openOutput,capabilities} from 'hanlin:runtime';
        import {createHash} from 'node:crypto';
        const python=await runCommand('python3',['actual-copy.py'],{stdinFile:'input.bin'});
        if(python.exitCode!==23||!python.executionID)throw Error('The actual Python result was not retained');
        const bsd=await runCommand('cat',[python.stdoutPath]);
        if(bsd.exitCode!==0||!bsd.executionID)throw Error('The actual linked BSD command failed');
        const hash=createHash('sha256');let bytes=0;
        for await(const chunk of openOutput(bsd)){hash.update(chunk);bytes+=chunk.length;}
        export default {bytes,sha256:hash.digest('hex'),pythonID:python.executionID,bsdID:bsd.executionID,pid:capabilities().pid};
        """
        let result = try await core.node.executeJavaScript(.init(source: source, workspace: workspace, limits: .init(timeout: .seconds(80))), moduleKind: "esm")
        #expect(result.exitCode == 0, "\(result.stderr)")
        guard case .object(let value)? = result.value else {
            throw RuntimeCoreError.runtimeFailure("The actual adapter returned no result object: \(result.stderr)")
        }
        #expect(value["bytes"] == .number(Double(payload.count)))
        let digest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        #expect(value["sha256"] == .string(digest))
        #expect(value["pid"] == .boolean(false))
        for field in ["pythonID", "bsdID"] {
            guard case .string(let text)? = value[field], let actualID = UUID(uuidString: text) else {
                throw RuntimeCoreError.runtimeFailure("The actual adapter returned no native job ID for \(field)")
            }
            let saved = try await core.jobs.snapshot(id: actualID, kind: field == "pythonID" ? .localPython : .shell)
            #expect(saved?.stdoutBytes == payload.count)
        }
    }

    @Test func hostOutputPageQueriesPreserveParametersAndTheAuthenticatedOrigin() throws {
        let host = RuntimeHostConnection(baseURL: URL(string: "http://127.0.0.1:8123")!, token: "fixture-token")
        let request = host.request(path: "/v1/executions/fixture/output?channel=stdout&offset=4093&limit=1024")
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.path == "/v1/executions/fixture/output")
        #expect(components.queryItems?.first(where: { $0.name == "offset" })?.value == "4093")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token")
        let absolute = host.request(path: "https://example.com/route?offset=1")
        #expect(absolute.url?.host == "127.0.0.1" && absolute.url?.port == 8123)
    }

    @Test func sourceImportsUseTheActualWorkspaceAndNativePackageExportConditions() async throws {
        let workspace = try RuntimeFileLayout.default.workspace(client: .tools, identifier: "workspace-import-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: workspace) }
        let package = workspace.appending(path: "node_modules/hanlin-local-fixture", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try Data(#"{"name":"hanlin-local-fixture","version":"2.0.0","exports":{"import":"./import.mjs","require":"./require.cjs"}}"#.utf8).write(to: package.appending(path: "package.json"))
        try Data("export default 'local-esm';".utf8).write(to: package.appending(path: "import.mjs"))
        try Data("module.exports='local-cjs';".utf8).write(to: package.appending(path: "require.cjs"))
        try Data("export default 'שלום sibling';".utf8).write(to: workspace.appending(path: "sibling.mjs"))
        for (kind, source) in [
            ("esm", "import local from 'hanlin-local-fixture'; import sibling from './sibling.mjs'; console.log(local,sibling); export default local;"),
            ("commonjs", "console.log(require('hanlin-local-fixture')); module.exports=require('hanlin-local-fixture');")
        ] {
            let result = try await AppRuntimeCore.shared.node.executeJavaScript(RuntimeExecutionRequest(source: source, workspace: workspace), moduleKind: kind)
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout.contains(kind == "esm" ? "local-esm שלום sibling" : "local-cjs"))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func verifiedLifecycleSourceRunsThroughTheActualSharedEnginesAndRejectsStalePlans() async throws {
        let core = AppRuntimeCore.shared
        let workspace = try RuntimeFileLayout.default.workspace(client: .tools, identifier: "lifecycle-v2-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: workspace) }
        let manifest: [String: Any] = ["name": "hanlin-lifecycle-fixture", "version": "1.2.3", "scripts": [
            "preinstall": "echo pre > order.txt",
            "install": "VALUE='שלום world' python3 build.py && cat built.txt >> order.txt",
            "postinstall": "node verify.cjs",
            "prepare": "echo prepared >> order.txt"
        ]]
        let manifestURL = workspace.appending(path: "package.json")
        try JSONSerialization.data(withJSONObject: manifest).write(to: manifestURL)
        try Data("""
        import os, pathlib
        assert os.environ['VALUE'] == 'שלום world'
        assert os.environ['npm_lifecycle_event'] == 'install'
        assert os.environ['npm_command'] == 'install'
        assert os.environ['npm_package_name'] == 'hanlin-lifecycle-fixture'
        pathlib.Path('built.txt').write_text('built\\n', encoding='utf8')
        """.utf8).write(to: workspace.appending(path: "build.py"))
        try Data("""
        const fs=require('node:fs');
        if(require.main!==module || fs.readFileSync('order.txt','utf8')!=='pre\\nbuilt\\n')throw Error('lifecycle ordering');
        fs.appendFileSync('order.txt','post\\n');
        """.utf8).write(to: workspace.appending(path: "verify.cjs"))
        let plan = try await core.node.packageLifecyclePlan(workspace: workspace)
        #expect(plan.schemaVersion == 2 && !plan.requiresApproval && plan.executable)
        #expect(plan.actions.map(\.script) == ["preinstall", "install", "postinstall", "prepare"])
        try await core.lifecycle.execute(plan, packageRoot: workspace)
        #expect(try String(contentsOf: workspace.appending(path: "order.txt"), encoding: .utf8) == "pre\nbuilt\npost\nprepared\n")
        var changed = manifest
        changed["scripts"] = ["preinstall": "echo must-not-run > forbidden.txt"]
        try JSONSerialization.data(withJSONObject: changed).write(to: manifestURL)
        do {
            try await core.lifecycle.execute(plan, packageRoot: workspace)
            Issue.record("A stale lifecycle plan was executed")
        } catch { }
        #expect(!FileManager.default.fileExists(atPath: workspace.appending(path: "forbidden.txt").path))
    }

    @Test(.timeLimit(.minutes(2)))
    func mcpInstallationIsADurableJobAndRunsNativeHooksBeforeTheRealProtocolProbe() async throws {
        let core = AppRuntimeCore.shared
        let workspace = try RuntimeFileLayout.default.workspace(client: .tools, identifier: "mcp-hook-proof-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: workspace) }
        let package = workspace.appending(path: "package", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        let manifest: [String: Any] = ["name": "hanlin-native-mcp-hooks", "version": "1.0.0", "type": "module", "bin": ["fixture": "server.mjs"], "scripts": [
            "install": "VALUE='שלום world' python3 build.py && node verify.cjs",
            "prepare": "false"
        ]]
        try JSONSerialization.data(withJSONObject: manifest).write(to: package.appending(path: "package.json"))
        try Data("""
        import os, pathlib
        assert os.environ['VALUE'] == 'שלום world'
        assert os.environ['npm_lifecycle_event'] == 'install'
        pathlib.Path('marker.txt').write_text('READY', encoding='utf8')
        """.utf8).write(to: package.appending(path: "build.py"))
        try Data("if(require('node:fs').readFileSync('marker.txt','utf8')!=='READY')throw Error('hook ordering');".utf8).write(to: package.appending(path: "verify.cjs"))
        try Data("""
        import {readFileSync} from 'node:fs'; import {createInterface} from 'node:readline';
        if(readFileSync(new URL('./marker.txt',import.meta.url),'utf8')!=='READY')throw Error('missing lifecycle output');
        if(process.argv.slice(2).length!==257 || process.argv.at(-1)!=='שלום\\nargument')throw Error('argv transport');
        createInterface({input:process.stdin}).on('line',line=>{
          const request=JSON.parse(line);let result;
          if(request.method==='initialize')result={protocolVersion:request.params.protocolVersion,capabilities:{tools:{}},serverInfo:{name:'hooks',version:'1.0.0'}};
          if(request.method==='tools/list')result={tools:[{name:'fixture',description:'Native hooks',inputSchema:{type:'object'}}]};
          if(result)process.stdout.write(JSON.stringify({jsonrpc:'2.0',id:request.id,result})+'\\n');
        });
        """.utf8).write(to: package.appending(path: "server.mjs"))
        let archive = workspace.appending(path: "fixture.tgz")
        let tar = try await core.shell.execute(tokens: ["tar", "-czf", archive.path, "-C", workspace.path, "package"], workspace: workspace, environment: [:], allowNetwork: false)
        #expect(tar.exitCode == 0, "\(tar.stderr)")
        let operationID = UUID(), serverID = UUID()
        do {
            let descriptor = try await core.node.installMCPPackage(spec: MCPPackageSpec(localArchive: archive), operationID: operationID,
                serverID: serverID, entryPointOverride: nil, arguments: (0..<256).map { "argument-\($0)" } + ["שלום\nargument"])
            #expect(descriptor.compatibility.runtimeProbePassed)
            let observedJob = try await core.node.existingExecution(id: operationID)
            let job = try #require(observedJob)
            #expect(job.state == .completed && job.result?.exitCode == 0)
            let artifact = try #require(job.result?.outputFiles?["stdout"])
            #expect(artifact.bytes > 0)
            let data = try Data(contentsOf: URL(fileURLWithPath: artifact.path))
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            #expect(digest == artifact.sha256)
            #expect(String(decoding: data, as: UTF8.self).contains("installingDependencies"))
            try await core.node.rollbackMCPInstall(operationID: operationID, serverID: serverID)
        } catch {
            try? await core.node.cancelMCPInstall(operationID: operationID)
            try? await core.node.rollbackMCPInstall(operationID: operationID, serverID: serverID)
            throw error
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func actualGlobalNpmInstallUpdateImportAndRemovalUsePreservedGenerations() async throws {
        let core = AppRuntimeCore.shared
        let previous = try await core.nodePackages.installed().first { $0.name == "is-number" }
        let workspace = try RuntimeFileLayout.default.workspace(client: .tools, identifier: "npm-generation-proof-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: workspace) }
        do {
            let first = try await core.nodePackages.install(name: "is-number", version: "7.0.0")
            let firstRoot = try #require(first.packageRoot)
            let source = """
            import isNumber from 'is-number';import {fileURLToPath} from 'node:url';
            if(!isNumber('42') || isNumber('not a number'))throw Error('actual package behavior');
            console.log(fileURLToPath(import.meta.resolve('is-number')));export default true;
            """
            let imported = try await core.node.executeJavaScript(RuntimeExecutionRequest(source: source, workspace: workspace), moduleKind: "esm")
            #expect(imported.exitCode == 0 && imported.value == .boolean(true), "\(imported.stderr)")
            #expect(imported.stdout.contains(firstRoot))
            let second = try await core.nodePackages.install(name: "is-number", version: "6.0.0")
            let secondRoot = try #require(second.packageRoot)
            #expect(secondRoot != firstRoot)
            #expect(FileManager.default.fileExists(atPath: firstRoot + "/package.json"))
            let updated = try await core.node.executeJavaScript(RuntimeExecutionRequest(source: source, workspace: workspace), moduleKind: "esm")
            #expect(updated.exitCode == 0 && updated.stdout.contains(secondRoot), "\(updated.stderr)")
            try await core.nodePackages.uninstall(name: "is-number")
            let remaining = try await core.nodePackages.installed()
            #expect(!remaining.contains { $0.name == "is-number" })
            let removed = try await core.node.executeJavaScript(RuntimeExecutionRequest(source: source, workspace: workspace), moduleKind: "esm")
            #expect(removed.exitCode != 0 && removed.stderr.contains("is-number"))
            if let previous { _ = try await core.nodePackages.install(name: previous.name, version: previous.version) }
        } catch {
            if let previous { _ = try? await core.nodePackages.install(name: previous.name, version: previous.version) }
            else { try? await core.nodePackages.uninstall(name: "is-number") }
            throw error
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func actualCommandOnlyNpmValidationDoesNotRunTheCommandUntilInvoked() async throws {
        let core = AppRuntimeCore.shared
        let workspace = try RuntimeFileLayout.default.workspace(client: .tools, identifier: "npm-bin-proof-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: workspace) }
        let root = workspace.appending(path: "node_modules/hanlin-command-only", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(#"{"name":"hanlin-command-only","version":"1.0.0","bin":{"actual":"bin.cjs"}}"#.utf8)
            .write(to: root.appending(path: "package.json"))
        let entry = root.appending(path: "bin.cjs")
        try Data("""
            require('node:fs').writeFileSync('actual-cli-invocation',process.argv[2]);
            console.log('actual command שלום');process.exit(23);
            """.utf8).write(to: entry)
        let receipt = try await core.node.validatePackage(name: "hanlin-command-only", packageRoot: root, workspace: root)
        #expect(NodePackageManager.validationStatus(receipt) == "commandFilesVerified", "\(receipt.stderr)")
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "actual-cli-invocation").path))
        let invoked = try await core.node.executeCLI(entryPoint: entry, arguments: ["actual-argument"], workspace: root)
        #expect(invoked.exitCode == 23 && invoked.stdout.contains("actual command שלום"))
        #expect(try String(contentsOf: root.appending(path: "actual-cli-invocation"), encoding: .utf8) == "actual-argument")
    }

    @Test(.timeLimit(.minutes(2)))
    func actualNodeFileInputExceedsTheHTTPFrameWithoutTruncationOrReplay() async throws {
        let workspace = try RuntimeFileLayout.default.workspace(client: .tools, identifier: "native-file-input-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: workspace) }
        let id = UUID(), nonce = UUID().uuidString
        let literal = String(decoding: try JSONEncoder().encode(nonce), as: UTF8.self)
        let source = "/*" + String(repeating: "שלום 👨‍👩‍👧‍👦 ", count: 1_000_000) + """
            */
            console.log(\(literal));
            export default {nonce: \(literal), argument:process.argv[2]};
            """
        #expect(source.utf8.count > 32 * 1_024 * 1_024)
        let result = try await AppRuntimeCore.shared.node.executeJavaScript(RuntimeExecutionRequest(id: id,
            source: source, arguments: ["actual argument שלום"], workspace: workspace), moduleKind: "esm")
        #expect(result.exitCode == 0, "\(result.stderr)")
        guard case .object(let value) = result.value else { Issue.record("Missing actual large-input result"); return }
        #expect(value["nonce"] == .string(nonce) && value["argument"] == .string("actual argument שלום"))
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == nonce)
        let journalRoot = RuntimeFileLayout.default.root.appending(path: "jobs/node/\(id.uuidString.lowercased())")
        let saved = try Data(contentsOf: journalRoot.appending(path: "request.json"))
        let request = try #require(try JSONSerialization.jsonObject(with: saved) as? [String: Any])
        #expect(request["source"] as? String == source)
        let journal = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: journalRoot.appending(path: "job.json"))) as? [String: Any])
        let receipt = try #require(journal["inputArtifact"] as? [String: Any])
        #expect(receipt["bytes"] as? Int == saved.count)
        #expect(receipt["sha256"] as? String == SHA256.hash(data: saved).map { String(format: "%02x", $0) }.joined())
        let typed = try #require(try await AppRuntimeCore.shared.node.existingExecution(id: id))
        #expect(typed.inputArtifact?.verified == true && typed.inputArtifact?.bytes == Int64(saved.count))
        #expect(typed.inputArtifact?.sha256 == receipt["sha256"] as? String)
        #expect(!FileManager.default.fileExists(atPath: RuntimeFileLayout.default.nodeRuntime.appending(path: "requests/\(id.uuidString.lowercased()).json").path))
    }

    @Test(.timeLimit(.minutes(2)))
    func actualOptionalLifecycleFailureKeepsRequiredNativeBuildsAndFailedJobEvidence() async throws {
        let core = AppRuntimeCore.shared
        _ = try await core.node.ensureRunning()
        let id = UUID().uuidString.lowercased()
        // An isolated private transaction. No copy or publication of the real
        // npm registry and no second runtime. Its base cannot be committed.
        let root = try RuntimeFileLayout.default.workspace(client: .tools, identifier: "npm-lifecycle-\(id)")
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest: [String: Any] = ["name": "native-optional-proof", "version": "1.0.0",
            "dependencies": ["required": "1.0.0"], "optionalDependencies": ["optional-bad": "1.0.0"]]
        try JSONSerialization.data(withJSONObject: manifest).write(to: root.appending(path: "package.json"))
        var packages: [String: Any] = ["": manifest]
        for (name, script) in [("required", "python3 build.py"), ("optional-bad", "node phase.cjs")] {
            let directory = root.appending(path: "node_modules/\(name)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let package: [String: Any] = ["name": name, "version": "1.0.0", "scripts": ["install": script]]
            try JSONSerialization.data(withJSONObject: package).write(to: directory.appending(path: "package.json"))
            packages["node_modules/\(name)"] = package
        }
        try Data("console.log('actual optional native output');process.exit(23);".utf8)
            .write(to: root.appending(path: "node_modules/optional-bad/phase.cjs"))
        try Data("from pathlib import Path; Path('built.txt').write_text('required native build שלום', encoding='utf-8')".utf8)
            .write(to: root.appending(path: "node_modules/required/build.py"))
        try JSONSerialization.data(withJSONObject: ["lockfileVersion": 3, "packages": packages])
            .write(to: root.appending(path: "package-lock.json"))
        let archive = try #require(Bundle.main.url(forResource: "RuntimeHostResources", withExtension: "zip"))
        let digest = SHA256.hash(data: try Data(contentsOf: archive)).map { String(format: "%02x", $0) }.joined()
        let host = RuntimeFileLayout.default.nodeRuntime.appending(path: "host-\(digest)", directoryHint: .isDirectory)
        let literal: (String) throws -> String = { String(decoding: try JSONEncoder().encode($0), as: UTF8.self) }
        let setup = try await core.node.executeJavaScript(RuntimeExecutionRequest(source: """
            import {createRequire} from 'node:module';
            import {planLifecycleTree} from \(try literal(host.appending(path: "lifecycle-planner.mjs").absoluteString));
            const Arborist=createRequire(\(try literal(host.appending(path: "package.json").path)))('@npmcli/arborist');
            const tree=await new Arborist({path:process.cwd(),ignoreScripts:true}).loadActual();
            export default await planLifecycleTree(tree);
            """, workspace: root), moduleKind: "esm")
        #expect(setup.exitCode == 0, "\(setup.stderr)")
        let planValue = try #require(setup.value)
        let planData = try JSONEncoder().encode(planValue)
        let plan = try JSONDecoder().decode(LifecycleExecutionPlan.self, from: planData)
        #expect(plan.actions.first { $0.packageName == "optional-bad" }?.optional == true)
        try JSONSerialization.data(withJSONObject: ["transactionID": id, "directory": root.path,
            "baseRevision": "non-publishable-native-fixture", "plan": try JSONSerialization.jsonObject(with: planData)])
            .write(to: root.appending(path: ".hanlin-package-transaction.json"))
        try await core.lifecycle.execute(plan, packageRoot: root)
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "node_modules/optional-bad").path))
        #expect(try String(contentsOf: root.appending(path: "node_modules/required/built.txt"), encoding: .utf8) == "required native build שלום")
        let receipt = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: root.appending(path: ".hanlin-optional-build-failures.json"))) as? [String: Any])
        let failures = try #require(receipt["failures"] as? [[String: Any]])
        let failedID = try #require(failures.first?["executionID"] as? String)
        let failedUUID = try #require(UUID(uuidString: failedID))
        let saved = try await core.node.existingExecution(id: failedUUID)
        let journal = try #require(saved)
        #expect(journal.state == .failed && journal.result?.exitCode == 23)
        #expect(journal.result?.stdout.contains("actual optional native output") == true)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellingQueuedPythonNeverExecutesItsSourceAfterTheRunningJobFinishes() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "python-queue-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = RuntimeFileLayout(root: root)
        let jobs = RuntimeJobStore(fileLayout: layout)
        let python = PythonRuntimeService(fileLayout: layout, jobs: jobs)
        let workspace = try layout.workspace(client: .tools, identifier: "queue-proof")
        let started = workspace.appending(path: "first-started")
        let release = workspace.appending(path: "release")
        let forbidden = workspace.appending(path: "must-not-run")
        // This fixture watchdog only prevents a broken test from leaving native
        // execution blocked. Production requests still have no default deadline.
        let firstRequest = RuntimeExecutionRequest(source: """
        import pathlib, time
        pathlib.Path('first-started').touch()
        end = time.monotonic() + 20
        while not pathlib.Path('release').exists() and time.monotonic() < end:
            time.sleep(0.01)
        """, workspace: workspace)
        let first = Task { try await python.execute(firstRequest) }
        defer { try? Data().write(to: release); first.cancel() }
        let firstDeadline = ContinuousClock.now + .seconds(5)
        while !FileManager.default.fileExists(atPath: started.path), ContinuousClock.now < firstDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(FileManager.default.fileExists(atPath: started.path))
        let secondRequest = RuntimeExecutionRequest(source: "from pathlib import Path; Path('must-not-run').touch()", workspace: workspace)
        let second = Task { try await python.execute(secondRequest) }
        let queuedDeadline = ContinuousClock.now + .seconds(5)
        while try await jobs.snapshot(id: secondRequest.id, kind: .localPython) == nil, ContinuousClock.now < queuedDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        second.cancel()
        do { _ = try await second.value; Issue.record("Queued Python returned success after cancellation") }
        catch is CancellationError { }
        let cancelled = try await jobs.snapshot(id: secondRequest.id, kind: .localPython)
        #expect(cancelled?.state == .cancelled && cancelled?.cancellationRequested == true)
        #expect(try await jobs.snapshot(id: firstRequest.id, kind: .localPython)?.state == .running)
        #expect(!FileManager.default.fileExists(atPath: forbidden.path))
        let empty = try await jobs.output(id: secondRequest.id, kind: .localPython, channel: "stdout", offset: 0, limit: 1024)
        #expect(empty["totalBytes"] == "0" && empty["base64"] == "")
        try Data().write(to: release)
        #expect(try await first.value.exitCode == 0)
        // The queue has advanced; a fresh job proves the cancelled work item was skipped.
        let third = try await python.execute(RuntimeExecutionRequest(source: "print('queue-drained')", workspace: workspace))
        #expect(third.exitCode == 0 && third.stdout.contains("queue-drained"))
        #expect(!FileManager.default.fileExists(atPath: forbidden.path))
    }

    @Test func nodeCLIUsesActualMainModuleAndRetainsItsInputAndDelayedOutput() async throws {
        let workspace = try RuntimeFileLayout.default.workspace(client: .tools, identifier: "cli-proof-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: workspace) }
        let entry = workspace.appending(path: "main.cjs")
        let input = workspace.appending(path: "input.txt")
        try Data("שלום CLI\n".utf8).write(to: input)
        try Data("""
        const assert = require('node:assert/strict');
        assert.equal(require.main, module);
        assert.deepEqual(process.argv.slice(2), ['argument with spaces', 'עברית']);
        assert.equal(process.env.CLI_PROOF, 'isolated');
        const chunks=[];
        process.stdin.on('data', chunk=>chunks.push(chunk));
        process.stdin.on('end', ()=>{
          process.stdout.write(Buffer.concat(chunks));
          setTimeout(()=>console.error('CLI_DELAYED_STDERR'),30);
        });
        """.utf8).write(to: entry)
        let result = try await AppRuntimeCore.shared.node.executeCLI(entryPoint: entry,
            arguments: ["argument with spaces", "עברית"], workspace: workspace,
            environment: ["CLI_PROOF": "isolated"], standardInput: input)
        #expect(result.exitCode == 0 && result.stdout == "שלום CLI\n")
        #expect(result.stderr.contains("CLI_DELAYED_STDERR"))
        #expect(!result.didTimeOut && !result.wasCancelled)
    }

    @Test func pythonCLIUsesActualFileArgumentsInputAndStandardExitStatus() async throws {
        let workspace = try RuntimeFileLayout.default.workspace(client: .tools, identifier: "python-cli-proof-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: workspace) }
        let entry = workspace.appending(path: "main.py")
        let input = workspace.appending(path: "input.txt")
        try Data("שלום Python CLI\n".utf8).write(to: input)
        try Data("""
        import sys, pathlib, os
        assert __name__ == '__main__'
        assert pathlib.Path(__file__).name == 'main.py'
        assert sys.argv[0] == __file__
        assert sys.argv[1:] == ['argument with spaces', 'עברית']
        assert os.environ['CLI_PROOF'] == 'isolated'
        sys.stdout.buffer.write(sys.stdin.buffer.read())
        sys.exit(23)
        """.utf8).write(to: entry)
        let result = try await AppRuntimeCore.shared.python.executeCLI(entryPoint: entry,
            arguments: ["argument with spaces", "עברית"], workspace: workspace,
            environment: ["CLI_PROOF": "isolated"], standardInput: input)
        #expect(result.exitCode == 23 && result.stdout == "שלום Python CLI\n")
        #expect(result.stderr.isEmpty && !result.didTimeOut && !result.wasCancelled)
    }

    @Test func savedEnvironmentPrecedenceFollowsScopesAndPreservesUserPaths() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "environment-proof-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = RuntimeFileLayout(root: root)
        let environment = RuntimeEnvironmentStore(fileLayout: layout)
        let id = UUID()
        // Save the narrower scope first to prove ordering is independent of UI edits.
        _ = try await environment.save(name: "PATH", value: "/python/bin", scope: .python, isEnabled: true, isSecret: false)
        _ = try await environment.save(name: "PATH", value: "/shared/bin", scope: .shared, isEnabled: true, isSecret: false)
        _ = try await environment.save(name: "HOME", value: "/user-home", scope: .shared, isEnabled: true, isSecret: false)
        _ = try await environment.save(name: "PATH", value: "/execution/bin", scope: .execution(id), isEnabled: true, isSecret: false)
        _ = try await environment.save(name: "שם-משתנה", value: "ערך", scope: .shared, isEnabled: true, isSecret: false)
        let perEngine = try await environment.resolved(scopes: [.shared, .python])
        #expect(perEngine["PATH"] == "/python/bin" && perEngine["HOME"] == "/user-home")
        let perJob = try await environment.resolved(scopes: [.shared, .python, .execution(id)])
        #expect(perJob["PATH"] == "/execution/bin")
        let explicit = try await environment.resolved(scopes: [.shared, .python, .execution(id)], overrides: ["PATH": "/explicit/bin"])
        #expect(explicit["PATH"] == "/explicit/bin")
        let reopened = RuntimeEnvironmentStore(fileLayout: layout)
        #expect(try await reopened.resolved(scopes: [.shared, .python]) == perEngine)
        let workspace = try layout.workspace(client: .tools, identifier: "environment")
        let python = PythonRuntimeService(fileLayout: layout, environment: reopened)
        let result = try await python.execute(RuntimeExecutionRequest(source: "import os; print(os.environ['PATH']); print(os.environ['HOME']); print(os.environ['שם-משתנה'])", workspace: workspace))
        #expect(result.exitCode == 0 && result.stdout == "/python/bin\n/user-home\nערך\n")
        do {
            _ = try await environment.save(name: "BAD_VALUE", value: "before\0after", scope: .shared, isEnabled: true, isSecret: false)
            Issue.record("An unrepresentable OS environment value was accepted")
        } catch { }
    }

    @Test(.timeLimit(.minutes(1)))
    func portableShellDispatchesActualPythonNodeAndNativeBSDPipelineWithFullStreams() async throws {
        let workspace = try RuntimeFileLayout.default.workspace(client: .tools, identifier: "mixed-command-proof-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: workspace) }
        try Data("""
        import sys, os
        assert sys.argv[0].endswith('transform.py')
        assert sys.argv[1:] == ['argument with spaces', 'עברית']
        assert os.environ['COMMAND_NAME'] == 'world'
        sys.stdout.write(sys.stdin.read().replace('שלום', 'hello') + os.environ['COMMAND_NAME'] + '\\n')
        """.utf8).write(to: workspace.appending(path: "transform.py"))
        try Data("""
        const assert = require('node:assert/strict');
        assert.equal(require.main, module);
        assert.equal(require('node:fs').readFileSync('result.txt','utf8'), 'hello\\nworld\\n');
        console.log('ACTUAL_MIXED_COMMAND_PIPELINE_PASSED');
        """.utf8).write(to: workspace.appending(path: "verify.cjs"))
        let result = try await AppRuntimeCore.shared.node.executePortableShell(RuntimeExecutionRequest(
            source: "echo שלום | python3 transform.py 'argument with spaces' עברית | cat > result.txt && node verify.cjs",
            workspace: workspace, environment: ["COMMAND_NAME": "world"]))
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout.contains("ACTUAL_MIXED_COMMAND_PIPELINE_PASSED"))
        #expect(try String(contentsOf: workspace.appending(path: "result.txt"), encoding: .utf8) == "hello\nworld\n")
    }

    @MainActor private final class JobCapture { var id: UUID? }

    @Test(.timeLimit(.minutes(1)))
    func cancellingShellWhileThePythonDirectoryLockIsBusyNeverRunsTheCommandLater() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "shell-queue-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = RuntimeFileLayout(root: root)
        let jobs = RuntimeJobStore(fileLayout: layout)
        let python = PythonRuntimeService(fileLayout: layout, jobs: jobs)
        let shell = ShellRuntimeService(fileLayout: layout, jobs: jobs)
        _ = try await shell.healthCheck()
        let workspace = try layout.workspace(client: .tools, identifier: "cross-engine-queue")
        let started = workspace.appending(path: "python-started")
        let release = workspace.appending(path: "release")
        let forbidden = workspace.appending(path: "must-not-run")
        let firstRequest = RuntimeExecutionRequest(source: """
        import pathlib, time
        pathlib.Path('python-started').touch()
        end = time.monotonic() + 20
        while not pathlib.Path('release').exists() and time.monotonic() < end:
            time.sleep(0.01)
        """, workspace: workspace)
        let first = Task { try await python.execute(firstRequest) }
        defer { try? Data().write(to: release); first.cancel() }
        let deadline = ContinuousClock.now + .seconds(5)
        while !FileManager.default.fileExists(atPath: started.path), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(FileManager.default.fileExists(atPath: started.path))
        let capture = JobCapture()
        let second = Task {
            try await RuntimeJobProgress.$reporter.withValue({ record in capture.id = record.executionID }) {
                try await shell.execute(tokens: ["touch", "must-not-run"], workspace: workspace, environment: [:], allowNetwork: false)
            }
        }
        let queueDeadline = ContinuousClock.now + .seconds(5)
        while capture.id == nil, ContinuousClock.now < queueDeadline { try await Task.sleep(for: .milliseconds(10)) }
        let id = try #require(capture.id)
        second.cancel()
        do { _ = try await second.value; Issue.record("Queued Shell command returned success after cancellation") }
        catch is CancellationError { }
        #expect(try await jobs.snapshot(id: id, kind: .shell)?.state == .cancelled)
        #expect(try await jobs.snapshot(id: firstRequest.id, kind: .localPython)?.state == .running)
        try Data().write(to: release)
        #expect(try await first.value.exitCode == 0)
        _ = try await shell.execute(tokens: ["pwd"], workspace: workspace, environment: [:], allowNetwork: false)
        #expect(!FileManager.default.fileExists(atPath: forbidden.path))
    }

    @Test func actualEmbeddedNodeExecutesThePinnedPortableShellWithoutJITOrAnOSSubprocess() async throws {
        let workspace = try RuntimeFileLayout.default.workspace(client: .tools, identifier: "portable-shell-\(UUID().uuidString)")
        let result = try await AppRuntimeCore.shared.node.executePortableShell(RuntimeExecutionRequest(source: """
        NAME='שלום'; echo "$NAME" > native-yarn.txt
        echo native-yarn-error 1>&2
        false || echo ACTUAL_PORTABLE_SHELL_COMPLETE
        """, workspace: workspace))
        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("ACTUAL_PORTABLE_SHELL_COMPLETE"))
        #expect(result.stderr.contains("native-yarn-error"))
        #expect(try String(contentsOf: workspace.appending(path: "native-yarn.txt"), encoding: .utf8) == "שלום\n")
        #expect(result.outputFiles?["stdout"] != nil)
    }

    @Test func linkedShellRetainsFullOutputBeyondThePreviewAndReopensLosslessPages() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "shell-full-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = RuntimeFileLayout(root: root)
        let jobs = RuntimeJobStore(fileLayout: layout)
        let shell = ShellRuntimeService(fileLayout: layout, jobs: jobs)
        let workspace = try layout.workspace(client: .tools, identifier: "full-output")
        let payload = Data(String(repeating: "שלום 👨‍👩‍👧‍👦\n", count: 400_000).utf8)
        #expect(payload.count > 10 * 1024 * 1024)
        try payload.write(to: workspace.appending(path: "input.txt"))
        let result = try await shell.execute(tokens: ["cat"], workspace: workspace,
            environment: [:], allowNetwork: false, standardInputURL: workspace.appending(path: "input.txt"),
            limits: .init(maximumOutputBytes: 17))
        #expect(result.exitCode == 0 && result.outputWasTruncated)
        #expect(result.stdout.utf8.count <= 17 && !result.stdout.contains("�"))
        let artifact = try #require(result.outputFiles?["stdout"])
        #expect(artifact.bytes == Int64(payload.count))
        #expect(artifact.sha256 == SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined())
        let reopened = RuntimeJobStore(fileLayout: layout)
        try await reopened.recoverInterrupted(.shell)
        #expect(try await reopened.snapshot(id: result.executionID, kind: .shell)?.state == .completed)
        var restored = Data()
        var offset: Int64 = 0
        while true {
            let page = try await reopened.output(id: result.executionID, kind: .shell, channel: "stdout", offset: offset, limit: 65533)
            let base64 = try #require(page["base64"])
            restored.append(try #require(Data(base64Encoded: base64)))
            if page["hasMore"] == "false" { break }
            let nextOffset = try #require(page["nextOffset"])
            offset = try #require(Int64(nextOffset))
        }
        #expect(restored == payload)
    }

    @Test func linkedShellActuallyPipesAndRedirectsWithinItsWorkspace() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "shell-pipe-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = RuntimeFileLayout(root: root)
        let shell = ShellRuntimeService(fileLayout: layout)
        let workspace = try layout.workspace(client: .tools, identifier: "pipe-proof")
        let text = "שלום\nworld\n"
        try Data(text.utf8).write(to: workspace.appending(path: "input.txt"))
        let result = try await shell.execute(command: "cat input.txt | wc -c > count.txt", workspace: workspace,
            environment: [:], allowNetwork: false)
        #expect(result.exitCode == 0)
        let count = try String(contentsOf: workspace.appending(path: "count.txt"), encoding: .utf8)
        #expect(Int(count.trimmingCharacters(in: .whitespacesAndNewlines)) == text.utf8.count)
        #expect(result.outputFiles?["stdout"] != nil && result.outputFiles?["stderr"] != nil)
    }

    @Test func linkedShellActuallyAcceptsMoreThan127Arguments() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "shell-argv-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = RuntimeFileLayout(root: root)
        let workspace = try layout.workspace(client: .tools, identifier: "argv-proof")
        try Data("שלום\n".utf8).write(to: workspace.appending(path: "one.txt"))
        let shell = ShellRuntimeService(fileLayout: layout)
        let result = try await shell.execute(tokens: ["cat"] + Array(repeating: "one.txt", count: 256),
            workspace: workspace, environment: [:], allowNetwork: false)
        #expect(result.exitCode == 0)
        #expect(result.stdout == String(repeating: "שלום\n", count: 256))
        #expect(!result.outputWasTruncated)
    }

    @Test func embeddedPythonActuallyDownloadsVerifiesInstallsAndImportsAPureWheel() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "python-pypi-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = RuntimeFileLayout(root: root)
        let python = PythonRuntimeService(fileLayout: layout)
        let manager = PythonPackageManager(fileLayout: layout, python: python)
        let record = try await manager.install(name: "six", version: "1.17.0")
        #expect(record.name == "six" && record.version == "1.17.0")
        #expect(record.sha256.count == 64)
        let probe = try await manager.probe(record)
        #expect(probe.exitCode == 0)
        #expect(probe.stdout.contains("1.17.0"))
        let tlsWorkspace = try layout.workspace(client: .tools, identifier: "tls-policy")
        let tls = try await python.execute(RuntimeExecutionRequest(source: """
        import ssl
        context = ssl.create_default_context()
        assert context.verify_mode == ssl.CERT_REQUIRED
        assert context.check_hostname
        assert context.cert_store_stats()['x509_ca'] > 0
        print('TLS_VERIFICATION_REQUIRED')
        """, workspace: tlsWorkspace))
        #expect(tls.exitCode == 0 && tls.stdout.contains("TLS_VERIFICATION_REQUIRED"))
        #expect(!probe.didTimeOut && !probe.wasCancelled)
        print("EMBEDDED_PYPI_INSTALL six=\(record.version) sha256=\(record.sha256) job=\(probe.executionID)")
    }

    @Test func bundledNativePythonExtensionInstallsAndExecutesARealNonce() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "native-python-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = RuntimeFileLayout(root: root)
        let python = PythonRuntimeService(fileLayout: layout)
        let manager = PythonPackageManager(fileLayout: layout, python: python)
        let record = try await manager.install(name: "hanlin-native")
        #expect(record.importName == "hanlin_native")
        let nonce = UUID().uuidString
        let quoted = String(decoding: try JSONEncoder().encode(nonce), as: UTF8.self)
        let workspace = try layout.workspace(client: .tools, identifier: "native-proof")
        let result = try await python.execute(RuntimeExecutionRequest(source: """
        import hanlin_native, sys
        try:
            __hanlin_result__ = hanlin_native.challenge(\(quoted))
            print(hanlin_native.registry())
        finally:
            sys.modules.pop('hanlin_native', None)
        """, workspace: workspace))
        #expect(result.exitCode == 0)
        guard case .object(let value) = result.value else { Issue.record("Native extension returned no structured result: \(result.stderr)"); return }
        #expect(value["nonce"] == .string(nonce))
        #expect(value["engine"] == .string("cpython-native-extension"))
        #expect(value["linkage"] == .string("signed-app-builtin"))
    }

    @Test(.timeLimit(.minutes(10)))
    func embeddedNodeAndPythonActuallyRunBeyondThreeHundredSeconds() async throws {
        let layout = RuntimeFileLayout.default
        let nodeWorkspace = try layout.workspace(client: .tools, identifier: "long-node-\(UUID().uuidString)")
        let pythonWorkspace = try layout.workspace(client: .tools, identifier: "long-python-\(UUID().uuidString)")
        let start = ContinuousClock.now
        async let node = AppRuntimeCore.shared.node.executeJavaScript(RuntimeExecutionRequest(source: """
        console.log('EMBEDDED_NODE_LONG_START');
        await new Promise(resolve => setTimeout(resolve, 305000));
        console.log('EMBEDDED_NODE_LONG_COMPLETE');
        export default 305;
        """, workspace: nodeWorkspace), moduleKind: "esm")
        async let python = AppRuntimeCore.shared.python.execute(RuntimeExecutionRequest(source: """
        import time
        print('EMBEDDED_PYTHON_LONG_START', flush=True)
        time.sleep(305)
        print('EMBEDDED_PYTHON_LONG_COMPLETE', flush=True)
        __hanlin_result__ = 305
        """, workspace: pythonWorkspace))
        let (nodeResult, pythonResult) = try await (node, python)
        #expect(start.duration(to: .now) >= .seconds(300))
        for result in [nodeResult, pythonResult] {
            #expect(result.exitCode == 0)
            #expect(!result.didTimeOut && !result.wasCancelled)
            #expect(result.durationMilliseconds >= 300_000)
            #expect(result.value == .number(305))
            #expect(result.outputFiles?["stdout"]?.bytes ?? 0 > 0)
        }
        #expect(nodeResult.stdout.contains("EMBEDDED_NODE_LONG_COMPLETE"))
        #expect(pythonResult.stdout.contains("EMBEDDED_PYTHON_LONG_COMPLETE"))
        print("EMBEDDED_LONG_JOBS node=\(nodeResult.executionID) ms=\(nodeResult.durationMilliseconds) python=\(pythonResult.executionID) ms=\(pythonResult.durationMilliseconds)")
    }
    @Test func retainedNativePythonCancellationCallbackRemainsValidAfterItsJobIsReleased() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "python-capsule-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = RuntimeFileLayout(root: root)
        let python = PythonRuntimeService(fileLayout: layout)
        let workspace = try layout.workspace(client: .tools, identifier: "capsule-proof")
        let key = "__hanlin_cancel_probe_" + UUID().uuidString.replacingOccurrences(of: "-", with: "_")
        let literal = String(decoding: try JSONEncoder().encode(key), as: UTF8.self)
        let first = try await python.execute(RuntimeExecutionRequest(source: """
        import builtins, inspect, sys
        callback = inspect.getclosurevars(sys.gettrace()).nonlocals['cancelled']
        setattr(builtins, \(literal), callback)
        """, workspace: workspace))
        #expect(first.exitCode == 0)
        // execute() has now unregistered the first job's native cancellation ID.
        let second = try await python.execute(RuntimeExecutionRequest(source: """
        import builtins, gc
        try:
            gc.collect()
            callback = getattr(builtins, \(literal))
            assert all(callback() is False for _ in range(1024))
            print('RETAINED_NATIVE_CANCELLATION_CONTEXT_VALID')
        finally:
            if hasattr(builtins, \(literal)):
                delattr(builtins, \(literal))
        """, workspace: workspace))
        #expect(second.exitCode == 0)
        #expect(second.stdout.contains("RETAINED_NATIVE_CANCELLATION_CONTEXT_VALID"))
    }

    @Test func runtimeOutputKeepsRetrievalMetadataForTheAgentAndReadableContentForTheUser() throws {
        let id = UUID()
        let execution = RuntimeExecutionResult(executionID: id, stdout: "42\n", stderr: "", value: nil,
            exitCode: 0, durationMilliseconds: 3, didTimeOut: false, wasCancelled: false, outputWasTruncated: false,
            outputFiles: ["stdout": .init(path: "/private/job/stdout.log", bytes: 3, sha256: String(repeating: "a", count: 64))])
        let result = RuntimeToolSupport.result(execution, title: "Local Python", systemImage: "terminal", runtimeKind: .localPython, argumentKeys: ["source"])
        #expect(result.modelText.contains(id.uuidString) && result.modelText.contains("get_runtime_job"))
        #expect(result.modelText.contains("SHA256"))
        #expect(result.isStoreEligible, "Large runtime values must use the existing full result store and read pages")
        #expect(result.userText == "42\n")
        #expect(result.uiBlocks.first?.body == "42\n")
        #expect(result.uiBlocks.first?.subtitle == nil)
    }

    @Test func defaultSchemaExposureDoesNotHideToolsPastOldBudgets() {
        let aliases = (0..<64).map { "tool_\($0)" }
        let sizes = Dictionary(uniqueKeysWithValues: aliases.map { ($0, 1024) })
        let decision = AssistantToolExposurePlanner().plan(candidateAliases: aliases, schemaSizes: sizes)
        #expect(decision.exposedAliases == aliases)
        #expect(decision.deferredAliases.isEmpty)
        #expect(decision.totalExposedBytes == 65536)
    }

    @Test func fullResultsExceedOldCountAndByteCapsAndSurviveReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ToolResultStore(directory: directory)
        let payload = String(repeating: "שלום 👨‍👩‍👧‍👦\n", count: 8192)
        let digest = SHA256.hash(data: Data(payload.utf8))
        var references: [String] = []
        for _ in 0..<64 { references.append(try #require(store.store(payload))) }
        #expect(store.currentTotalBytes > 10 * 1024 * 1024)
        let reopened = ToolResultStore(directory: directory)
        for reference in references {
            let full = try #require(reopened.fullPayload(for: reference))
            #expect(SHA256.hash(data: Data(full.utf8)) == digest)
        }
        let reference = try #require(references.first)
        var reconstructed = ""
        var offset = 0
        while true {
            let slice = try #require(reopened.read(reference: reference, offset: offset, limit: 4093))
            reconstructed += slice.chunk
            if !slice.hasMore { break }
            offset = slice.offset + slice.sliceLength
        }
        #expect(reconstructed == payload)
        #expect(reopened.read(reference: "../../private") == nil)
    }

    @Test func finishingRunKeepsHistoryReferencesButNotExposedSchemas() throws {
        let session = AssistantCapabilitySession()
        defer { session.resultStore.clear() }
        session.exposeTools(aliases: ["private_run_tool"])
        let reference = try #require(session.resultStore.store("saved result שלום"))
        session.finishRun()
        session.reset()
        #expect(!session.isToolExposed("private_run_tool"))
        #expect(session.resultStore.fullPayload(for: reference) == "saved result שלום")
    }

    @Test func capabilityReportNeverPromotesStoppedOrFailedEnginesToReady() throws {
        var failed = RuntimeSnapshot.stopped(.node)
        failed.state = .failed
        failed.lastErrorCode = "startup_failed"
        let report = RuntimeCapabilityContract(snapshots: [.stopped(.localPython), failed])
        let encoded = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(RuntimeCapabilityContract.self, from: encoded)
        #expect(decoded.snapshots[0].state == .stopped)
        #expect(decoded.snapshots[0].version == nil)
        #expect(decoded.snapshots[1].state == .failed)
        #expect(decoded.snapshots[1].lastErrorCode == "startup_failed")
    }
    @Test func subsequentTurnsCanReadOwnChatResultsWithoutLeakingOtherChats() throws {
        let chatID = UUID().uuidString
        let first = AssistantCapabilitySession(chatID: chatID)
        defer { first.resultStore.clear() }
        let reference = try #require(first.resultStore.store("persisted across turns שלום"))
        first.exposeTools(aliases: ["run_scoped_only"])
        first.finishRun()
        let second = AssistantCapabilitySession(chatID: chatID)
        #expect(second.resultStore.fullPayload(for: reference) == "persisted across turns שלום")
        #expect(!second.isToolExposed("run_scoped_only"))
        let unrelated = AssistantCapabilitySession(chatID: UUID().uuidString)
        defer { unrelated.resultStore.clear() }
        #expect(unrelated.resultStore.fullPayload(for: reference) == nil)
        let temporary = AssistantCapabilitySession(chatID: chatID, isTemporaryChat: true)
        defer { temporary.resultStore.clear() }
        #expect(temporary.resultStore.fullPayload(for: reference) == nil)
    }

    @Test func journalRetainsCompletedJobsAndMarksUnfinishedOnRestart() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = RuntimeFileLayout(root: root)
        let jobs = RuntimeJobStore(fileLayout: layout)
        let id = UUID()
        _ = try await jobs.create(id: id, kind: .localPython)
        try await jobs.markRunning(id: id, kind: .localPython)
        let output = "שלום 👋🏽"
        try Data(output.utf8).write(to: jobs.directory(id: id, kind: .localPython).appending(path: "stdout.log"))
        let progress = try await jobs.refresh(id: id, kind: .localPython)
        #expect(progress?.state == .running)
        #expect(progress?.stdoutBytes == Int64(output.utf8.count))
        let result = RuntimeExecutionResult(executionID: id, stdout: output, stderr: "", value: nil,
            exitCode: 0, durationMilliseconds: 1, didTimeOut: false, wasCancelled: false, outputWasTruncated: false)
        try await jobs.complete(result, kind: .localPython)
        let unfinished = UUID()
        _ = try await jobs.create(id: unfinished, kind: .localPython)
        let reopened = RuntimeJobStore(fileLayout: layout)
        try await reopened.recoverInterrupted(.localPython)
        let preserved = try await reopened.snapshot(id: id, kind: .localPython)
        let interrupted = try await reopened.snapshot(id: unfinished, kind: .localPython)
        #expect(preserved?.state == .completed && preserved?.result?.stdout == output)
        #expect(interrupted?.state == .interrupted)
        #expect(RuntimeExecutionLimits().timeout == nil)
        #expect(try RuntimeExecutionLimits(timeout: .seconds(600)).timeoutMilliseconds() == 600_000)
    }

}
