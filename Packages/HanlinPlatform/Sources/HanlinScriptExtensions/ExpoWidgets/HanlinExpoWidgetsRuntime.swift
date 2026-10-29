import Foundation
import JavaScriptCore

public struct HanlinExpoWidgetError: Error, LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public final class HanlinExpoWidgetsRuntime: @unchecked Sendable {
    public static let shared = HanlinExpoWidgetsRuntime()

    private let lock = NSRecursiveLock()
    private var context: JSContext?
    private var bundleScript: String?

    private init() {}

    public func render(
        layout: String,
        props: [String: Any]? = nil,
        environment: [String: Any] = [:]
    ) -> Result<[String: Any], HanlinExpoWidgetError> {
        call(layout: layout, functionName: "__expoWidgetRender") { ctx in
            [props.map { $0 } ?? JSValue(undefinedIn: ctx) as Any, environment]
        }.flatMap { result in
            guard let dict = result?.toObject() as? [String: Any] else {
                return .failure(HanlinExpoWidgetError("Expo widget render did not produce a dictionary node."))
            }
            return .success(dict)
        }
    }

    public func handlePress(
        layout: String,
        props: [String: Any] = [:],
        environment: [String: Any] = [:]
    ) -> Result<[String: Any]?, HanlinExpoWidgetError> {
        call(layout: layout, functionName: "__expoWidgetHandlePress") { _ in
            [props, environment]
        }.map { result in
            result?.toObject() as? [String: Any]
        }
    }

    private func call(
        layout: String,
        functionName: String,
        arguments: (JSContext) -> [Any]
    ) -> Result<JSValue?, HanlinExpoWidgetError> {
        lock.lock()
        defer { lock.unlock() }

        guard let ctx = getContext() else {
            return .failure(HanlinExpoWidgetError("Could not initialize JavaScriptCore context."))
        }

        ctx.exception = nil
        let layoutVal = ctx.evaluateScript("(\(layout))")
        if let exception = ctx.exception {
            let msg = exception.toString() ?? "Failed to evaluate layout function"
            ctx.exception = nil
            return .failure(HanlinExpoWidgetError("Layout evaluation error: \(msg)"))
        }

        guard let layoutVal, !layoutVal.isUndefined, !layoutVal.isNull else {
            return .failure(HanlinExpoWidgetError("Layout function evaluated to null/undefined."))
        }

        ctx.setObject(layoutVal, forKeyedSubscript: "__expoWidgetLayout" as NSString)

        guard let fn = ctx.objectForKeyedSubscript(functionName), !fn.isUndefined, fn.isObject else {
            return .failure(HanlinExpoWidgetError("Expo runtime function '\(functionName)' not found in global scope."))
        }

        let res = fn.call(withArguments: arguments(ctx))
        if let exception = ctx.exception {
            let msg = exception.toString() ?? "Unknown exception during '\(functionName)'"
            ctx.exception = nil
            return .failure(HanlinExpoWidgetError("Execution error in '\(functionName)': \(msg)"))
        }

        return .success(res)
    }

    private func getContext() -> JSContext? {
        if let context { return context }
        guard let ctx = JSContext() else { return nil }

        guard let script = getBundleScript() else {
            print("[HanlinExpoWidgets] Warning: Missing ExpoWidgets.bundle")
            return nil
        }

        ctx.evaluateScript(script)
        if let exception = ctx.exception {
            print("[HanlinExpoWidgets] Bundle evaluation error: \(exception.toString() ?? "unknown")")
            return nil
        }

        self.context = ctx
        return ctx
    }

    private func getBundleScript() -> String? {
        if let bundleScript { return bundleScript }

        // 1. Try Bundle.main (app extension bundle or host app)
        if let url = Bundle.main.url(forResource: "ExpoWidgets", withExtension: "bundle") {
            if let str = try? String(contentsOf: url, encoding: .utf8) {
                self.bundleScript = str
                return str
            }
            if let innerBundle = Bundle(url: url),
               let innerURL = innerBundle.url(forResource: "ExpoWidgets", withExtension: "bundle") ?? innerBundle.url(forResource: "ExpoWidgets", withExtension: "js"),
               let str = try? String(contentsOf: innerURL, encoding: .utf8) {
                self.bundleScript = str
                return str
            }
        }

        // 2. Try Bundle.module (SPM resource)
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: "ExpoWidgets", withExtension: "bundle"),
           let str = try? String(contentsOf: url, encoding: .utf8) {
            self.bundleScript = str
            return str
        }
        #endif

        // 3. Try App Group ScriptingExtensions directory
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.itorah.chavrusachat") {
            let fileURL = container.appending(path: "ScriptingExtensions/ExpoWidgets.bundle")
            if let str = try? String(contentsOf: fileURL, encoding: .utf8) {
                self.bundleScript = str
                return str
            }
        }

        return nil
    }
}
