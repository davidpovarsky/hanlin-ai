import Foundation
import HanlinPlatformContracts

actor HanlinNodeWorkerSession {
    private enum State: Equatable, Sendable {
        case stopped
        case ready
        case executing
        case disposed
    }

    private let runtime: NodeRuntimeService
    private let workspace: URL
    private var state = State.stopped
    private var program = ""
    private var expectedToolCount = 0
    private var activeExecutionID: UUID?

    init(
        identifier: String,
        runtime: NodeRuntimeService = AppRuntimeCore.shared.node,
        fileLayout: RuntimeFileLayout = .default
    ) throws {
        self.runtime = runtime
        workspace = try fileLayout.workspace(client: .scripting, identifier: identifier)
    }

    func loadProgram(_ source: String, filename _: String, expectedToolCount: Int) async throws {
        guard state != .disposed else {
            throw HanlinScriptingError.unavailableProvider("disposed_session")
        }
        guard !source.isEmpty, (1 ... 64).contains(expectedToolCount) else {
            throw HanlinScriptingError.invalidPackage("worker_program")
        }
        program = source
        self.expectedToolCount = expectedToolCount
        let inspection = source + "\nexport default globalThis.__hanlinToolCount();"
        let result = try await execute(inspection)
        guard case let .number(count)? = result.value,
              count == Double(expectedToolCount) else {
            state = .stopped
            throw HanlinScriptingError.exportedToolMissing("tool_count")
        }
        state = .ready
    }

    func invoke(toolIndex: Int, parameters: HanlinValue) async throws -> HanlinValue {
        guard state == .ready else {
            throw HanlinScriptingError.unavailableProvider("worker_session_not_ready")
        }
        guard (0 ..< expectedToolCount).contains(toolIndex) else {
            throw HanlinScriptingError.exportedToolMissing(String(toolIndex))
        }
        let input = HanlinValue.object([
            "__hanlinToolIndex": .integer(Int64(toolIndex)),
            "parameters": parameters,
        ])
        let canonicalInput = String(decoding: try input.canonicalJSONData(), as: UTF8.self)
        let inputLiteral = String(decoding: try JSONEncoder().encode(canonicalInput), as: UTF8.self)
        let invocation = program + "\nconst __hanlinWorkerResult = await globalThis.__hanlinInvoke(\(inputLiteral));\nexport default JSON.parse(__hanlinWorkerResult);"
        let result = try await execute(invocation)
        guard let value = result.value else {
            throw HanlinScriptingError.invalidBridgeValue("worker_result_missing")
        }
        do {
            return try HanlinValue.decodeCanonicalJSON(JSONEncoder().encode(value))
        } catch let error as HanlinScriptingError {
            throw error
        } catch {
            throw HanlinScriptingError.invalidBridgeValue("worker_result")
        }
    }

    func restart() async throws {
        let source = program
        let count = expectedToolCount
        state = .stopped
        try await loadProgram(source, filename: "worker.js", expectedToolCount: count)
    }

    func stop() async {
        if let activeExecutionID {
            await runtime.cancelExecution(id: activeExecutionID)
        }
        activeExecutionID = nil
        if state != .disposed { state = .stopped }
    }

    func dispose() async {
        await stop()
        program = ""
        expectedToolCount = 0
        state = .disposed
        try? FileManager.default.removeItem(at: workspace)
    }

    private func execute(_ source: String) async throws -> RuntimeExecutionResult {
        guard state != .disposed else {
            throw HanlinScriptingError.unavailableProvider("disposed_session")
        }
        let executionID = UUID()
        activeExecutionID = executionID
        state = .executing
        defer {
            activeExecutionID = nil
            if state != .disposed { state = .ready }
        }
        let request = RuntimeExecutionRequest(
            id: executionID,
            source: HanlinScriptValueBridge.bootstrap + "\n" + source,
            workspace: workspace,
            limits: .init(timeout: .seconds(30), maximumOutputBytes: 1_048_576)
        )
        let runtime = runtime
        do {
            let result = try await withTaskCancellationHandler {
                try await runtime.executeJavaScript(request)
            } onCancel: {
                Task { await runtime.cancelExecution(id: executionID) }
            }
            if Task.isCancelled || result.wasCancelled { throw HanlinScriptingError.cancelled }
            if result.didTimeOut { throw HanlinScriptingError.executionTimedOut }
            if result.outputWasTruncated { throw HanlinScriptingError.resourceLimit("output_size") }
            guard result.exitCode == 0 else {
                throw HanlinScriptingError.moduleEvaluationFailed("node_worker_failed")
            }
            return result
        } catch {
            throw Self.map(error)
        }
    }

    private static func map(_ error: Error) -> HanlinScriptingError {
        if let scriptingError = error as? HanlinScriptingError { return scriptingError }
        if error is CancellationError { return .cancelled }
        guard let runtimeError = error as? RuntimeCoreError else {
            return .moduleEvaluationFailed("node_worker_failed")
        }
        return switch runtimeError {
        case .executionTimedOut: .executionTimedOut
        case .executionCancelled: .cancelled
        case .outputLimitExceeded: .resourceLimit("output_size")
        case .runtimeUnavailable, .appRestartRequired: .runtimeInitializationFailed
        default: .moduleEvaluationFailed("node_worker_failed")
        }
    }
}

actor HanlinPythonWorkerSession {
    private enum State: Equatable, Sendable {
        case stopped
        case ready
        case executing
        case disposed
    }

    private let runtime: PythonRuntimeService
    private let workspace: URL
    private var state = State.stopped
    private var program = ""
    private var expectedToolCount = 0

    init(
        identifier: String,
        runtime: PythonRuntimeService = AppRuntimeCore.shared.python,
        fileLayout: RuntimeFileLayout = .default
    ) throws {
        self.runtime = runtime
        workspace = try fileLayout.workspace(client: .scripting, identifier: identifier)
    }

    func loadProgram(_ source: String, filename _: String, expectedToolCount: Int) async throws {
        guard state != .disposed else {
            throw HanlinScriptingError.unavailableProvider("disposed_session")
        }
        guard !source.isEmpty, (1 ... 64).contains(expectedToolCount) else {
            throw HanlinScriptingError.invalidPackage("worker_program")
        }
        program = source
        self.expectedToolCount = expectedToolCount
        let result = try await execute(source + "\n__hanlin_result__ = len(_hanlin_tools)")
        guard case let .number(count)? = result.value,
              count == Double(expectedToolCount) else {
            state = .stopped
            throw HanlinScriptingError.exportedToolMissing("tool_count")
        }
        state = .ready
    }

    func invoke(toolIndex: Int, parameters: HanlinValue) async throws -> HanlinValue {
        guard state == .ready else {
            throw HanlinScriptingError.unavailableProvider("worker_session_not_ready")
        }
        guard (0 ..< expectedToolCount).contains(toolIndex) else {
            throw HanlinScriptingError.exportedToolMissing(String(toolIndex))
        }
        let canonical = try parameters.canonicalJSONData().base64EncodedString()
        let source = program + "\n__hanlin_result__ = _hanlin_invoke(\(toolIndex), \"(canonical)\")"
        let result = try await execute(source)
        guard let value = result.value else {
            throw HanlinScriptingError.invalidBridgeValue("worker_result_missing")
        }
        do {
            return try HanlinValue.decodeCanonicalJSON(JSONEncoder().encode(value))
        } catch {
            throw HanlinScriptingError.invalidBridgeValue("worker_result")
        }
    }

    func restart() async throws {
        let source = program
        let count = expectedToolCount
        state = .stopped
        try await loadProgram(source, filename: "worker.py", expectedToolCount: count)
    }

    func stop() {
        if state != .disposed { state = .stopped }
    }

    func dispose() {
        stop()
        program = ""
        expectedToolCount = 0
        state = .disposed
        try? FileManager.default.removeItem(at: workspace)
    }

    private func execute(_ source: String) async throws -> RuntimeExecutionResult {
        guard state != .disposed else {
            throw HanlinScriptingError.unavailableProvider("disposed_session")
        }
        guard !Task.isCancelled else { throw HanlinScriptingError.cancelled }
        state = .executing
        defer { if state != .disposed { state = .ready } }
        do {
            let result = try await runtime.execute(.init(
                source: Self.bootstrap + "\n" + source,
                workspace: workspace,
                limits: .init(timeout: .seconds(30), maximumOutputBytes: 1_048_576)
            ))
            if Task.isCancelled || result.wasCancelled { throw HanlinScriptingError.cancelled }
            if result.didTimeOut { throw HanlinScriptingError.executionTimedOut }
            if result.outputWasTruncated { throw HanlinScriptingError.resourceLimit("output_size") }
            guard result.exitCode == 0 else {
                throw HanlinScriptingError.moduleEvaluationFailed("python_worker_failed")
            }
            return result
        } catch let error as HanlinScriptingError {
            throw error
        } catch is CancellationError {
            throw HanlinScriptingError.cancelled
        } catch let error as RuntimeCoreError {
            switch error {
            case .executionTimedOut: throw HanlinScriptingError.executionTimedOut
            case .executionCancelled: throw HanlinScriptingError.cancelled
            case .outputLimitExceeded: throw HanlinScriptingError.resourceLimit("output_size")
            case .runtimeUnavailable, .appRestartRequired:
                throw HanlinScriptingError.runtimeInitializationFailed
            default: throw HanlinScriptingError.moduleEvaluationFailed("python_worker_failed")
            }
        } catch {
            throw HanlinScriptingError.moduleEvaluationFailed("python_worker_failed")
        }
    }

    private static let bootstrap = #"""
    import base64 as _hanlin_base64
    import json as _hanlin_json
    import sys as _hanlin_sys

    _hanlin_tools = []

    def _hanlin_decode(value):
        kind = value.get("type")
        if kind == "null": return None
        if kind == "bool": return bool(value["value"])
        if kind == "integer": return int(value["value"])
        if kind == "number":
            import struct as _hanlin_struct
            return _hanlin_struct.unpack(">d", bytes.fromhex(value["value"]))[0]
        if kind == "string": return value["value"]
        if kind == "array": return [_hanlin_decode(item) for item in value["value"]]
        if kind == "object": return {key: _hanlin_decode(item) for key, item in value["value"].items()}
        raise TypeError("HANLIN_BRIDGE:unknown_tag")

    def _hanlin_encode(value):
        if value is None: return {"type": "null"}
        if isinstance(value, bool): return {"type": "bool", "value": value}
        if isinstance(value, int): return {"type": "integer", "value": str(value)}
        if isinstance(value, float):
            import math as _hanlin_math
            import struct as _hanlin_struct
            if not _hanlin_math.isfinite(value): raise TypeError("HANLIN_BRIDGE:non_finite_number")
            return {"type": "number", "value": _hanlin_struct.pack(">d", value).hex()}
        if isinstance(value, str): return {"type": "string", "value": value}
        if isinstance(value, list): return {"type": "array", "value": [_hanlin_encode(item) for item in value]}
        if isinstance(value, dict): return {"type": "object", "value": {str(key): _hanlin_encode(item) for key, item in value.items()}}
        raise TypeError("HANLIN_BRIDGE:unsupported_type")

    class _HanlinAssistantTool:
        @staticmethod
        def registerExecuteTool(execute):
            if not callable(execute): raise TypeError("HANLIN_BRIDGE:execute_not_callable")
            if len(_hanlin_tools) >= 64: raise RuntimeError("HANLIN_BRIDGE:tool_registration_limit")
            _hanlin_tools.append(execute)
            return execute

        register_execute_tool = registerExecuteTool

    class _HanlinScript:
        @staticmethod
        def exit(code=0):
            if code: raise RuntimeError("HANLIN_SCRIPT:exit_failure")

    _hanlin_scripting = type(_hanlin_sys)("scripting")
    _hanlin_scripting.AssistantTool = _HanlinAssistantTool
    _hanlin_scripting.Script = _HanlinScript
    _hanlin_sys.modules["scripting"] = _hanlin_scripting
    AssistantTool = _HanlinAssistantTool
    Script = _HanlinScript

    def _hanlin_invoke(index, canonical_base64):
        parameters = _hanlin_decode(_hanlin_json.loads(_hanlin_base64.b64decode(canonical_base64)))
        result = _hanlin_tools[index](parameters)
        if hasattr(result, "__await__"):
            import asyncio as _hanlin_asyncio
            result = _hanlin_asyncio.run(result)
        if not isinstance(result, dict) or set(result.keys()) not in ({"success", "message"}, {"success", "message", "data"}):
            raise TypeError("HANLIN_ABI:invalid_tool_result")
        if not isinstance(result["success"], bool) or not isinstance(result["message"], str):
            raise TypeError("HANLIN_ABI:invalid_tool_result")
        return _hanlin_encode(result)
    """#
}
