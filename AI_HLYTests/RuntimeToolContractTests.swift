import Foundation
import Testing
@testable import AI_Hanlin

@MainActor
@Suite("Runtime Tool Contracts", .serialized)
struct RuntimeToolContractTests {
    @Test func preparedSchemasHaveUniqueAliasesRoutesAndValidObjectContracts() async throws {
        let prepared = try await AssistantToolBridge.prepare(scope: .nativeOnly)
        let schemas = prepared.schemas
        #expect(!schemas.isEmpty)

        var aliases: [String] = []
        var logicalRoutes: [String] = []
        for schema in schemas {
            #expect(schema["type"] as? String == "function")
            let function = try #require(schema["function"] as? [String: Any])
            let alias = try #require(function["name"] as? String)
            let description = try #require(function["description"] as? String)
            let parameters = try #require(function["parameters"] as? [String: Any])
            let properties = try #require(parameters["properties"] as? [String: Any])
            let required = parameters["required"] as? [String] ?? []
            #expect(!alias.isEmpty)
            #expect(!description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(parameters["type"] as? String == "object")
            #expect(Set(required).isSubset(of: Set(properties.keys)))
            if let additionalProperties = parameters["additionalProperties"] {
                #expect(additionalProperties is Bool)
            }

            aliases.append(alias)
            let resolution = try #require(prepared.authority.resolution(alias: alias))
            logicalRoutes.append(
                "\(resolution.route.logicalToolID.providerInstanceID.rawValue)|\(resolution.route.logicalToolID.localToolID.rawValue)"
            )
        }

        #expect(Set(aliases).count == aliases.count)
        #expect(Set(logicalRoutes).count == logicalRoutes.count)
        #expect(prepared.authority.backendRoutes.count == schemas.count)
        #expect(prepared.authority.catalog.entries.count == schemas.count)
        #expect(!aliases.contains("execute_python_code"))
    }

    @Test func localAndRemotePythonAreUnambiguous() throws {
        let localSchema = ExecuteLocalPythonTool().openAIToolSchema()
        let localFunction = try #require(localSchema["function"] as? [String: Any])
        #expect(localFunction["name"] as? String == "execute_local_python_code")
        let localDescription = try #require(localFunction["description"] as? String)
        #expect(localDescription.localizedCaseInsensitiveContains("on this device"))
        #expect(localDescription.localizedCaseInsensitiveContains("Piston"))

        let legacySchemas = buildMemoryTools(
            memoryEnabled: false,
            mapEnabled: false,
            calendarEnabled: false,
            searchEnabled: false,
            knowledgeEnabled: false,
            codeEnabled: true,
            healthEnabled: false,
            weatherEnabled: false,
            canvasEnabled: false
        )
        let names = legacySchemas.compactMap(Self.functionName)
        #expect(names.contains("execute_remote_python_code"))
        #expect(!names.contains("execute_python_code"))
        #expect(Set(names + ["execute_local_python_code"]).count == names.count + 1)

        let remote = try #require(
            legacySchemas.first(where: { Self.functionName($0) == "execute_remote_python_code" })?["function"]
                as? [String: Any]
        )
        let remoteDescription = try #require(remote["description"] as? String)
        #expect(remoteDescription.localizedCaseInsensitiveContains("remote"))
        #expect(remoteDescription.localizedCaseInsensitiveContains("network"))
        let parameters = try #require(remote["parameters"] as? [String: Any])
        #expect(parameters["additionalProperties"] as? Bool == false)
    }

    @Test func shellSchemaIsStructurallyConstrained() throws {
        let schema = ExecuteShellCommandTool().openAIToolSchema()
        let function = try #require(schema["function"] as? [String: Any])
        let parameters = try #require(function["parameters"] as? [String: Any])
        let properties = try #require(parameters["properties"] as? [String: Any])
        let program = try #require(properties["program"] as? [String: Any])
        let advertised = try #require(program["enum"] as? [String])

        #expect(parameters["additionalProperties"] as? Bool == false)
        #expect(parameters["required"] as? [String] == ["program"])
        #expect(properties["command"] == nil)
        #expect(Set(advertised) == Set(ShellRuntimeService.capabilities.map(\.name)))
        #expect(advertised.count == 23)
        #expect(!advertised.contains("echo"))
        #expect(!advertised.contains("date"))
    }

    @Test func runtimeSchemasAdvertiseOnlyHandledParameters() throws {
        try assertParameters(
            ExecuteLocalPythonTool().openAIToolSchema(),
            properties: ["source", "arguments", "timeout_seconds"],
            required: ["source"]
        )
        try assertParameters(
            ExecuteJavaScriptTool().openAIToolSchema(),
            properties: ["source", "runtime", "arguments", "timeout_seconds"],
            required: ["source"]
        )
        try assertParameters(
            ExecuteTypeScriptTool().openAIToolSchema(),
            properties: ["source", "file_name", "compile_only", "timeout_seconds"],
            required: ["source"]
        )
        try assertParameters(
            ExecuteShellCommandTool().openAIToolSchema(),
            properties: ["program", "arguments", "allow_network"],
            required: ["program"]
        )
    }

    @Test func runtimeToolsRejectMalformedArgumentsSemantically() async {
        let context = NativeToolExecutionContext(localeIdentifier: "en")

        let unknown = await ExecuteLocalPythonTool().execute(
            argumentsJSON: #"{"source":"print(1)","surprise":true}"#,
            context: context
        )
        #expect(unknown.outcome == .invalidArguments)

        let wrongType = await ExecuteLocalPythonTool().execute(
            argumentsJSON: #"{"source":42}"#,
            context: context
        )
        #expect(wrongType.outcome == .invalidArguments)

        let invalidTimeout = await ExecuteLocalPythonTool().execute(
            argumentsJSON: #"{"source":"print(1)","timeout_seconds":0}"#,
            context: context
        )
        #expect(invalidTimeout.outcome == .invalidArguments)

        let invalidRuntime = await ExecuteJavaScriptTool().execute(
            argumentsJSON: #"{"source":"1 + 1","runtime":"browser"}"#,
            context: context
        )
        #expect(invalidRuntime.outcome == .invalidArguments)

        let unsupportedJSTimeout = await ExecuteJavaScriptTool().execute(
            argumentsJSON: #"{"source":"1 + 1","runtime":"jscore","timeout_seconds":1}"#,
            context: context
        )
        #expect(unsupportedJSTimeout.outcome == .invalidArguments)

        let unsupportedShell = await ExecuteShellCommandTool().execute(
            argumentsJSON: #"{"program":"echo","arguments":["hello"]}"#,
            context: context
        )
        #expect(unsupportedShell.outcome == .invalidArguments)
    }

    @Test func strictJSONScalarsDistinguishOneFromTrue() throws {
        let arguments = try NativeToolJSON.dictionary(
            from: #"{"one":1,"enabled":true}"#
        )

        #expect(try NativeToolJSON.strictInt(arguments, "one", default: 30) == 1)
        #expect(try NativeToolJSON.strictBool(arguments, "enabled"))
        #expect(throws: NativeToolJSON.JSONError.self) {
            try NativeToolJSON.strictInt(arguments, "enabled", default: 30)
        }
        #expect(throws: NativeToolJSON.JSONError.self) {
            try NativeToolJSON.strictBool(arguments, "one")
        }
    }

    @Test func javaScriptCoreExpressionValueReachesModel() async {
        let availability = RuntimeAvailabilityStore.shared
        let original = availability.isAvailable(.javaScriptCore)
        defer { availability.setAvailable(original, for: .javaScriptCore) }
        availability.setAvailable(true, for: .javaScriptCore)

        let result = await ExecuteJavaScriptTool().execute(
            argumentsJSON: #"{"source":"6 * 7","runtime":"jscore"}"#,
            context: NativeToolExecutionContext(localeIdentifier: "en")
        )

        #expect(result.outcome == .succeeded)
        #expect(result.modelText.contains("42"))
        #expect(result.diagnostics.runtimeKind == RuntimeKind.javaScriptCore.rawValue)
        #expect(result.diagnostics.valueType == "number")
    }

    @Test func diagnosticsCountSemanticFailureInsideCompletedRun() async throws {
        let recorder = try #require(
            await AgentDiagnosticsRecorder.start(
                runID: UUID(),
                groupID: UUID(),
                providerID: "acceptance-fixture",
                modelID: "deterministic"
            )
        )
        let request = try JSONSerialization.data(withJSONObject: [
            "messages": [["role": "user", "content": "recover after failure"]],
            "tools": []
        ])
        let roundID = await recorder.beginRound(index: 1, trigger: "acceptance", requestData: request)
        let call = AgentToolCall.parse(
            id: "call-failed-shell",
            name: "execute_shell_command",
            argumentsJSON: #"{"program":"echo","arguments":["no"]}"#
        )
        await recorder.recordToolCall(roundID: roundID, call: call)
        await recorder.completeToolCall(
            roundID: roundID,
            callID: call.id,
            resultForModel: "Unsupported command",
            resultForUser: "Unsupported command",
            duration: 0.01,
            outcome: .invalidArguments,
            diagnostics: NativeToolExecutionDiagnostics(
                canonicalLogicalToolID: "native|execute_shell_command",
                modelFacingAlias: "execute_shell_command",
                backendRoute: "native:runtime:execute_shell_command",
                source: "native",
                runtimeKind: RuntimeKind.shell.rawValue,
                failureCategory: NativeToolExecutionOutcome.invalidArguments.rawValue,
                argumentKeys: ["arguments", "program"]
            ),
            error: "Unsupported command"
        )
        await recorder.finishRound(roundID: roundID, finishReason: "tool_calls", usage: nil)
        await recorder.complete(status: "completed")

        let session = await recorder.session
        #expect(session.status == "completed")
        #expect(session.efficiency.toolCallCount == 1)
        #expect(session.efficiency.failedToolCount == 1)
        #expect(session.efficiency.invalidArgumentToolCount == 1)
        #expect(session.efficiency.succeededToolCount == 0)
        #expect(session.rounds.first?.toolCalls.first?.outcome == "invalidArguments")
    }

    @Test func diagnosticsTerminalStateIsIdempotent() async throws {
        // complete -> fail => stays completed
        let r1 = try #require(await AgentDiagnosticsRecorder.start(runID: UUID(), groupID: UUID(), providerID: "test", modelID: "test"))
        await r1.complete(status: "completed")
        await r1.complete(status: "failed", error: "late error")
        let s1 = await r1.session
        #expect(s1.status == "completed")
        #expect(s1.isComplete)

        // fail -> complete => stays failed
        let r2 = try #require(await AgentDiagnosticsRecorder.start(runID: UUID(), groupID: UUID(), providerID: "test", modelID: "test"))
        await r2.complete(status: "failed", error: "initial error")
        await r2.complete(status: "completed")
        let s2 = await r2.session
        #expect(s2.status == "failed")
        #expect(s2.isComplete)

        // complete -> complete => stays completed
        let r3 = try #require(await AgentDiagnosticsRecorder.start(runID: UUID(), groupID: UUID(), providerID: "test", modelID: "test"))
        await r3.complete(status: "completed")
        await r3.complete(status: "completed")
        let s3 = await r3.session
        #expect(s3.status == "completed")
        #expect(s3.isComplete)

        // cancel -> other end => stays cancelled
        let r4 = try #require(await AgentDiagnosticsRecorder.start(runID: UUID(), groupID: UUID(), providerID: "test", modelID: "test"))
        await r4.complete(status: "cancelled")
        await r4.complete(status: "completed")
        await r4.complete(status: "failed")
        let s4 = await r4.session
        #expect(s4.status == "cancelled")
        #expect(s4.isComplete)
    }

    @Test func diagnosticsRecordsStepMetadataWithoutSecrets() async throws {
        let recorder = try #require(await AgentDiagnosticsRecorder.start(runID: UUID(), groupID: UUID(), providerID: "openai", modelID: "gpt-4o"))
        let requestData = try JSONSerialization.data(withJSONObject: [
            "messages": [["role": "user", "content": "analyze data"]],
            "tools": []
        ])

        let roundID = await recorder.beginRound(
            index: 1,
            trigger: "initialUserRequest",
            requestData: requestData,
            loadedSkillIDs: ["data_analysis"],
            modelVisibleToolAliases: ["run_python", "tool_search"],
            modelVisibleToolCount: 2,
            modelVisibleSchemaBytes: 1024,
            providerID: "openai",
            modelID: "gpt-4o"
        )

        recorder.recordStreamEvent(roundID: roundID, visibleContent: "Processing", visibleReasoningSummary: "Thinking", isMeaningful: true)
        recorder.recordStreamEvent(roundID: roundID, visibleContent: nil, visibleReasoningSummary: nil, isMeaningful: false)

        await recorder.finishRound(roundID: roundID, finishReason: "stop", usage: nil, meaningfulEventCount: 1)
        await recorder.complete(status: "completed")

        let session = await recorder.session
        let round = try #require(session.rounds.first)
        #expect(round.index == 1)
        #expect(round.loadedSkillIDs == ["data_analysis"])
        #expect(round.modelVisibleToolAliases == ["run_python", "tool_search"])
        #expect(round.modelVisibleToolCount == 2)
        #expect(round.modelVisibleSchemaBytes == 1024)
        #expect(round.providerID == "openai")
        #expect(round.modelID == "gpt-4o")
        #expect(round.response.finishReason == "stop")
        #expect(round.meaningfulStreamEventCount == 1)
    }

    private static func functionName(_ schema: [String: Any]) -> String? {
        (schema["function"] as? [String: Any])?["name"] as? String
    }

    private func assertParameters(
        _ schema: [String: Any],
        properties expectedProperties: Set<String>,
        required expectedRequired: Set<String>
    ) throws {
        let function = try #require(schema["function"] as? [String: Any])
        let parameters = try #require(function["parameters"] as? [String: Any])
        let properties = try #require(parameters["properties"] as? [String: Any])
        #expect(Set(properties.keys) == expectedProperties)
        #expect(Set(parameters["required"] as? [String] ?? []) == expectedRequired)
        #expect(parameters["additionalProperties"] as? Bool == false)
    }
}
