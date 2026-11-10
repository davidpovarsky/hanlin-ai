import Foundation
import IOSSystemLite

@_silgen_name("HanlinPythonVersion")
private func HanlinPythonVersion() -> UnsafePointer<CChar>?

@_silgen_name("HanlinPythonExecute")
private func HanlinPythonExecute(_ requestJSON: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?

@_silgen_name("HanlinPythonFree")
private func HanlinPythonFree(_ value: UnsafeMutablePointer<CChar>)

@_silgen_name("HanlinPythonRegisterExecution")
private func HanlinPythonRegisterExecution(_ executionID: UnsafePointer<CChar>)
@_silgen_name("HanlinPythonCancelExecution")
private func HanlinPythonCancelExecution(_ executionID: UnsafePointer<CChar>)
@_silgen_name("HanlinPythonUnregisterExecution")
private func HanlinPythonUnregisterExecution(_ executionID: UnsafePointer<CChar>)

enum PythonRuntimeBridge {
    private static let executionQueue = DispatchQueue(label: "hanlin.python.execution", qos: .userInitiated)

    nonisolated static func cancel(id: UUID) {
        id.uuidString.withCString(HanlinPythonCancelExecution)
    }

    static func register(id: UUID) { id.uuidString.withCString(HanlinPythonRegisterExecution) }
    static func unregister(id: UUID) { id.uuidString.withCString(HanlinPythonUnregisterExecution) }

    static func execute(requestJSON: String, id: UUID, onStart: @escaping @Sendable () -> Void) async throws -> Data {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                executionQueue.async {
                    onStart()
                    do {
                        let data = try IOSSystemRunner.withProcessCurrentDirectoryLock {
                            try execute(requestJSON: requestJSON)
                        }
                        continuation.resume(returning: data)
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { cancel(id: id) }
    }
    static func version() throws -> String {
        guard let pointer = HanlinPythonVersion() else { throw RuntimeCoreError.runtimeUnavailable(.localPython) }
        return String(cString: pointer).split(separator: " ").first.map(String.init) ?? String(cString: pointer)
    }

    static func execute(requestJSON: String) throws -> Data {
        let pointer = requestJSON.withCString(HanlinPythonExecute)
        guard let pointer else { throw RuntimeCoreError.runtimeUnavailable(.localPython) }
        defer { HanlinPythonFree(pointer) }
        return Data(String(cString: pointer).utf8)
    }
}
