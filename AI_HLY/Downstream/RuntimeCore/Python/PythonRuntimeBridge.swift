import Foundation

@_silgen_name("HanlinPythonVersion")
private func HanlinPythonVersion() -> UnsafePointer<CChar>?

@_silgen_name("HanlinPythonExecute")
private func HanlinPythonExecute(_ requestJSON: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?

@_silgen_name("HanlinPythonFree")
private func HanlinPythonFree(_ value: UnsafeMutablePointer<CChar>)

enum PythonRuntimeBridge {
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
