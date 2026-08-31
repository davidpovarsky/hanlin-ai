import CryptoKit
import Foundation
import HanlinPlatformContracts
import HanlinScriptCompiler
import HanlinScriptContracts
import HanlinScriptStore
import HanlinScriptingApplicationRuntime
import HanlinScriptingSDK
import Testing
@testable import AI_Hanlin

@Suite("Hanlin Scripting Phase 2A acceptance", .serialized)
struct HanlinScriptingAcceptanceTests {
    @MainActor
    @Test("Routes structured AssistantTool parts to model and native user presentation")
    func structuredAssistantToolResult() throws {
        let result = HanlinScriptToolExecutionResult(
            success: true,
            message: "",
            userParts: [
                .text("Shown to the user"),
                .image(base64: "iVBORw0KGgo=", mimeType: "image/png"),
            ],
            assistantParts: [.text("Sent only to the assistant")]
        )

        let native = try AssistantToolBridge.Executors.nativeResult(for: result)

        #expect(native.userText == "Shown to the user")
        #expect(native.uiBlocks.count == 2)
        #expect(native.uiBlocks[0].type == .markdown)
        #expect(native.uiBlocks[1].embeddedImageBase64 == "iVBORw0KGgo=")
        #expect(native.modelText.contains("Sent only to the assistant"))
        #expect(!native.modelText.contains("Shown to the user"))
    }

    @MainActor
    @Test("Loads, projects, routes, and executes the TypeScript fixture")
    func executableVerticalSlice() async throws {
        let registry = HanlinScriptingProviderRegistry()
        let directory = try materializedFixtureDirectory("ValidEcho")
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstIdentity = try await registry.loadPackage(at: directory, trust: .bundledTrusted)
        let secondIdentity = try await registry.loadPackage(at: directory, trust: .bundledTrusted)
        #expect(firstIdentity == secondIdentity)

        let snapshots = await registry.snapshots()
        let sources = try HanlinScriptCanonicalAdapter.project(snapshots)
        let authority = try HanlinCanonicalToolAuthority.build(
            nativeSources: [],
            mcpTools: [],
            scriptSources: sources,
            generatedAt: Date(timeIntervalSince1970: 8)
        )
        let alias = try #require(authority.catalog.entries.first?.modelAlias)
        var nativeCalls = 0
        var mcpCalls = 0
        var scriptCalls = 0
        let prepared = AssistantToolBridge.PreparedTools(
            authority: authority,
            executors: .init(
                executeNative: { _, _, _, _ in
                    nativeCalls += 1
                    return NativeToolResult(modelText: "wrong-native")
                },
                executeMCP: { _, _, _, _ in
                    mcpCalls += 1
                    return NativeToolResult(modelText: "wrong-mcp")
                },
                executeScripting: { route, arguments in
                    scriptCalls += 1
                    do {
                        let result = try await registry.execute(
                            route: route,
                            argumentsJSON: arguments
                        )
                        return NativeToolResult(modelText: result.message)
                    } catch {
                        Issue.record("Script registry execution failed")
                        return NativeToolResult(modelText: "script-failure")
                    }
                }
            )
        )

        #expect(prepared.schemas.count == 1)
        let result = await prepared.execute(
            alias: alias,
            argumentsJSON: #"{"text":"phase-2a"}"#,
            context: .init(localeIdentifier: "en")
        )
        #expect(result?.modelText == "script:phase-2a")
        #expect(nativeCalls == 0)
        #expect(mcpCalls == 0)
        #expect(scriptCalls == 1)

        await registry.unloadAll()
        let finalSnapshots = await registry.snapshots()
        #expect(finalSnapshots.isEmpty)
    }

    @Test("Rejects malformed packages before provider availability")
    func malformedPackageIsUnavailable() async throws {
        let registry = HanlinScriptingProviderRegistry()
        let malformedDirectory = try materializedMalformedPackage()
        defer { try? FileManager.default.removeItem(at: malformedDirectory) }
        do {
            _ = try await registry.loadPackage(at: malformedDirectory, trust: .bundledTrusted)
            Issue.record("Malformed package unexpectedly loaded")
        } catch {
            let snapshots = await registry.snapshots()
            #expect(snapshots.isEmpty)
        }
    }

    @Test("Binds provider availability to manifest and artifact integrity")
    func integrityTamperingIsUnavailable() async throws {
        let registry = HanlinScriptingProviderRegistry()
        let metadataCopy = try materializedPackageCopy(named: "metadata")
        defer { try? FileManager.default.removeItem(at: metadataCopy) }
        let metadataManifest = metadataCopy.appending(
            path: "hanlin-script.json",
            directoryHint: .notDirectory
        )
        let original = try String(contentsOf: metadataManifest, encoding: .utf8)
        let tampered = original.replacingOccurrences(
            of: "Hanlin Script Echo Fixture",
            with: "Tampered Script Echo Fixture"
        )
        try Data(tampered.utf8).write(to: metadataManifest, options: .atomic)
        await expectUnavailableLoad(registry: registry, directory: metadataCopy)

        let artifactCopy = try materializedPackageCopy(named: "artifact")
        defer { try? FileManager.default.removeItem(at: artifactCopy) }
        let artifact = artifactCopy.appending(
            path: "assistant_tool.js",
            directoryHint: .notDirectory
        )
        var artifactData = try Data(contentsOf: artifact)
        artifactData.append(0x0A)
        try artifactData.write(to: artifact, options: .atomic)
        await expectUnavailableLoad(registry: registry, directory: artifactCopy)
    }

    private func expectUnavailableLoad(
        registry: HanlinScriptingProviderRegistry,
        directory: URL
    ) async {
        do {
            _ = try await registry.loadPackage(at: directory, trust: .bundledTrusted)
            Issue.record("Tampered package unexpectedly loaded")
        } catch {
            let snapshots = await registry.snapshots()
            #expect(snapshots.isEmpty)
        }
    }
}

@Suite("Scripting production compiler acceptance", .serialized)
struct HanlinScriptingProductionCompilerAcceptanceTests {
    @MainActor
    @Test("Compiles every supported raw corpus package through NodeMobile and the real bundler")
    func supportedCorpus() async throws {
        let authority = try productionCompilerAuthority()
        let fixtures = try productionCompilerFixtures(expected: "success")
        #expect(fixtures.map(\.lastPathComponent).sorted() == ["ValidScriptUI", "ValidStorageModules"])

        for fixture in fixtures {
            let staged = try stagedProductionCompilerFixture(fixture)
            defer { try? FileManager.default.removeItem(at: staged.stagingRoot) }
            let preview = try authority.analyzer.analyze(staged)
            #expect(preview.canInstall, "\(fixture.lastPathComponent) failed import analysis")
            let bundle = try await authority.bundler.bundle(
                package: staged,
                preview: preview,
                context: .app
            )
            #expect(bundle.manifest.compilerVersion == HanlinScriptingBundler.compilerVersion)
            #expect(!bundle.modules.isEmpty)
            #expect(bundle.modules.allSatisfy { !$0.javaScript.isEmpty })

            let module = try #require(bundle.modules.first)
            let entrypointContext: HanlinScriptingEntrypointContext =
                fixture.lastPathComponent == "ValidScriptUI" ? .application : .intent()
            let session = try HanlinScriptingApplicationSession(
                installedPackageID: try HanlinInstalledPackageID(
                    validating: "compiler-acceptance.\(fixture.lastPathComponent.lowercased())"
                ),
                program: String(decoding: module.javaScript, as: UTF8.self),
                filename: module.logicalPath,
                entrypointContext: entrypointContext,
                storageAllowed: true
            )
            if fixture.lastPathComponent == "ValidScriptUI" {
                #expect(session.model.root.kind == .vStack)
            }
            session.dispose()
        }
    }

    @MainActor
    @Test("Rejects mistyped Scripting and DOM APIs without weakening strict checking")
    func strictFailures() async throws {
        let authority = try productionCompilerAuthority()
        let expectedCodes = [
            "InvalidScriptingAPI": 2339,
            "InvalidDOMGlobal": 2304,
        ]
        for (name, code) in expectedCodes {
            let fixture = try productionCompilerFixture(named: name)
            let staged = try stagedProductionCompilerFixture(fixture)
            defer { try? FileManager.default.removeItem(at: staged.stagingRoot) }
            let preview = try authority.analyzer.analyze(staged)
            #expect(preview.canInstall)
            do {
                _ = try await authority.bundler.bundle(
                    package: staged,
                    preview: preview,
                    context: .app
                )
                Issue.record("\(name) unexpectedly compiled")
            } catch let HanlinScriptingBundlerError.compilerFailed(diagnostics) {
                #expect(diagnostics.contains { $0.code == code })
            }
        }

        let bareImport = try stagedProductionCompilerFixture(
            productionCompilerFixture(named: "InvalidBareImport")
        )
        defer { try? FileManager.default.removeItem(at: bareImport.stagingRoot) }
        let preview = try authority.analyzer.analyze(bareImport)
        #expect(!preview.canInstall)
        #expect(preview.dependencyGraph.unresolvedSpecifiers == ["unsupported-package"])
    }
}

@Suite("Script Package production installation E2E", .serialized)
struct HanlinScriptPackageProductionE2ETests {
    @MainActor
    @Test("Exports, imports, approves, installs, restores, launches, and renders through production")
    func productionPackageFlow() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "hanlin-production-package-e2e-\(UUID().uuidString.lowercased())",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "ProductionE2E", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data(#"{"name":"Production Package E2E","version":"1.0.0","entry":"index.tsx","runInApp":true}"#.utf8)
            .write(to: source.appending(path: "script.json"), options: .atomic)
        try Data(#"""
        import { Navigation, Text } from "scripting"
        Storage.set("production-e2e", "passed")
        Navigation.present({ element: <Text>Production Package E2E Passed</Text> })
        """#.utf8).write(to: source.appending(path: "index.tsx"), options: .atomic)
        let archive = root.appending(path: "production-e2e.scripting", directoryHint: .notDirectory)
        try HanlinScriptingPackageExporter().exportPackage(at: source, to: archive)

        let platformRoot = root.appending(path: "Platform", directoryHint: .isDirectory)
        let platform = HanlinScriptingPlatform(rootOverride: platformRoot)
        await platform.importPackage(from: archive)
        let preview = try #require(platform.preview)
        let storage = try HanlinCapabilityID(validating: "storage")
        #expect(preview.requestedCapabilities.map(\.capabilityID).contains(storage))

        await platform.installPreview()
        #expect(platform.activity == .failed("Approve every required capability before installing this package."))
        platform.setCapabilityApproved(true, capability: storage)
        await platform.installPreview()
        #expect(platform.activity == .idle)
        let installed = try #require(platform.installedPackages.first)
        #expect(installed.grantedCapabilities == [storage])

        await platform.launch(installed.record.installedPackageID)
        #expect(platform.activeApplicationModel?.root.properties["text"] == .string("Production Package E2E Passed"))
        platform.dismissActiveApplication()

        // Reproduce the on-device upgrade state that caused a new, valid
        // installation to be reported as artifactManifestMissing: an older
        // unrelated generation is present without the current artifact contract.
        let staleManifest = platformRoot.appending(
            path: "Installed/packages/\(installed.record.installedPackageID.rawValue)/generations/1/artifact-manifest.json",
            directoryHint: .notDirectory
        )
        try FileManager.default.removeItem(at: staleManifest)
        let secondSource = root.appending(path: "ProductionE2ESecond", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: secondSource, withIntermediateDirectories: true)
        try Data(#"{"name":"Production Package E2E Second","version":"1.0.0","entry":"index.tsx","runInApp":true}"#.utf8)
            .write(to: secondSource.appending(path: "script.json"), options: .atomic)
        try Data(#"""
        import { Navigation, Text } from "scripting"
        Storage.set("production-e2e-second", "passed")
        Navigation.present({ element: <Text>Second Production Package Passed</Text> })
        """#.utf8).write(to: secondSource.appending(path: "index.tsx"), options: .atomic)
        let secondArchive = root.appending(path: "production-e2e-second.scripting", directoryHint: .notDirectory)
        try HanlinScriptingPackageExporter().exportPackage(at: secondSource, to: secondArchive)
        await platform.importPackage(from: secondArchive)
        platform.setCapabilityApproved(true, capability: storage)
        await platform.installPreview()
        #expect(platform.activity == .idle)
        #expect(platform.installedPackages.count == 2)
        let second = try #require(platform.installedPackages.first {
            $0.manifest?.name == "Production Package E2E Second"
        })
        await platform.launch(second.record.installedPackageID)
        #expect(platform.activeApplicationModel?.root.properties["text"] == .string("Second Production Package Passed"))
        platform.dismissActiveApplication()

        let restored = HanlinScriptingPlatform(rootOverride: platformRoot)
        await restored.restore()
        #expect(restored.installedPackages.count == 2)
        await restored.launch(second.record.installedPackageID)
        #expect(restored.activeApplicationModel?.root.properties["text"] == .string("Second Production Package Passed"))
        restored.dismissActiveApplication()
    }
}

@Suite("Physical iPad Script App restart regression", .serialized)
struct HanlinScriptPackagePhysicalIPadRegressionTests {
    private static let fixtureSHA256 = "c8ee66e4e5e6a06a884b2a1d7b552d51691cb824f245e4cca238bc44d1509d57"

    @MainActor
    @Test("Exact external ZIP keeps its active artifact across a cold platform restoration")
    func exactExternalArchiveColdRestoration() async throws {
        let applicationSupport = try #require(
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        )
        let evidenceRoot = applicationSupport.appending(
            path: "HanlinScriptRestartRegression",
            directoryHint: .isDirectory
        )
        let platformRoot = evidenceRoot.appending(path: "Platform", directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: evidenceRoot.path()) {
            try FileManager.default.removeItem(at: evidenceRoot)
        }
        try FileManager.default.createDirectory(at: evidenceRoot, withIntermediateDirectories: true)

        let fixture = try physicalIPadArchiveFixture()
        let fixtureData = try Data(contentsOf: fixture)
        let fixtureDigest = SHA256.hash(data: fixtureData)
            .map { String(format: "%02x", $0) }.joined()
        #expect(fixtureDigest == Self.fixtureSHA256)
        let providerCopy = evidenceRoot.appending(path: "provider-source.zip", directoryHint: .notDirectory)
        try fixtureData.write(to: providerCopy, options: .atomic)

        let installed = try await installPhysicalIPadFixture(
            providerCopy: providerCopy,
            platformRoot: platformRoot,
            evidenceRoot: evidenceRoot
        )
        #expect(!FileManager.default.fileExists(atPath: providerCopy.path()))

        let generationRoot = platformRoot.appending(
            path: "Installed/packages/\(installed.record.installedPackageID.rawValue)/generations/\(installed.record.activeGeneration)",
            directoryHint: .isDirectory
        )
        let manifestURL = generationRoot.appending(path: "artifact-manifest.json", directoryHint: .notDirectory)
        #expect(FileManager.default.fileExists(atPath: manifestURL.path()))
        try writePhysicalIPadEvidence(
            checkpoint: "before-cold-restoration",
            evidenceRoot: evidenceRoot,
            platformRoot: platformRoot,
            package: installed
        )

        let restored = HanlinScriptingPlatform(rootOverride: platformRoot)
        await restored.restore()
        let restoredPackage = try #require(restored.installedPackages.first {
            $0.record.installedPackageID == installed.record.installedPackageID
        })
        #expect(restoredPackage.record.activeGeneration == installed.record.activeGeneration)
        #expect(restoredPackage.availableGenerations.contains(installed.record.activeGeneration))
        #expect(FileManager.default.fileExists(atPath: manifestURL.path()))
        await restored.launch(restoredPackage.record.installedPackageID)
        if case let .failed(message) = restored.activity {
            Issue.record("Cold launch failed: \(message)")
        }
        #expect(restored.activeApplicationModel != nil)
        try writePhysicalIPadEvidence(
            checkpoint: "after-cold-restoration",
            evidenceRoot: evidenceRoot,
            platformRoot: platformRoot,
            package: restoredPackage
        )
        restored.dismissActiveApplication()
    }

    @MainActor
    private func installPhysicalIPadFixture(
        providerCopy: URL,
        platformRoot: URL,
        evidenceRoot: URL
    ) async throws -> HanlinStoredPackageSnapshot {
        let platform = HanlinScriptingPlatform(rootOverride: platformRoot)
        await platform.importPackage(from: providerCopy)
        let preview = try #require(platform.preview)
        #expect(preview.source.contentSHA256 == Self.fixtureSHA256)
        #expect(preview.entrypoints.map(\.runtimeProfile).allSatisfy { $0 == .scriptingJSC })

        // The installed app must no longer depend on the Files/File Provider URL.
        try FileManager.default.removeItem(at: providerCopy)
        for capability in preview.requestedCapabilities.map(\.capabilityID) {
            platform.setCapabilityApproved(true, capability: capability)
        }
        await platform.installPreview()
        if case let .failed(message) = platform.activity {
            try Data(message.utf8).write(
                to: evidenceRoot.appending(path: "install-error.txt"),
                options: .atomic
            )
            Issue.record("Exact physical-iPad fixture failed installation: \(message)")
        }
        #expect(platform.activity == .idle)
        let installed = try #require(platform.installedPackages.first)
        await platform.launch(installed.record.installedPackageID)
        if case let .failed(message) = platform.activity {
            try Data(message.utf8).write(
                to: evidenceRoot.appending(path: "first-launch-error.txt"),
                options: .atomic
            )
            Issue.record("Exact physical-iPad fixture failed first launch: \(message)")
        }
        try writePhysicalIPadEvidence(
            checkpoint: "after-install-and-first-launch",
            evidenceRoot: evidenceRoot,
            platformRoot: platformRoot,
            package: installed
        )
        platform.dismissActiveApplication()
        return installed
    }
}

@Suite("Scripting JavaScriptCore compatibility engine", .serialized)
struct HanlinJavaScriptCoreEngineTests {
    @Test("Keeps a persistent isolated context and exposes no privileged globals")
    func persistentContextAndDefaultDeny() async throws {
        let session = try HanlinJavaScriptCoreSession()
        try await session.loadProgram(
            #"""
            let state = { invocationCount: 0 };
            AssistantTool.registerExecuteTool(() => ({
              success: typeof process === "undefined"
                && typeof require === "undefined"
                && typeof fetch === "undefined",
              message: String(++state.invocationCount)
            }));
            """#,
            filename: "fixture.js",
            expectedToolCount: 1
        )
        let first = try await session.invoke(toolIndex: 0, parameters: .object([:]))
        let second = try await session.invoke(toolIndex: 0, parameters: .object([:]))
        guard case let .object(firstMembers) = first,
              case let .bool(success)? = firstMembers["success"],
              case let .string(firstMessage)? = firstMembers["message"],
              case let .object(secondMembers) = second,
              case let .string(secondMessage)? = secondMembers["message"] else {
            Issue.record("JavaScriptCore result did not cross the canonical bridge")
            return
        }
        #expect(success)
        #expect(firstMessage == "1")
        #expect(secondMessage == "2")
        await session.dispose()
    }

    @Test("Implements AssistantTool call state, progress replacement, cancellation, and reuse")
    func assistantToolLifecycle() async throws {
        let session = try HanlinJavaScriptCoreSession()
        try await session.loadProgram(
            #"""
            globalThis.cancelMarker = "none";
            AssistantTool.registerExecuteTool((parameters) => {
              if (parameters.hang) {
                AssistantTool.onCancel = () => { globalThis.cancelMarker = "cancelled"; return "cancelled"; };
                return new Promise(() => {});
              }
              AssistantTool.setState("value", parameters.value);
              AssistantTool.report("first", "progress");
              AssistantTool.report("second", "progress");
              const reports = globalThis.__hanlinToolReports();
              return {
                success: AssistantTool.getState("value") === parameters.value
                  && reports.length === 1
                  && reports[0].message === "second"
                  && !AssistantTool.isCancelled,
                message: globalThis.cancelMarker
              };
            });
            """#,
            filename: "assistant_tool.js",
            expectedToolCount: 1
        )

        let first = try await session.invoke(
            toolIndex: 0,
            parameters: .object(["hang": .bool(false), "value": .string("stored")])
        )
        guard case let .object(firstMembers) = first,
              case let .bool(firstSuccess)? = firstMembers["success"] else {
            Issue.record("AssistantTool state and reports did not cross the bridge")
            await session.dispose()
            return
        }
        #expect(firstSuccess)

        let hanging = Task {
            try await session.invoke(
                toolIndex: 0,
                parameters: .object(["hang": .bool(true), "value": .null])
            )
        }
        await session.waitUntilInvocationStarted()
        hanging.cancel()
        do {
            _ = try await hanging.value
            Issue.record("Cancelled AssistantTool invocation unexpectedly completed")
        } catch let error as HanlinScriptingError {
            #expect(error == .cancelled)
        }

        let afterCancellation = try await session.invoke(
            toolIndex: 0,
            parameters: .object(["hang": .bool(false), "value": .string("next")])
        )
        guard case let .object(members) = afterCancellation,
              case let .string(message)? = members["message"] else {
            Issue.record("AssistantTool session was not reusable after cancellation")
            await session.dispose()
            return
        }
        #expect(message == "cancelled")
        await session.dispose()
    }

    @Test("Disposal resumes a pending JavaScriptCore invocation")
    func disposalResumesPendingInvocation() async throws {
        let session = try HanlinJavaScriptCoreSession()
        try await session.loadProgram(
            "AssistantTool.registerExecuteTool(() => new Promise(() => {}));",
            filename: "assistant_tool.js",
            expectedToolCount: 1
        )
        let pending = Task {
            try await session.invoke(toolIndex: 0, parameters: .object([:]))
        }
        try await Task.sleep(for: .milliseconds(20))
        await session.dispose()
        do {
            _ = try await pending.value
            Issue.record("Disposed JavaScriptCore invocation unexpectedly completed")
        } catch let error as HanlinScriptingError {
            #expect(error == .unavailableProvider("disposed_session"))
        }
    }
}

@Suite("Installed Scripting application runtime", .serialized)
struct HanlinScriptingApplicationRuntimeTests {
    @MainActor
    @Test("Renders multi-component ScriptUI and reconciles stateful events")
    func interactiveScriptUI() throws {
        let packageID = try HanlinInstalledPackageID(validating: "install-script-ui-acceptance")
        let session = try HanlinScriptingApplicationSession(
            installedPackageID: packageID,
            program: #"""
            Storage.clear();
            Storage.set("launch-count", 1);
            function App() {
              const [count, setCount] = useState(Storage.get("launch-count"));
              return createElement(VStack, { spacing: 8 },
                createElement(Text, null, "Count ", count),
                createElement(Button, {
                  title: "Increment",
                  action: () => {
                    Storage.set("launch-count", count + 1);
                    setCount(value => value + 1);
                  }
                })
              );
            }
            Navigation.present({ element: createElement(App, null) });
            """#,
            filename: "compiled/index.js",
            storageAllowed: true
        )
        #expect(session.model.root.kind == .vStack)
        #expect(session.model.root.children.first?.properties["text"] == .string("Count 1"))
        guard case let .string(handlerID)? = session.model.root.children.last?.properties["onPress"] else {
            Issue.record("The button action was not bridged to a typed handler identity")
            session.dispose()
            return
        }
        try session.model.apply(.event(handlerID: handlerID, payload: .null))
        #expect(session.model.root.children.first?.properties["text"] == .string("Count 2"))
        session.dismiss()
    }

    @MainActor
    @Test("Denies package storage when the capability is not granted")
    func deniedStorage() throws {
        let packageID = try HanlinInstalledPackageID(validating: "install-script-ui-denied")
        do {
            _ = try HanlinScriptingApplicationSession(
                installedPackageID: packageID,
                program: #"Storage.get("not-granted"); Navigation.present({ element: createElement(Text, null, "No") });"#,
                filename: "compiled/index.js",
                storageAllowed: false
            )
            Issue.record("Storage was available without the package capability")
        } catch {
            // Expected: the denied synchronous Storage access aborts launch.
        }
    }

    @MainActor
    @Test("Bridges Path, binary Data, Storage, and package-scoped FileManager to native services")
    func nativeFoundationServices() throws {
        let packageID = try HanlinInstalledPackageID(
            validating: "install-foundation-\(UUID().uuidString.lowercased())"
        )
        let runtimeRoot = FileManager.default.temporaryDirectory.appending(
            path: "hanlin-foundation-\(UUID().uuidString.lowercased())",
            directoryHint: .isDirectory
        )
        let sourceRoot = runtimeRoot.appending(path: "Source", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try Data("fixture".utf8).write(
            to: sourceRoot.appending(path: "fixture.txt", directoryHint: .notDirectory)
        )
        defer { try? FileManager.default.removeItem(at: runtimeRoot) }

        let session = try HanlinScriptingApplicationSession(
            installedPackageID: packageID,
            program: #"""
            Storage.clear();
            Storage.set("record", { count: 3 });
            Storage.setData("bytes", Data.fromIntArray([0, 127, 255]));
            const directory = Path.join(FileManager.documentsDirectory, "nested");
            const file = Path.join(directory, "note.txt");
            FileManager.createDirectorySync(directory, true);
            FileManager.writeAsStringSync(file, "שלום");
            FileManager.appendTextSync(file, "!");
            const result = [
              Path.basename(file),
              Path.dirname(file),
              FileManager.readAsStringSync(file),
              FileManager.statSync(file).type,
              String(Storage.get("record").count),
              Storage.getData("bytes").toHexString(),
              FileManager.readAsStringSync(Path.join(FileManager.scriptsDirectory, "fixture.txt"))
            ].join("|");
            Navigation.present({ element: createElement(Text, null, result) });
            """#,
            filename: "compiled/index.js",
            storageAllowed: true,
            filesAllowed: true,
            runtimeRoot: runtimeRoot,
            packageSourceDirectory: sourceRoot
        )
        #expect(
            session.model.root.properties["text"]
                == .string("note.txt|/documents/nested|שלום!|file|3|007fff|fixture")
        )
        session.dismiss()
    }

    @MainActor
    @Test("Enforces files capability before package filesystem access")
    func deniedFiles() throws {
        let packageID = try HanlinInstalledPackageID(
            validating: "install-files-denied-\(UUID().uuidString.lowercased())"
        )
        do {
            _ = try HanlinScriptingApplicationSession(
                installedPackageID: packageID,
                program: #"FileManager.existsSync(FileManager.documentsDirectory); Navigation.present({ element: createElement(Text, null, "No") });"#,
                filename: "compiled/index.js",
                storageAllowed: false,
                filesAllowed: false
            )
            Issue.record("FileManager was available without the files capability")
        } catch {
            // Expected: denied synchronous filesystem access aborts launch.
        }
    }

    @MainActor
    @Test("Resolves fetch and FileManager promises through the native callback bridge")
    func asynchronousNativeCallbacks() async throws {
        let packageID = try HanlinInstalledPackageID(
            validating: "install-async-\(UUID().uuidString.lowercased())"
        )
        let runtimeRoot = FileManager.default.temporaryDirectory.appending(
            path: "hanlin-async-\(UUID().uuidString.lowercased())",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: runtimeRoot) }
        let session = try HanlinScriptingApplicationSession(
            installedPackageID: packageID,
            program: #"""
            function App() {
              const [result, setResult] = useState("pending");
              useEffect(() => {
                const file = Path.join(FileManager.documentsDirectory, "async.txt");
                FileManager.writeAsString(file, "bridge")
                  .then(() => FileManager.readAsString(file))
                  .then(text => fetch("https://example.test/value").then(response => response.json())
                    .then(body => setResult(text + ":" + body.ok)))
                  .catch(error => setResult(error.name + ":" + error.code));
              }, []);
              return createElement(Text, null, result);
            }
            Navigation.present({ element: createElement(App, null) });
            """#,
            filename: "compiled/index.js",
            storageAllowed: false,
            filesAllowed: true,
            networkAllowed: true,
            runtimeRoot: runtimeRoot,
            networkLoader: { request in
                #expect(request.url == "https://example.test/value")
                return HanlinScriptingFetchResponse(
                    url: request.url,
                    status: 200,
                    headers: ["content-type": "application/json"],
                    body: Data(#"{"ok":true}"#.utf8)
                )
            }
        )
        #expect(session.model.root.properties["text"] == .string("pending"))
        for _ in 0..<50 where session.model.root.properties["text"] != .string("bridge:true") {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(session.model.root.properties["text"] == .string("bridge:true"))
        session.dismiss()
    }
}

@Suite("Trusted Scripting worker routes", .serialized)
struct HanlinTrustedWorkerRouteTests {
    @Test("NodeMobile worker registers and invokes multiple typed tools")
    func nodeWorkerInvocation() async throws {
        let session = try HanlinNodeWorkerSession(
            identifier: "test-node-\(UUID().uuidString.lowercased())"
        )
        defer { Task { await session.dispose() } }
        try await session.loadProgram(
            #"""
            AssistantTool.registerExecuteTool((parameters) => ({
              success: true,
              message: `node:${parameters.value}`
            }));
            AssistantTool.registerExecuteTool((parameters) => ({
              success: true,
              message: "node-second",
              data: { received: parameters.value }
            }));
            """#,
            filename: "assistant_tool.js",
            expectedToolCount: 2
        )
        let result = try await session.invoke(
            toolIndex: 1,
            parameters: .object(["value": .string("typed")])
        )
        guard case let .object(fields) = result,
              case let .bool(success)? = fields["success"],
              case let .object(data)? = fields["data"],
              case let .string(received)? = data["received"] else {
            Issue.record("Node worker result did not cross the canonical bridge")
            return
        }
        #expect(success)
        #expect(received == "typed")
    }

    @Test("Python worker exposes the scripting compatibility module")
    func pythonWorkerInvocation() async throws {
        let session = try HanlinPythonWorkerSession(
            identifier: "test-python-\(UUID().uuidString.lowercased())"
        )
        defer { Task { await session.dispose() } }
        try await session.loadProgram(
            #"""
            from scripting import AssistantTool

            @AssistantTool.register_execute_tool
            def execute(parameters):
                return {
                    "success": True,
                    "message": "python:" + parameters["value"],
                    "data": {"received": parameters["value"]}
                }
            """#,
            filename: "assistant_tool.py",
            expectedToolCount: 1
        )
        let result = try await session.invoke(
            toolIndex: 0,
            parameters: .object(["value": .string("typed")])
        )
        guard case let .object(fields) = result,
              case let .string(message)? = fields["message"] else {
            Issue.record("Python worker result did not cross the canonical bridge")
            return
        }
        #expect(message == "python:typed")
    }
}

@Suite("Isolated QuickJS engine", .serialized)
struct HanlinQuickJSEngineTests {
    @Test("Preserves canonical number, negative-zero, Unicode-key, and nested semantics")
    func canonicalBridgeSemantics() async throws {
        let session = try await session(program: #"""
        AssistantTool.registerExecuteTool(async (parameters) => {
          const unicodeKeys = Object.keys(parameters.unicode);
          const valid = typeof parameters.integer === "bigint"
            && parameters.integer === 1n
            && typeof parameters.number === "number"
            && parameters.number === 1
            && Object.is(parameters.negativeZero, -0)
            && parameters.flags[0] === null
            && parameters.flags[1] === false
            && parameters.flags[2] === true
            && unicodeKeys.length === 2;
          return { success: valid, message: unicodeKeys.join("|") };
        });
        """#)
        let unicode = try HanlinObject(uniqueMembers: [
            (key: "é", value: HanlinValue.string("composed")),
            (key: "e\u{301}", value: HanlinValue.string("decomposed"))
        ])
        let result = try await session.invoke(parameters: .object([
            "flags": .array([.null, .bool(false), .bool(true)]),
            "integer": .integer(1),
            "negativeZero": .number(-0.0),
            "number": .number(1.0),
            "unicode": .object(unicode)
        ]))
        let fields = try resultFields(result)
        #expect(fields.success)
        #expect(fields.message.contains("é"))
        #expect(fields.message.contains("e\u{301}"))
    }

    @Test("Keeps package globals isolated and supports repeated session state")
    func packageIsolationAndRepeatedExecution() async throws {
        let first = try await session(program: #"""
        globalThis.packageMarker = "package-a";
        let count = { value: 0 };
        AssistantTool.registerExecuteTool(() => ({
          success: true,
          message: `${globalThis.packageMarker}:${++count.value}`
        }));
        """#)
        let second = try await session(program: #"""
        AssistantTool.registerExecuteTool(() => ({
          success: true,
          message: typeof globalThis.packageMarker
        }));
        """#)

        let firstResult = try await first.invoke(parameters: .object([:]))
        let repeatedResult = try await first.invoke(parameters: .object([:]))
        let isolatedResult = try await second.invoke(parameters: .object([:]))
        #expect(try resultFields(firstResult).message == "package-a:1")
        #expect(try resultFields(repeatedResult).message == "package-a:2")
        #expect(try resultFields(isolatedResult).message == "undefined")
    }

    @Test("Routes multiple registered tools and preserves structured results")
    func multipleToolsAndStructuredResults() async throws {
        let session = try await session(
            program: #"""
            AssistantTool.registerExecuteTool((parameters) => ({
              success: true,
              message: `first:${parameters.value}`
            }));
            AssistantTool.registerExecuteTool((parameters) => ({
              success: true,
              message: "second",
              data: { received: parameters.value, items: [1n, true] }
            }));
            """#,
            expectedToolCount: 2
        )

        let first = try await session.invoke(
            toolIndex: 0,
            parameters: .object(["value": .string("one")])
        )
        let second = try await session.invoke(
            toolIndex: 1,
            parameters: .object(["value": .string("two")])
        )
        #expect(try resultFields(first).message == "first:one")
        guard case let .object(secondMembers) = second,
              case let .object(data)? = secondMembers["data"],
              case let .string(received)? = data["received"] else {
            Issue.record("Structured Script tool result was not preserved")
            return
        }
        #expect(received == "two")
    }

    @Test("Exposes no ambient host capabilities")
    func defaultDenyHostSurface() async throws {
        let session = try await session(program: #"""
        AssistantTool.registerExecuteTool(() => {
          const unavailable = [
            typeof process,
            typeof require,
            typeof fetch,
            typeof std,
            typeof os
          ];
          return { success: unavailable.every((value) => value === "undefined"), message: unavailable.join("|") };
        });
        """#)
        let fields = try resultFields(await session.invoke(parameters: .object([:])))
        #expect(fields.success)
        #expect(fields.message == "undefined|undefined|undefined|undefined|undefined")
    }

    @Test("Converts exceptions, unsupported values, cycles, and binary input to typed failures")
    func typedBridgeAndRuntimeFailures() async throws {
        let throwing = try await session(program: #"""
        AssistantTool.registerExecuteTool(() => { throw new Error("fixture failure"); });
        """#)
        await expectScriptingFailure {
            _ = try await throwing.invoke(parameters: .object([:]))
        }

        let invalidResult = try await session(program: #"""
        AssistantTool.registerExecuteTool(() => {
          const result = { success: true, message: "cycle", extra: null };
          result.extra = result;
          return result;
        });
        """#)
        await expectScriptingFailure {
            _ = try await invalidResult.invoke(parameters: .object([:]))
        }

        let echo = try await session(program: #"""
        AssistantTool.registerExecuteTool(() => ({ success: true, message: "unused" }));
        """#)
        await expectScriptingFailure(expected: .invalidBridgeValue("binary_unsupported")) {
            _ = try await echo.invoke(parameters: .data(Data([0, 1, 2])))
        }
    }

    @Test("Maps engine timeout to the typed timeout failure")
    func executionTimeout() async throws {
        let timeoutSession = try await session(
            program: "AssistantTool.registerExecuteTool(() => { while (true) {} });",
            configuration: .init(
                memoryLimitBytes: 8 * 1_048_576,
                stackLimitBytes: 256 * 1_024,
                timeoutMilliseconds: 20,
                maximumOutputBytes: 1_024
            )
        )
        await expectScriptingFailure(expected: .executionTimedOut) {
            _ = try await timeoutSession.invoke(parameters: .object([:]))
        }
    }

    @Test("Maps QuickJS null OOM recovery to the typed memory limit")
    func memoryLimit() async throws {
        let memorySession = try await session(
            program: #"""
            AssistantTool.registerExecuteTool(() => {
              const retained = [];
              while (true) retained.push("x".repeat(65536));
            });
            """#,
            configuration: .init(
                memoryLimitBytes: 8 * 1_048_576,
                stackLimitBytes: 256 * 1_024,
                timeoutMilliseconds: 2_000,
                maximumOutputBytes: 1_024
            )
        )
        await expectScriptingFailure(expected: .resourceLimit("engine_memory")) {
            _ = try await memorySession.invoke(parameters: .object([:]))
        }
    }

    @Test("Maps the locked QuickJS stack message to the typed stack limit")
    func stackLimit() async throws {
        let stackSession = try await session(
            program: #"AssistantTool.registerExecuteTool(() => { const recurse = () => recurse(); recurse(); });"#,
            configuration: .init(
                memoryLimitBytes: 8 * 1_048_576,
                stackLimitBytes: 128 * 1_024,
                timeoutMilliseconds: 2_000,
                maximumOutputBytes: 1_024
            )
        )
        await expectScriptingFailure(expected: .resourceLimit("engine_stack")) {
            _ = try await stackSession.invoke(parameters: .object([:]))
        }
    }

    @Test("Rejects results larger than the configured output limit")
    func outputLimit() async throws {
        let outputSession = try await session(
            program: #"""
            AssistantTool.registerExecuteTool(() => ({
              success: true,
              message: "x".repeat(2048)
            }));
            """#,
            configuration: .init(
                memoryLimitBytes: 16 * 1_048_576,
                stackLimitBytes: 256 * 1_024,
                timeoutMilliseconds: 2_000,
                maximumOutputBytes: 256
            )
        )
        await expectScriptingFailure(expected: .resourceLimit("output_size")) {
            _ = try await outputSession.invoke(parameters: .object([:]))
        }
    }

    @Test("Cancellation takes precedence over the execution deadline")
    func cancellation() async throws {
        let cancellationSession = try await session(
            program: "AssistantTool.registerExecuteTool(() => { while (true) {} });",
            configuration: .init(
                memoryLimitBytes: 8 * 1_048_576,
                stackLimitBytes: 256 * 1_024,
                timeoutMilliseconds: 30_000,
                maximumOutputBytes: 1_024
            )
        )
        let task = Task {
            try await cancellationSession.invoke(parameters: .object([:]))
        }
        await cancellationSession.waitUntilInvocationStarted()
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Cancelled Script unexpectedly completed")
        } catch let error as HanlinScriptingError {
            #expect(error == .cancelled)
        } catch {
            Issue.record("Cancellation escaped the typed Scripting boundary")
        }
    }

    @Test("Disposed sessions reject subsequent invocations")
    func disposal() async throws {
        let disposedSession = try await session(
            program: "AssistantTool.registerExecuteTool(() => ({ success: true, message: 'unused' }));"
        )
        await disposedSession.dispose()
        await expectScriptingFailure(
            expected: .unavailableProvider("disposed_session")
        ) {
            _ = try await disposedSession.invoke(parameters: .object([:]))
        }
    }

    private func session(
        program: String,
        configuration: HanlinQuickJSSession.Configuration = .phase2A,
        expectedToolCount: Int = 1
    ) async throws -> HanlinQuickJSSession {
        let session = try HanlinQuickJSSession(configuration: configuration)
        try await session.loadProgram(
            program,
            filename: "fixture.js",
            expectedToolCount: expectedToolCount
        )
        return session
    }

    private func resultFields(
        _ value: HanlinValue
    ) throws -> (success: Bool, message: String) {
        guard case let .object(members) = value,
              case let .bool(success)? = members["success"],
              case let .string(message)? = members["message"] else {
            throw HanlinScriptingError.invalidBridgeValue("test_result")
        }
        return (success, message)
    }

    private func expectScriptingFailure(
        expected: HanlinScriptingError? = nil,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            Issue.record("Script operation unexpectedly succeeded")
        } catch let error as HanlinScriptingError {
            if let expected {
                #expect(error == expected)
            }
        } catch {
            Issue.record("Failure escaped the typed Scripting boundary")
        }
    }
}

private func bundledFixtureDirectory(_ name: String) throws -> URL {
    let bundle = Bundle(for: HanlinScriptingFixtureMarker.self)
    let roots = [
        bundle.url(
            forResource: "ScriptingFixtures",
            withExtension: "bundle",
            subdirectory: "Fixtures"
        ),
        bundle.url(forResource: "ScriptingFixtures", withExtension: "bundle")
    ].compactMap { $0 }
    guard let root = roots.first(where: {
        FileManager.default.fileExists(atPath: $0.path())
    }) else {
        throw HanlinScriptingError.unavailableProvider("fixture_bundle_missing")
    }
    let directory = root.appending(path: name, directoryHint: .isDirectory)
    guard FileManager.default.fileExists(atPath: directory.path()) else {
        throw HanlinScriptingError.unavailableProvider("fixture_missing_\(name)")
    }
    return directory
}

private func materializedFixtureDirectory(_ name: String) throws -> URL {
    let source = try bundledFixtureDirectory(name)
    let destination = FileManager.default.temporaryDirectory.appending(
        path: "hanlin-script-fixture-\(UUID().uuidString.lowercased())",
        directoryHint: .isDirectory
    )
    try FileManager.default.copyItem(at: source, to: destination)
    return destination
}

private final class HanlinScriptingFixtureMarker: NSObject {}

private func materializedPackageCopy(named name: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appending(
        path: "hanlin-script-\(name)-\(UUID().uuidString.lowercased())",
        directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false
    )
    let source = try bundledFixtureDirectory("ValidEcho")
    for filename in ["assistant_tool.ts", "assistant_tool.js", "hanlin-script.json"] {
        try FileManager.default.copyItem(
            at: source.appending(path: filename, directoryHint: .notDirectory),
            to: directory.appending(path: filename, directoryHint: .notDirectory)
        )
    }
    return directory
}

private func materializedMalformedPackage() throws -> URL {
    let fixtureRoot = try bundledFixtureDirectory("MalformedManifest")
    let source = fixtureRoot.appending(
        path: "malformed-hanlin-script.json",
        directoryHint: .notDirectory
    )
    let directory = FileManager.default.temporaryDirectory.appending(
        path: "hanlin-malformed-script-\(UUID().uuidString.lowercased())",
        directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false
    )
    try FileManager.default.copyItem(
        at: source,
        to: directory.appending(path: "hanlin-script.json", directoryHint: .notDirectory)
    )
    return directory
}

private struct ProductionCompilerAuthority {
    let analyzer: HanlinScriptAnalyzer
    let bundler: HanlinScriptingBundler
}

private struct ProductionCompilerExpectation: Decodable {
    let expected: String
}

private func productionCompilerAuthority() throws -> ProductionCompilerAuthority {
    let metadata = try HanlinScriptingSDK.metadata()
    let inventory = HanlinCompatibilityInventory(
        baselineID: metadata.baselineID,
        baselineDigest: metadata.baselineDigest,
        symbols: try metadata.records.map { record in
            .init(
                symbol: record.symbol,
                state: record.state,
                requiredCapability: try record.capability.map(HanlinCapabilityID.init(validating:)),
                allowedContexts: record.contexts.contains("all")
                    ? Set(HanlinExecutionContext.allCases)
                    : Set(record.contexts.compactMap(HanlinExecutionContext.init(rawValue:)))
            )
        }
    )
    return ProductionCompilerAuthority(
        analyzer: HanlinScriptAnalyzer(inventory: inventory),
        bundler: HanlinScriptingBundler(
            baseline: inventory,
            abiVersion: HanlinScriptContractSupport.multiRuntime.abiVersion.description,
            scriptingDeclarations: try HanlinScriptingSDK.declarationFiles().map {
                HanlinVirtualSourceFile(
                    logicalPath: "virtual/\($0.name)",
                    bytes: $0.data
                )
            },
            compiler: HanlinNodeMobileScriptingCompiler()
        )
    )
}

private func productionCompilerFixtures(expected: String) throws -> [URL] {
    let root = try bundledFixtureDirectory("ProductionCompilerCorpus")
    return try FileManager.default.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    ).filter { fixture in
        guard fixture.hasDirectoryPath else { return false }
        let expectationURL = fixture.appending(
            path: "compiler-acceptance.json",
            directoryHint: .notDirectory
        )
        let expectation = try JSONDecoder().decode(
            ProductionCompilerExpectation.self,
            from: Data(contentsOf: expectationURL)
        )
        return expectation.expected == expected
    }.sorted { $0.lastPathComponent < $1.lastPathComponent }
}

private func productionCompilerFixture(named name: String) throws -> URL {
    let fixture = try bundledFixtureDirectory("ProductionCompilerCorpus").appending(
        path: name,
        directoryHint: .isDirectory
    )
    guard FileManager.default.fileExists(atPath: fixture.path()) else {
        throw HanlinScriptingError.unavailableProvider("production_fixture_missing_\(name)")
    }
    return fixture
}

private func stagedProductionCompilerFixture(_ source: URL) throws -> HanlinStagedPackage {
    let stagingRoot = FileManager.default.temporaryDirectory.appending(
        path: "hanlin-production-compiler-\(UUID().uuidString.lowercased())",
        directoryHint: .isDirectory
    )
    let packageRoot = stagingRoot.appending(path: "package", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: stagingRoot, withIntermediateDirectories: false)
    do {
        try FileManager.default.copyItem(at: source, to: packageRoot)
        let manifestData = try Data(contentsOf: packageRoot.appending(path: "script.json"))
        let manifest = try JSONDecoder().decode(HanlinScriptingManifest.self, from: manifestData)
        let files = FileManager.default.enumerator(
            at: packageRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )?.compactMap { $0 as? URL } ?? []
        let regularFiles = try files.filter {
            try $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
        }
        let byteCount = try regularFiles.reduce(Int64(0)) { partial, url in
            partial + Int64(try Data(contentsOf: url).count)
        }
        return HanlinStagedPackage(
            source: .init(
                originalFileName: "\(source.lastPathComponent).scripting",
                format: .scripting,
                contentSHA256: String(repeating: "d", count: 64),
                byteCount: byteCount,
                importedAt: Date(timeIntervalSince1970: 1)
            ),
            stagingRoot: stagingRoot,
            archiveURL: stagingRoot.appending(path: "fixture.scripting"),
            packageRoot: packageRoot,
            inspection: .init(
                fileCount: regularFiles.count,
                directoryCount: 1,
                compressedBytes: byteCount,
                uncompressedBytes: byteCount,
                maximumDepth: 3,
                manifestPath: "script.json"
            ),
            manifest: manifest
        )
    } catch {
        try? FileManager.default.removeItem(at: stagingRoot)
        throw error
    }
}

private func physicalIPadArchiveFixture() throws -> URL {
    let fixture = try bundledFixtureDirectory("PhysicalIPad").appending(
        path: "smart-eating-normalized.zip",
        directoryHint: .notDirectory
    )
    guard FileManager.default.fileExists(atPath: fixture.path()) else {
        throw HanlinScriptingError.unavailableProvider("physical_ipad_archive_missing")
    }
    return fixture
}

private struct PhysicalIPadArtifactPaths: Codable {
    let checkpoint: String
    let packageID: String
    let runtimeKinds: [String]
    let activeGeneration: UInt64
    let availableGenerations: [UInt64]
    let platformRoot: String
    let standardizedPlatformRoot: String
    let symlinkResolvedPlatformRoot: String
    let installRoot: String
    let packageRoot: String
    let artifactRoot: String
    let artifactManifestURL: String
    let artifactManifestExists: Bool
    let artifactManifestParentExists: Bool
    let entrypoints: [String]
    let importStagingEntries: [String]
    let storeStagingEntries: [String]
}

private func writePhysicalIPadEvidence(
    checkpoint: String,
    evidenceRoot: URL,
    platformRoot: URL,
    package: HanlinStoredPackageSnapshot
) throws {
    let manager = FileManager.default
    let installRoot = platformRoot.appending(path: "Installed", directoryHint: .isDirectory)
    let packageRoot = installRoot.appending(
        path: "packages/\(package.record.installedPackageID.rawValue)",
        directoryHint: .isDirectory
    )
    let artifactRoot = packageRoot.appending(
        path: "generations/\(package.record.activeGeneration)",
        directoryHint: .isDirectory
    )
    let manifest = artifactRoot.appending(path: "artifact-manifest.json", directoryHint: .notDirectory)
    let payload = PhysicalIPadArtifactPaths(
        checkpoint: checkpoint,
        packageID: package.record.installedPackageID.rawValue,
        runtimeKinds: package.entrypoints.map(\.runtimeProfile.rawValue).sorted(),
        activeGeneration: package.record.activeGeneration,
        availableGenerations: package.availableGenerations,
        platformRoot: platformRoot.path(percentEncoded: false),
        standardizedPlatformRoot: platformRoot.standardizedFileURL.path(percentEncoded: false),
        symlinkResolvedPlatformRoot: platformRoot.resolvingSymlinksInPath().path(percentEncoded: false),
        installRoot: installRoot.path(percentEncoded: false),
        packageRoot: packageRoot.path(percentEncoded: false),
        artifactRoot: artifactRoot.path(percentEncoded: false),
        artifactManifestURL: manifest.path(percentEncoded: false),
        artifactManifestExists: manager.fileExists(atPath: manifest.path()),
        artifactManifestParentExists: manager.fileExists(atPath: artifactRoot.path()),
        entrypoints: package.entrypoints.map(\.sourcePath).sorted(),
        importStagingEntries: try directoryNames(
            at: platformRoot.appending(path: "ImportStaging", directoryHint: .isDirectory)
        ),
        storeStagingEntries: try directoryNames(
            at: installRoot.appending(path: "staging", directoryHint: .isDirectory)
        )
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(payload).write(
        to: evidenceRoot.appending(path: "artifact-paths-\(checkpoint).json"),
        options: .atomic
    )

    let registry = installRoot.appending(path: "registry/catalog.json", directoryHint: .notDirectory)
    if manager.fileExists(atPath: registry.path()) {
        try manager.copyItem(
            at: registry,
            to: evidenceRoot.appending(path: "registry-\(checkpoint).json")
        )
    }
    let tree = try filesystemTree(root: platformRoot)
    try Data(tree.utf8).write(
        to: evidenceRoot.appending(path: "filesystem-\(checkpoint).txt"),
        options: .atomic
    )
}

private func directoryNames(at directory: URL) throws -> [String] {
    guard FileManager.default.fileExists(atPath: directory.path()) else { return [] }
    return try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
    ).map(\.lastPathComponent).sorted()
}

private func filesystemTree(root: URL) throws -> String {
    guard let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .isSymbolicLinkKey],
        options: [.skipsHiddenFiles]
    ) else { return "<unreadable>\n" }
    let rootPath = root.path(percentEncoded: false)
    let records = try enumerator.compactMap { item -> String? in
        guard let url = item as? URL else { return nil }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .isSymbolicLinkKey])
        let relative = String(url.path(percentEncoded: false).dropFirst(rootPath.count + 1))
        let kind = values.isSymbolicLink == true ? "symlink" : (values.isDirectory == true ? "directory" : "file")
        return "\(kind)\t\(values.fileSize ?? 0)\t\(relative)"
    }
    return records.sorted().joined(separator: "\n") + "\n"
}
