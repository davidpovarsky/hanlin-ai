import Foundation

/// Original Host schema fixtures only; no claim that desktop Node is iOS Node.
@main
enum SkillRuntimeNodeCapabilityAdapterChecks {
    typealias C = SkillRuntimeContract
    typealias A = SkillRuntimeNodeCapabilityAdapter
    struct Failure: Error { let name: String }
    static let binding = C.EngineBinding(engineID: .node, engineVersion: "22.21.1",
        engineFingerprint: String(repeating: "a", count: 64), environmentID: "group",
        environmentFingerprint: String(repeating: "b", count: 64))
    static let now = Date(timeIntervalSince1970: 2_000)

    static func data(schema: Int = 1, profile: String = "hanlin-ios-app",
                     boundary: String = "same-process-worker-threads", node: String = "22.21.1",
                     extras: [String: Any] = ["webAssemblyAvailable": true, "pointerCompression": true,
                         "v8Sandbox": false, "fetchImplementation": "node-undici"]) throws -> Data {
        var observed = extras
        observed["node"] = node
        return try JSONSerialization.data(withJSONObject: ["schemaVersion": schema,
            "targetProfile": profile, "executionBoundary": boundary, "observed": observed], options: [.sortedKeys])
    }

    static func inspect(_ data: Data, binding: C.EngineBinding = Self.binding) throws -> C.EngineFacts {
        try A.inspect(report: data, binding: binding, observedAt: now, artifactReference: "reports/node.json")
    }

    static func rejects(_ data: Data, _ expected: A.ObservationError,
                        binding: C.EngineBinding = Self.binding) -> Bool {
        do { _ = try inspect(data, binding: binding); return false }
        catch let actual as A.ObservationError { return actual == expected }
        catch { return false }
    }

    static func main() throws {
        var passed: [String] = []
        func check(_ name: String, _ condition: @autoclosure () -> Bool) throws {
            guard condition() else { throw Failure(name: name) }
            passed.append(name)
        }
        let actual = try inspect(data())
        func fact(_ name: String, in facts: C.EngineFacts? = nil) -> C.CapabilityFact? {
            (facts ?? actual).facts.first { $0.requirement.name == name }
        }
        try check("engine version comes from original observed node field",
                  fact(C.EngineID.node.rawValue)?.resolvedVersion == "22.21.1")
        try check("actual namespace observation maps narrowly",
                  fact("node.webassembly.namespace")?.status == .available)
        try check("build configuration false is explicit unsupported",
                  fact("node.build.v8-sandbox")?.status == .unsupported)
        try check("transport selection is preserved without generic fetch promise",
                  fact("node.fetch.selected-transport")?.resolvedVersion == "node-undici" && fact("fetch") == nil)
        try check("no package command or POSIX capability is invented",
                  actual.facts.allSatisfy { [.engine, .capability].contains($0.requirement.kind) } &&
                  fact("child_process") == nil && fact("jit") == nil)
        let absent = try inspect(data(extras: [:]))
        try check("absent optional observations remain absent", absent.facts.count == 1)
        let disabled = try inspect(data(extras: ["webAssemblyAvailable": false]))
        try check("absent WASM namespace is not made available",
                  fact("node.webassembly.namespace", in: disabled)?.status == .unsupported)
        let alternate = try inspect(data(extras: ["fetchImplementation": "node-fetch@3.3.2+native-web-api"]))
        try check("original fallback transport name is preserved",
                  fact("node.fetch.selected-transport", in: alternate)?.resolvedVersion == "node-fetch@3.3.2+native-web-api")
        let unknownTransport = try inspect(data(extras: ["fetchImplementation": "future-unverified"]))
        try check("unknown transport is not claimed compatible", fact("node.fetch.selected-transport", in: unknownTransport) == nil)
        let schema = try data(schema: 2)
        try check("unknown schema rejected", rejects(schema, .unsupportedSchema))
        let profile = try data(profile: "desktop-linux")
        try check("another platform report cannot certify iOS", rejects(profile, .wrongProfile))
        let boundary = try data(boundary: "child-process")
        try check("another execution boundary rejected", rejects(boundary, .wrongProfile))
        let changed = try data(node: "23.0.0")
        try check("changed process version invalidates binding", rejects(changed, .wrongEngineBinding))
        let python = C.EngineBinding(engineID: .python, engineVersion: binding.engineVersion,
            engineFingerprint: binding.engineFingerprint, environmentID: binding.environmentID,
            environmentFingerprint: binding.environmentFingerprint)
        let report = try data()
        try check("Node report cannot be assigned to another engine", rejects(report, .wrongEngineBinding, binding: python))
        let unbound = C.EngineBinding(engineID: .node, engineVersion: binding.engineVersion,
            engineFingerprint: "unknown", environmentID: binding.environmentID,
            environmentFingerprint: binding.environmentFingerprint)
        try check("no facts without actual engine identity", rejects(report, .unboundIdentity, binding: unbound))
        try check("observation provenance is not test evidence",
                  actual.facts.allSatisfy { $0.evidence.kind == .observed && $0.evidence.observedAt == now &&
                      $0.evidence.sourceFingerprint == binding.engineFingerprint && $0.binding == binding })
        var wrongTypeRejected = false
        do { _ = try inspect(data(extras: ["webAssemblyAvailable": "true"])) }
        catch is DecodingError { wrongTypeRejected = true }
        try check("string truthiness cannot create a Boolean capability", wrongTypeRejected)
        var malformedRejected = false
        do { _ = try inspect(Data("not JSON".utf8)) }
        catch is DecodingError { malformedRejected = true }
        try check("malformed original report rejected", malformedRejected)
        let result: [String: Any] = ["status": "EXECUTED_PASS", "cases": passed,
            "boundary": "Original Host schema fixtures through the production Swift decoder; no Node start, HTTP, package import, native engine or device execution."]
        print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
