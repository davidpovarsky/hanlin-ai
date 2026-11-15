import Foundation

struct PythonNativeExtensionDescriptor: Codable, Sendable, Equatable {
    let distribution: String
    let version: String
    let module: String
    let architecture: String
    let pythonMajor: Int
    let pythonMinor: Int
    let linkage: String
    let simulator: Bool
    let registeredInittab: Bool
    let initializationObserved: Bool
}

@_silgen_name("HanlinPythonNativeExtensionCatalogJSON")
private func copyPythonNativeExtensionCatalog() -> UnsafeMutablePointer<CChar>?
@_silgen_name("HanlinPythonFree")
private func freePythonNativeExtensionCatalog(_ value: UnsafeMutablePointer<CChar>)

enum PythonNativeExtensions {
    /// Observes the linked table without starting the interpreter, scheduling a
    /// job, taking the GIL, changing service readiness or verifying a signature.
    static func snapshot() throws -> [PythonNativeExtensionDescriptor] {
        guard let pointer = copyPythonNativeExtensionCatalog() else {
            throw RuntimeCoreError.runtimeFailure("The linked Python extension catalog could not allocate its snapshot.")
        }
        defer { freePythonNativeExtensionCatalog(pointer) }
        return try JSONDecoder().decode([PythonNativeExtensionDescriptor].self, from: Data(String(cString: pointer).utf8))
    }
}
