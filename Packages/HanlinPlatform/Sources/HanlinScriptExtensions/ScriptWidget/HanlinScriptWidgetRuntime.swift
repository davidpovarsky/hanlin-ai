import Foundation
import HanlinPlatformContracts
import HanlinScriptContracts
import JavaScriptCore

public struct HanlinScriptWidgetError: Error, LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

@objc protocol ScriptWidgetStorageJSExports: JSExport {
    func get(_ key: String) -> Any?
    func set(_ key: String, _ value: Any) -> Bool
    func remove(_ key: String) -> Bool
    func getString(_ key: String) -> String
    func setString(_ key: String, _ value: String) -> Bool
    func getJSON(_ key: String) -> Any?
    func setJSON(_ key: String, _ value: Any) -> Bool
    func compareAndSetString(_ key: String, _ expected: String, _ value: String) -> Bool
    func compareAndSetJSON(_ key: String, _ expected: Any, _ value: Any) -> Bool
    func keys() -> [String]
    func clear() -> Bool
}

/// Execution-local typed storage. Only the verified outer transaction publishes
/// it; JavaScript never writes UserDefaults or a process-local fallback.
@objc final class ScriptWidgetStorageBridge: NSObject, ScriptWidgetStorageJSExports {
    var values: [String: HanlinValue]
    var failure: String?
    init(values: [String: HanlinValue]) { self.values = values }
    func get(_ key: String) -> Any? { values[key]?.toAny() }
    func set(_ key: String, _ value: Any) -> Bool {
        do {
            guard key.utf8.count <= 256, values.count < 128 || values[key] != nil else { throw HanlinWidgetProgramError.invalidProgram }
            values[key] = try HanlinWidgetJSON.value(value)
            return true
        } catch { failure = "Invalid typed storage value: \(error)"; return false }
    }
    func remove(_ key: String) -> Bool { values.removeValue(forKey: key); return true }
    func getString(_ key: String) -> String { get(key) as? String ?? "" }
    func setString(_ key: String, _ value: String) -> Bool { set(key, value) }
    func getJSON(_ key: String) -> Any? { get(key) as? [String: Any] ?? [:] }
    func setJSON(_ key: String, _ value: Any) -> Bool { set(key, value) }
    func compareAndSetString(_ key: String, _ expected: String, _ value: String) -> Bool {
        guard getString(key) == expected else { return false }
        return setString(key, value)
    }
    func compareAndSetJSON(_ key: String, _ expected: Any, _ value: Any) -> Bool {
        guard let expected = try? HanlinWidgetJSON.value(expected), values[key] == expected else { return false }
        return setJSON(key, value)
    }
    func keys() -> [String] { values.keys.sorted() }
    func clear() -> Bool { values.removeAll(); return true }
}

@objc protocol HanlinWidgetFileJSExports: JSExport {
    func exists(_ path: String) -> Bool
    func read(_ path: String) -> String
    func readJSON(_ path: String) -> Any
}

/// Original read-only $file contract, backed by the verified immutable program.
@objc final class HanlinWidgetFileBridge: NSObject, HanlinWidgetFileJSExports {
    let files: [String: Data]
    init(files: [String: Data]) { self.files = files }
    func exists(_ path: String) -> Bool { files[path] != nil }
    func read(_ path: String) -> String { files[path].flatMap { String(data: $0, encoding: .utf8) } ?? "" }
    func readJSON(_ path: String) -> Any {
        guard let data = files[path], let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [String: String]() }
        return object
    }
}

public struct HanlinScriptWidgetExecution: Sendable {
    public let node: HanlinScriptWidgetPreparedNode
    public let values: [String: HanlinValue]
}

/// Adapted widget lifecycle from ScriptWidgetRuntime.swift at 68f04194:
/// $element JSExport -> original util.js -> async $main -> $render -> resolve
/// custom function components -> freeze. One invocation owns its VM. No
/// JSContext, JSValue or mutable exported object is retained or sent out.
public struct HanlinScriptWidgetRuntime: Sendable {
    public static let shared = Self()
    public init() {}

    public func run(program: HanlinWidgetProgram, values: [String: HanlinValue],
                    environment: [String: HanlinValue], actionID: String? = nil,
                    actionValue: Bool? = nil) throws -> HanlinScriptWidgetExecution {
        try program.validate(engine: .scriptwidget)
        guard let context = JSContext(), let util = Self.resource("util.js") else {
            throw HanlinScriptWidgetError("Missing ScriptWidget runtime resource")
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        let guardExecution: @convention(block) () -> Void = {
            if ContinuousClock.now >= deadline, let current = JSContext.current() {
                current.exception = JSValue(newErrorFromMessage: "Widget execution budget exceeded", in: current)
            }
        }
        context.setObject(guardExecution, forKeyedSubscript: "__scriptWidgetCheckExecution" as NSString)
        context.setObject(ScriptWidgetRuntimeElement.self, forKeyedSubscript: "$element" as NSString)
        let storage = ScriptWidgetStorageBridge(values: values)
        context.setObject(storage, forKeyedSubscript: "$storage" as NSString)
        context.setObject(HanlinWidgetFileBridge(files: program.resources), forKeyedSubscript: "$file" as NSString)
        var importCount = 0
        let importScript: @convention(block) (String) -> Bool = { path in
            guard importCount < 64, let script = program.imports[path], let current = JSContext.current() else { return false }
            importCount += 1
            current.evaluateScript(script)
            return current.exception == nil
        }
        context.setObject(importScript, forKeyedSubscript: "$import" as NSString)
        // The upstream $fetch/$http contract resolves text (or explicit response
        // metadata), not a browser Response object. The native transport never
        // touches JSC: bounded bytes return on the execution owner before Promise
        // settlement. No VM callback is retained by URLSession.
        var requestCount = 0
        let http: @convention(block) (String, String, [String: Any]?, Bool) -> [String: Any] = { method, rawURL, params, metadata in
            requestCount += 1
            guard requestCount <= 4, ContinuousClock.now < deadline, let url = URL(string: rawURL),
                  ScriptWidgetFetchPolicy.validationError(for: url) == nil,
                  ["GET", "POST", "PUT", "PATCH", "DELETE"].contains(method) else {
                return ["ok": false, "error": "Invalid or over-budget widget HTTP request"]
            }
            let remaining = ContinuousClock.now.duration(to: deadline).components
            let seconds = Double(remaining.seconds) + Double(remaining.attoseconds) / 1e18
            let requestedTimeout = params?["timeoutInterval"] as? Double ?? 2.5
            guard requestedTimeout.isFinite, requestedTimeout > 0, seconds > 0 else {
                return ["ok": false, "error": "Invalid widget HTTP timeout"]
            }
            let timeout = min(2.5, requestedTimeout, seconds)
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.timeoutInterval = timeout
            if let headers = params?["headers"] as? [String: String] {
                guard headers.count <= 32, headers.allSatisfy({ key, value in
                    !key.isEmpty && key.utf8.count <= 128 && value.utf8.count <= 2_048
                        && !key.contains(where: { $0.isNewline }) && !value.contains(where: { $0.isNewline })
                }) else { return ["ok": false, "error": "Invalid widget HTTP headers"] }
                for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
            }
            if let body = params?["body"] as? String { request.httpBody = Data(body.utf8) }
            else if let body = params?["body"] as? [String: Any] {
                guard let bytes = try? JSONSerialization.data(withJSONObject: body) else { return ["ok": false, "error": "Invalid JSON request body"] }
                request.httpBody = bytes
                if request.value(forHTTPHeaderField: "Content-Type") == nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
            }
            guard timeout > 0, let response = HanlinWidgetImageTransport.request(request, timeout: timeout),
                  let body = params?["responseType"] as? String == "base64" ? response.data.base64EncodedString() : String(data: response.data, encoding: .utf8) else {
                return ["ok": false, "error": "Widget HTTP transport failed, exceeded its budget or returned invalid UTF-8"]
            }
            let value: Any = metadata ? ["body": body, "status": response.status, "headers": response.headers] : body
            return ["ok": true, "value": value]
        }
        context.setObject(http, forKeyedSubscript: "__hanlinWidgetHTTP" as NSString)
        context.evaluateScript("""
            function __hanlinHTTP(method,url,params,metadata) {
                const result = __hanlinWidgetHTTP(method,url,params || {},Boolean(metadata));
                return result.ok ? Promise.resolve(result.value) : Promise.reject(result.error);
            }
            globalThis.$fetch = (url,params) => __hanlinHTTP('GET',url,params,false);
            globalThis.fetch = globalThis.$fetch;
            globalThis.$http = Object.freeze({
                get:(url,params)=>__hanlinHTTP('GET',url,params,false),
                getResponse:(url,params)=>__hanlinHTTP('GET',url,params,true),
                post:(url,params)=>__hanlinHTTP('POST',url,params,false),
                put:(url,params)=>__hanlinHTTP('PUT',url,params,false),
                patch:(url,params)=>__hanlinHTTP('PATCH',url,params,false),
                delete:(url,params)=>__hanlinHTTP('DELETE',url,params,false)
            });
            """)
        let getenv: @convention(block) (String) -> Any = { environment[$0]?.toAny() ?? "" }
        context.setObject(getenv, forKeyedSubscript: "$getenv" as NSString)
        context.setObject(environment.mapValues { $0.toAny() }, forKeyedSubscript: "$widget" as NSString)
        context.setObject(actionID ?? "", forKeyedSubscript: "__hanlinAction" as NSString)
        context.setObject(actionValue.map { ["value": $0] } ?? [:], forKeyedSubscript: "__hanlinEvent" as NSString)
        var rendered: ScriptWidgetRuntimeElement?
        var scriptError: String?
        let render: @convention(block) (ScriptWidgetRuntimeElement) -> Void = { rendered = $0 }
        let error: @convention(block) (String) -> Void = { scriptError = $0 }
        context.setObject(render, forKeyedSubscript: "$render" as NSString)
        context.setObject(error, forKeyedSubscript: "$error" as NSString)
        context.evaluateScript("var console = {log:function(){},warn:function(){},error:function(e){$error(String(e));}}; var $console=console;")
        context.evaluateScript(util)
        if let moment = Self.resource("moment.min.js") { context.evaluateScript(moment) }
        context.evaluateScript(program.javaScript)
        context.evaluateScript("$main().then(function(){globalThis.__hanlinComplete=true;},function(e){$error(String(e));});")
        if let exception = context.exception { throw HanlinScriptWidgetError(exception.toString() ?? "ScriptWidget exception") }
        if let scriptError = scriptError ?? storage.failure { throw HanlinScriptWidgetError(scriptError) }
        guard ContinuousClock.now < deadline else { throw HanlinScriptWidgetError("Widget execution budget exceeded") }
        guard context.objectForKeyedSubscript("__hanlinComplete")?.toBool() == true else {
            throw HanlinScriptWidgetError("Widget is awaiting an unsupported asynchronous operation")
        }
        guard let rendered else { throw HanlinScriptWidgetError("The script did not call $render") }
        var count = 0
        var active: Set<ObjectIdentifier> = []
        let frozen = try freeze(rendered, depth: 1, count: &count, active: &active, context: context)
        return .init(node: frozen, values: storage.values)
    }

    // Source-derived component resolution, performed only by the VM owner.
    private func freeze(_ input: ScriptWidgetRuntimeElement, depth: Int, count: inout Int,
                        active: inout Set<ObjectIdentifier>, context: JSContext) throws -> HanlinScriptWidgetPreparedNode {
        guard depth <= 64, count < 1_000 else { throw HanlinScriptWidgetError("Widget tree budget exceeded") }
        var element = input
        var inserted: [ObjectIdentifier] = []
        defer { inserted.forEach { active.remove($0) } }
        for _ in 0..<64 {
            let identifier = ObjectIdentifier(element)
            guard active.insert(identifier).inserted else { throw HanlinScriptWidgetError("Widget component cycle") }
            inserted.append(identifier)
            if element.tagAsString() != nil { break }
            var arguments = element.getProps()
            arguments["children"] = element.getChildren()
            guard let result = element.tag.call(withArguments: [arguments])?.toObject() as? ScriptWidgetRuntimeElement else {
                throw HanlinScriptWidgetError("Custom component must return a ScriptWidget element")
            }
            element = result
        }
        guard let tag = element.tagAsString(), element.getProps().count <= 128 else { throw HanlinScriptWidgetError("Invalid native widget element") }
        count += 1
        var props: [String: HanlinValue] = [:]
        for (key, value) in element.getProps() {
            guard let key = key as? String else { throw HanlinScriptWidgetError("Invalid property key") }
            props[key] = try HanlinWidgetJSON.value(value)
        }
        var children: [HanlinScriptWidgetPreparedNode.Child] = []
        func append(_ value: Any) throws {
            if let child = value as? ScriptWidgetRuntimeElement {
                children.append(.element(try freeze(child, depth: depth + 1, count: &count, active: &active, context: context)))
            } else if let nested = value as? [Any] {
                for item in nested { try append(item) }
            } else { children.append(.value(try HanlinWidgetJSON.value(value))) }
        }
        for child in element.getChildren() { try append(child) }
        if let exception = context.exception { throw HanlinScriptWidgetError(exception.toString() ?? "Component exception") }
        return .init(tag: tag, props: props, children: children)
    }

    private static func resource(_ name: String) -> String? {
        guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "support.bundle") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
