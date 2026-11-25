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
    public let presentationEffect: HanlinNativePresentationEffect
    public let dynamicIsland: HanlinScriptWidgetDynamicIsland?
    public init(node: HanlinScriptWidgetPreparedNode, values: [String: HanlinValue],
                presentationEffect: HanlinNativePresentationEffect = .init(),
                dynamicIsland: HanlinScriptWidgetDynamicIsland? = nil) {
        self.node = node
        self.values = values
        self.presentationEffect = presentationEffect
        self.dynamicIsland = dynamicIsland
    }
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
                    actionValue: Bool? = nil, actionParameters: HanlinValue = .null, nativeRoot: URL? = nil,
                    nativeIdentity: String? = nil) throws -> HanlinScriptWidgetExecution {
        let result = try evaluate(program: program, values: values, environment: environment,
            actionID: actionID, actionValue: actionValue, actionParameters: actionParameters,
            nativeRoot: nativeRoot, nativeIdentity: nativeIdentity, requiresRender: true)
        guard let node = result.node else {
            throw HanlinScriptWidgetError("The script did not call $render or $dynamic_island")
        }
        return .init(node: node, values: result.values,
            presentationEffect: result.presentationEffect, dynamicIsland: result.dynamicIsland)
    }

    /// Original Control Widget actions may execute a function without rendering
    /// a widget. The same original native session commits its storage values.
    public func performAction(program: HanlinWidgetProgram, values: [String: HanlinValue],
                              environment: [String: HanlinValue], actionID: String,
                              actionValue: Bool? = nil, nativeRoot: URL,
                              nativeIdentity: String) throws -> [String: HanlinValue] {
        try evaluate(program: program, values: values, environment: environment,
            actionID: actionID, actionValue: actionValue, actionParameters: .null,
            nativeRoot: nativeRoot, nativeIdentity: nativeIdentity, requiresRender: false).values
    }

    private func evaluate(program: HanlinWidgetProgram, values: [String: HanlinValue],
                          environment: [String: HanlinValue], actionID: String?,
                          actionValue: Bool?, actionParameters: HanlinValue,
                          nativeRoot: URL?, nativeIdentity: String?,
                          requiresRender: Bool) throws -> HanlinScriptWidgetEvaluation {
        try program.validate(engine: .scriptwidget)
        try HanlinOriginalScriptWidgetSession.validatePreparedJavaScript(program.javaScript)
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
                return (try? String(data: value.jsonValue().canonicalJSONData(limits: .unbounded), encoding: .utf8)) ?? ""
            }, isUserInitiatedAction: actionID != nil || actionValue != nil)
        let completion = HanlinScriptWidgetCompletion()
        let deadline = ContinuousClock.now.advanced(by: .seconds(HanlinOriginalScriptWidgetSession.executionTimeout))
        var rendered: ScriptWidgetRuntimeElement?
        var presentationEffect = HanlinNativePresentationEffect()
        var dynamicRegions: [String: ScriptWidgetRuntimeElement] = [:]
        native.onJavaScriptQueue {
            native.installAPIs()
            context.setObject(ScriptWidgetRuntimeElement.self, forKeyedSubscript: "$element" as NSString)
            // Original $component is a registration diagnostic; function JSX
            // components are resolved by the original element/freeze pipeline.
            let component: @convention(block) (String, JSValue) -> Void = { name, _ in
                NSLog("ScriptWidget component: %@", name)
            }
            context.setObject(component, forKeyedSubscript: "$component" as NSString)
            let dynamicIsland: @convention(block) (NSDictionary) -> Void = { regions in
                let expanded = regions["expanded"] as? NSDictionary ?? [:]
                let values: [(String, Any?)] = [
                    ("expandedLeading", expanded["leading"]), ("expandedTrailing", expanded["trailing"]),
                    ("expandedCenter", expanded["center"]), ("expandedBottom", expanded["bottom"]),
                    ("compactLeading", regions["compactLeading"]), ("compactTrailing", regions["compactTrailing"]),
                    ("minimal", regions["minimal"])
                ]
                var captured: [String: ScriptWidgetRuntimeElement] = [:]
                for (key, value) in values {
                    guard let value, !(value is NSNull) else { continue }
                    guard let element = value as? ScriptWidgetRuntimeElement else {
                        completion.finish(.failure(HanlinScriptWidgetError("Dynamic Island region must be a ScriptWidget element: " + key)))
                        return
                    }
                    captured[key] = element
                }
                dynamicRegions = captured
            }
            context.setObject(dynamicIsland, forKeyedSubscript: "$dynamic_island" as NSString)

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
                do { try HanlinOriginalScriptWidgetSession.validatePreparedJavaScript(script) }
                catch { completion.finish(.failure(error)); return false }
                current.evaluateScript(script)
                return current.exception == nil
            }
            context.setObject(importScript, forKeyedSubscript: "$import" as NSString)
            let getenv: @convention(block) (String) -> Any = { environment[$0]?.toAny() ?? "" }
            context.setObject(getenv, forKeyedSubscript: "$getenv" as NSString)
            context.setObject(environment.mapValues { $0.toAny() }, forKeyedSubscript: "$widget" as NSString)
            context.setObject(actionID ?? "", forKeyedSubscript: "__hanlinAction" as NSString)
            context.setObject(!requiresRender, forKeyedSubscript: "__hanlinActionOnly" as NSString)
            var event: [String: Any] = ["parameters": actionParameters.toAny()]
            if let actionValue { event["value"] = actionValue }
            context.setObject(event, forKeyedSubscript: "__hanlinEvent" as NSString)
            let expand: @convention(block) () -> Void = {
                guard case let .object(presentation)? = environment["presentation"],
                      presentation["kind"] == .string("translationUI") else {
                    completion.finish(.failure(HanlinScriptWidgetError("expandSheet is available in a translation presentation")))
                    return
                }
                presentationEffect.expandsSheet = true
            }
            let finish: @convention(block) (JSValue) -> Void = { value in
                guard case let .object(presentation)? = environment["presentation"],
                      presentation["kind"] == .string("translationUI") else {
                    completion.finish(.failure(HanlinScriptWidgetError("finish is available in a translation presentation")))
                    return
                }
                let text: String? = value.isNull || value.isUndefined ? nil : value.toString()
                presentationEffect.finishRequested = true
                presentationEffect.replacementText = text
            }
            context.setObject(expand, forKeyedSubscript: "__hanlinPresentationExpand" as NSString)
            context.setObject(finish, forKeyedSubscript: "__hanlinPresentationFinish" as NSString)
            context.evaluateScript("""
                globalThis.$presentation = {
                  expandSheet: __hanlinPresentationExpand,
                  finish: text => __hanlinPresentationFinish(text == null ? null : String(text))
                };
                """)
            let render: @convention(block) (ScriptWidgetRuntimeElement) -> Void = { rendered = $0 }
            let error: @convention(block) (String) -> Void = { completion.finish(.failure(HanlinScriptWidgetError($0))) }
            let finished: @convention(block) () -> Void = { [weak native] in
                guard let native, let current = JSContext.current() else {
                    completion.finish(.failure(HanlinScriptWidgetError("The native rendering session ended")))
                    return
                }
                let expanded = ["expandedLeading", "expandedCenter", "expandedTrailing", "expandedBottom"]
                    .filter { dynamicRegions[$0] != nil }
                let fallback = expanded.isEmpty
                    ? ["compactLeading", "compactTrailing", "minimal"].filter { dynamicRegions[$0] != nil } : expanded
                if requiresRender && rendered == nil && fallback.isEmpty {
                    completion.finish(.failure(HanlinScriptWidgetError("The script did not call $render or $dynamic_island")))
                    return
                }
                do {
                    var budget = FreezeBudget(deadline: deadline)
                    var active: Set<ObjectIdentifier> = []
                    var frozen: HanlinScriptWidgetPreparedNode?
                    if requiresRender, let rendered {
                        frozen = try freeze(rendered, depth: 1, budget: &budget, active: &active, context: current)
                    }
                    var regions: [String: HanlinScriptWidgetPreparedNode] = [:]
                    if requiresRender {
                        for (key, element) in dynamicRegions {
                            // The original engine validates each submitted
                            // Dynamic Island root separately.
                            budget.nodes = 0
                            regions[key] = try freeze(element, depth: 1, budget: &budget, active: &active, context: current)
                        }
                        if frozen == nil, !fallback.isEmpty {
                            frozen = .init(tag: "vstack", props: [:],
                                children: fallback.compactMap { regions[$0] }.map { .element($0) })
                        }
                    }
                    let island: HanlinScriptWidgetDynamicIsland? = regions.isEmpty ? nil : .init(
                        expandedLeading: regions["expandedLeading"], expandedTrailing: regions["expandedTrailing"],
                        expandedCenter: regions["expandedCenter"], expandedBottom: regions["expandedBottom"],
                        compactLeading: regions["compactLeading"], compactTrailing: regions["compactTrailing"], minimal: regions["minimal"])
                    try budget.checkTime()
                    completion.finish(.success(.init(node: frozen, values: try HanlinWidgetJSON.dictionary(native.values()),
                        presentationEffect: presentationEffect, dynamicIsland: island)))
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
            dynamicRegions.removeAll()
            context.exceptionHandler = nil
            for key in ["$render", "$dynamic_island", "$component", "$error", "$storage", "$presentation", "__hanlinPresentationExpand", "__hanlinPresentationFinish", "__hanlinFinishWidget", "__hanlinGetWidgetValue", "__hanlinSetWidgetValue"] {
                context.setObject(nil, forKeyedSubscript: key as NSString)
            }
        }
        return try result.get()
    }

    private struct FreezeBudget {
        let deadline: ContinuousClock.Instant
        var nodes = 0
        func checkTime() throws {
            guard ContinuousClock.now < deadline else { throw HanlinScriptWidgetError("Widget execution budget exceeded") }
        }
        mutating func node() throws {
            try checkTime()
            guard nodes < HanlinOriginalScriptWidgetSession.maximumElementNodes else {
                throw HanlinScriptWidgetError("Original ScriptWidget element-node limit exceeded")
            }
            nodes += 1
        }
        func value(_ object: Any) throws -> HanlinValue {
            try checkTime()
            return try HanlinWidgetJSON.value(object)
        }
    }

    private func singleFragmentElement(_ values: [Any], budget: FreezeBudget) throws -> ScriptWidgetRuntimeElement? {
        var flattened: [Any] = []
        var activeArrays: Set<ObjectIdentifier> = []
        func append(_ value: Any) throws {
            try budget.checkTime()
            if let nested = value as? NSArray {
                let identifier = ObjectIdentifier(nested)
                guard activeArrays.insert(identifier).inserted else {
                    throw HanlinScriptWidgetError("Widget child array contains a cycle")
                }
                defer { activeArrays.remove(identifier) }
                for child in nested { try append(child) }
            } else {
                flattened.append(value)
            }
        }
        for value in values { try append(value) }
        guard flattened.count == 1 else { return nil }
        return flattened[0] as? ScriptWidgetRuntimeElement
    }

    // Source-derived component resolution, performed only by the VM owner.
    private func freeze(_ input: ScriptWidgetRuntimeElement, depth: Int, budget: inout FreezeBudget,
                        active: inout Set<ObjectIdentifier>, context: JSContext,
                        unwrapFragment: Bool = true) throws -> HanlinScriptWidgetPreparedNode {
        guard depth <= HanlinOriginalScriptWidgetSession.maximumElementDepth else {
            throw HanlinScriptWidgetError("Original ScriptWidget element-depth limit exceeded")
        }
        try budget.checkTime()
        var element = input
        var inserted: [ObjectIdentifier] = []
        defer { inserted.forEach { active.remove($0) } }
        for _ in 0..<HanlinOriginalScriptWidgetSession.maximumElementDepth {
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
        guard let tag = element.tagAsString() else {
            throw HanlinScriptWidgetError("Invalid native widget element")
        }
        // Upstream normalizes only a single-element root Fragment, keeping the
        // same depth. Its discarded wrapper must not consume an element slot.
        if unwrapFragment, tag == "Fragment",
           let child = try singleFragmentElement(element.getChildren(), budget: budget) {
            return try freeze(child, depth: depth, budget: &budget, active: &active, context: context)
        }
        try budget.node()
        guard element.getProps().count <= HanlinOriginalScriptWidgetSession.maximumPropsPerElement else {
            throw HanlinScriptWidgetError("Invalid native widget element")
        }
        var props: [String: HanlinValue] = [:]
        for (key, value) in element.getProps() {
            guard let key = key as? String else { throw HanlinScriptWidgetError("Invalid property key") }
            props[key] = try budget.value(value)
        }
        var children: [HanlinScriptWidgetPreparedNode.Child] = []
        var activeArrays: Set<ObjectIdentifier> = []
        func append(_ value: Any) throws {
            try budget.checkTime()
            if let child = value as? ScriptWidgetRuntimeElement {
                children.append(.element(try freeze(child, depth: depth + 1, budget: &budget, active: &active, context: context, unwrapFragment: false)))
            } else if let nested = value as? NSArray {
                let identifier = ObjectIdentifier(nested)
                guard activeArrays.insert(identifier).inserted else {
                    throw HanlinScriptWidgetError("Widget child array contains a cycle")
                }
                defer { activeArrays.remove(identifier) }
                for item in nested { try append(item) }
            } else {
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


private struct HanlinScriptWidgetEvaluation: Sendable {
    let node: HanlinScriptWidgetPreparedNode?
    let values: [String: HanlinValue]
    let presentationEffect: HanlinNativePresentationEffect
    let dynamicIsland: HanlinScriptWidgetDynamicIsland?
}

/// Only immutable native values cross the JavaScript queue/caller boundary.
private final class HanlinScriptWidgetCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private let signal = DispatchSemaphore(value: 0)
    private var result: Result<HanlinScriptWidgetEvaluation, Error>?
    func finish(_ result: Result<HanlinScriptWidgetEvaluation, Error>) {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return }
        self.result = result
        lock.unlock()
        signal.signal()
    }
    func wait(until deadline: ContinuousClock.Instant) -> Result<HanlinScriptWidgetEvaluation, Error> {
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
