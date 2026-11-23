import Foundation
import HanlinPlatformContracts
import HanlinScriptContracts
import JavaScriptCore
@preconcurrency import HanlinScriptWidgetOriginal

public struct HanlinScriptWidgetError: Error, LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct HanlinScriptWidgetExecution: Sendable {
    public let node: HanlinScriptWidgetPreparedNode
    public let values: [String: HanlinValue]
}

/// Original ScriptWidget native API/session lifecycle plus Hanlin's prepared
/// source and immutable native renderer boundary. All native Promise callbacks
/// settle before values are committed by the surrounding widget transaction.
public struct HanlinScriptWidgetRuntime: Sendable {
    public static let shared = Self()
    public init() {}

    public static func nativeIdentity(_ identity: HanlinScriptExtensionIdentity, artifactSHA256: String) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(data: try encoder.encode(identity), encoding: .utf8)! + ":" + artifactSHA256
    }

    public func run(program: HanlinWidgetProgram, values: [String: HanlinValue],
                    environment: [String: HanlinValue], actionID: String? = nil,
                    actionValue: Bool? = nil, nativeRoot: URL? = nil,
                    nativeIdentity: String? = nil) throws -> HanlinScriptWidgetExecution {
        try program.validate(engine: .scriptwidget)
        guard let context = JSContext(), let util = Self.resource("util.js") else {
            throw HanlinScriptWidgetError("Missing ScriptWidget runtime resource")
        }
        // Existing direct SDK callers receive an isolated execution image.
        // Installed widget callers always provide their exact product store
        // and current installation/generation/artifact identity.
        let temporary = nativeRoot == nil
            ? FileManager.default.temporaryDirectory.appendingPathComponent("HanlinScriptWidget-" + UUID().uuidString, isDirectory: true)
            : nil
        defer { if let temporary { try? FileManager.default.removeItem(at: temporary) } }
        let native = try HanlinOriginalScriptWidgetSession(context: context,
            root: nativeRoot ?? temporary!, identity: nativeIdentity ?? UUID().uuidString,
            preparedJavaScript: program.javaScript, files: program.resources,
            values: values.mapValues { $0.toAny() },
            environment: environment.mapValues { value in
                if case let .string(text) = value { return text }
                return (try? String(data: value.jsonValue().canonicalJSONData(), encoding: .utf8)) ?? ""
            }, isUserInitiatedAction: actionID != nil || actionValue != nil)
        let completion = HanlinScriptWidgetCompletion()
        let deadline = ContinuousClock.now.advanced(by: .seconds(HanlinOriginalScriptWidgetSession.executionTimeout))
        var rendered: ScriptWidgetRuntimeElement?
        native.onJavaScriptQueue {
            native.installAPIs()
            context.setObject(ScriptWidgetRuntimeElement.self, forKeyedSubscript: "$element" as NSString)
            // $storage.get/set are Hanlin's compatibility additions. Every
            // original storage operation below still calls its JSExport class.
            let get: @convention(block) (String) -> Any = { [weak native] key in
                do { return try native?.value(forKey: key) ?? NSNull() }
                catch { completion.finish(.failure(error)); return NSNull() }
            }
            let set: @convention(block) (String, Any) -> Bool = { [weak native] key, value in
                guard let native else { return false }
                do { try native.setValue(value, forKey: key); return true }
                catch { completion.finish(.failure(error)); return false }
            }
            context.setObject(get, forKeyedSubscript: "__hanlinGetWidgetValue" as NSString)
            context.setObject(set, forKeyedSubscript: "__hanlinSetWidgetValue" as NSString)
            context.evaluateScript("""
                const __hanlinOriginalStorage = $storage;
                globalThis.$storage = {
                  get: __hanlinGetWidgetValue, set: __hanlinSetWidgetValue,
                  getString: key => __hanlinOriginalStorage.getString(key),
                  setString: (key,value) => __hanlinOriginalStorage.setString(key,value),
                  getJSON: key => __hanlinOriginalStorage.getJSON(key),
                  setJSON: (key,value) => __hanlinOriginalStorage.setJSON(key,value),
                  compareAndSetString: (key,expected,value) => __hanlinOriginalStorage.compareAndSetString(key,expected,value),
                  compareAndSetJSON: (key,expected,value) => __hanlinOriginalStorage.compareAndSetJSON(key,expected,value),
                  remove: key => __hanlinOriginalStorage.remove(key),
                  keys: () => __hanlinOriginalStorage.keys(),
                  clear: () => __hanlinOriginalStorage.clear()
                };
                """)
            let importScript: @convention(block) (String) -> Bool = { path in
                guard let script = program.imports[path], let current = JSContext.current() else { return false }
                current.evaluateScript(script)
                return current.exception == nil
            }
            context.setObject(importScript, forKeyedSubscript: "$import" as NSString)
            let getenv: @convention(block) (String) -> Any = { environment[$0]?.toAny() ?? "" }
            context.setObject(getenv, forKeyedSubscript: "$getenv" as NSString)
            context.setObject(environment.mapValues { $0.toAny() }, forKeyedSubscript: "$widget" as NSString)
            context.setObject(actionID ?? "", forKeyedSubscript: "__hanlinAction" as NSString)
            context.setObject(actionValue.map { ["value": $0] } ?? [:], forKeyedSubscript: "__hanlinEvent" as NSString)
            let render: @convention(block) (ScriptWidgetRuntimeElement) -> Void = { rendered = $0 }
            let error: @convention(block) (String) -> Void = { completion.finish(.failure(HanlinScriptWidgetError($0))) }
            let finished: @convention(block) () -> Void = { [weak native] in
                guard let native, let current = JSContext.current(), let rendered else {
                    completion.finish(.failure(HanlinScriptWidgetError("The script did not call $render")))
                    return
                }
                do {
                    var budget = FreezeBudget(deadline: deadline)
                    var active: Set<ObjectIdentifier> = []
                    let frozen = try freeze(rendered, depth: 1, budget: &budget, active: &active, context: current)
                    guard try JSONEncoder().encode(frozen).count <= 1_024 * 1_024 else {
                        throw HanlinScriptWidgetError("Widget prepared payload budget exceeded")
                    }
                    try budget.checkTime()
                    completion.finish(.success(.init(node: frozen, values: try HanlinWidgetJSON.dictionary(native.values()))))
                } catch { completion.finish(.failure(error)) }
            }
            context.setObject(render, forKeyedSubscript: "$render" as NSString)
            context.setObject(error, forKeyedSubscript: "$error" as NSString)
            context.setObject(finished, forKeyedSubscript: "__hanlinFinishWidget" as NSString)
            context.exceptionHandler = { _, exception in
                completion.finish(.failure(HanlinScriptWidgetError(exception?.toString() ?? "ScriptWidget exception")))
            }
            context.evaluateScript(util)
            if let moment = Self.resource("moment.min.js") { context.evaluateScript(moment) }
            context.evaluateScript(program.javaScript)
            context.evaluateScript("$main().then(__hanlinFinishWidget,function(e){$error(String(e));});")
        }
        let result = completion.wait(until: deadline)
        native.cancel()
        // Drain prior native callbacks before releasing the context/package.
        native.onJavaScriptQueue {
            native.finish()
            rendered = nil
            context.exceptionHandler = nil
            for key in ["$render", "$error", "$storage", "__hanlinFinishWidget", "__hanlinGetWidgetValue", "__hanlinSetWidgetValue"] {
                context.setObject(nil, forKeyedSubscript: key as NSString)
            }
        }
        return try result.get()
    }

    private struct FreezeBudget {
        let deadline: ContinuousClock.Instant
        var nodes = 0
        var materialBytes = 0
        func checkTime() throws {
            guard ContinuousClock.now < deadline else { throw HanlinScriptWidgetError("Widget execution budget exceeded") }
        }
        mutating func node() throws {
            try checkTime()
            guard nodes < 1_000 else { throw HanlinScriptWidgetError("Widget tree budget exceeded") }
            nodes += 1
        }
        mutating func charge(_ size: Int) throws {
            try checkTime()
            guard size <= 256 * 1_024 - materialBytes else { throw HanlinScriptWidgetError("Widget material budget exceeded") }
            materialBytes += size
        }
        mutating func value(_ object: Any) throws -> HanlinValue {
            let value = try HanlinWidgetJSON.value(object)
            try charge(try value.jsonValue().canonicalJSONData().count)
            return value
        }
    }

    // Source-derived component resolution, performed only by the VM owner.
    private func freeze(_ input: ScriptWidgetRuntimeElement, depth: Int, budget: inout FreezeBudget,
                        active: inout Set<ObjectIdentifier>, context: JSContext) throws -> HanlinScriptWidgetPreparedNode {
        guard depth <= 64 else { throw HanlinScriptWidgetError("Widget tree budget exceeded") }
        try budget.node()
        var element = input
        var inserted: [ObjectIdentifier] = []
        defer { inserted.forEach { active.remove($0) } }
        for _ in 0..<64 {
            try budget.checkTime()
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
        try budget.charge(tag.utf8.count)
        var props: [String: HanlinValue] = [:]
        for (key, value) in element.getProps() {
            guard let key = key as? String else { throw HanlinScriptWidgetError("Invalid property key") }
            try budget.charge(key.utf8.count)
            props[key] = try budget.value(value)
        }
        var children: [HanlinScriptWidgetPreparedNode.Child] = []
        func append(_ value: Any, arrayDepth: Int = 0) throws {
            guard depth + arrayDepth <= 64 else { throw HanlinScriptWidgetError("Widget tree budget exceeded") }
            try budget.checkTime()
            if let child = value as? ScriptWidgetRuntimeElement {
                children.append(.element(try freeze(child, depth: depth + arrayDepth + 1, budget: &budget, active: &active, context: context)))
            } else if let nested = value as? [Any] {
                for item in nested { try append(item, arrayDepth: arrayDepth + 1) }
            } else {
                try budget.node()
                children.append(.value(try budget.value(value)))
            }
        }
        for child in element.getChildren() { try append(child) }
        if let exception = context.exception { throw HanlinScriptWidgetError(exception.toString() ?? "Component exception") }
        return .init(tag: tag, props: props, children: children)
    }

    private static func resource(_ name: String) -> String? {
        HanlinOriginalScriptWidgetSession.supportScript(name)
    }
}


/// Only immutable native values cross the JavaScript queue/caller boundary.
private final class HanlinScriptWidgetCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private let signal = DispatchSemaphore(value: 0)
    private var result: Result<HanlinScriptWidgetExecution, Error>?
    func finish(_ result: Result<HanlinScriptWidgetExecution, Error>) {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return }
        self.result = result
        lock.unlock()
        signal.signal()
    }
    func wait(until deadline: ContinuousClock.Instant) -> Result<HanlinScriptWidgetExecution, Error> {
        while ContinuousClock.now < deadline {
            lock.lock(); let current = result; lock.unlock()
            if let current { return current }
            if Thread.isMainThread {
                // Apple providers deliver UI authorization and some system
                // snapshots on the main run loop. Keep that real loop live.
                _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            } else {
                _ = signal.wait(timeout: .now() + .milliseconds(10))
            }
        }
        lock.lock(); defer { lock.unlock() }
        return result ?? .failure(HanlinScriptWidgetError("ScriptWidget native execution timed out."))
    }
}
