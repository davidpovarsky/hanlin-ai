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
    func getString(_ key: String) -> String?
    func setString(_ key: String, _ value: String) -> Bool
    func getJSON(_ key: String) -> Any?
    func setJSON(_ key: String, _ value: Any) -> Bool
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
    func getString(_ key: String) -> String? { get(key) as? String }
    func setString(_ key: String, _ value: String) -> Bool { set(key, value) }
    func getJSON(_ key: String) -> Any? { get(key) }
    func setJSON(_ key: String, _ value: Any) -> Bool { set(key, value) }
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
        if program.javaScript.contains("moment"), let moment = Self.resource("moment.min.js") { context.evaluateScript(moment) }
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