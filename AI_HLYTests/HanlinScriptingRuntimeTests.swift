import Foundation
import HanlinPlatformContracts
import Testing
@testable import AI_Hanlin

@Suite("Hanlin Scripting Phase 2A acceptance", .serialized)
struct HanlinScriptingAcceptanceTests {
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
