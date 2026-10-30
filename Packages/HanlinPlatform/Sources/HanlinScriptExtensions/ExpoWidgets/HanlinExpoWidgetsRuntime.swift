import Foundation
import JavaScriptCore

public struct HanlinExpoWidgetError: Error, LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct HanlinExpoWidgetsRuntime: Sendable {
    public static let shared = HanlinExpoWidgetsRuntime()


    private init() {}

    public func renderNodeSync(
        layout: String,
        props: [String: Any]? = nil,
        environment: [String: Any] = [:]
    ) -> [String: Any]? {
        switch render(layout: layout, props: props, environment: environment) {
        case let .success(dict): return dict
        case .failure: return nil
        }
    }

    public func render(
        layout: String,
        props: [String: Any]? = nil,
        environment: [String: Any] = [:]
    ) -> Result<[String: Any], HanlinExpoWidgetError> {
        call(layout: layout, functionName: "__expoWidgetRender") { ctx in
            [props.map { $0 } ?? JSValue(undefinedIn: ctx) as Any, environment]
        }.flatMap { result in
            guard let dict = result as? [String: Any] else {
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
            result as? [String: Any]
        }
    }

    private func call(
        layout: String,
        functionName: String,
        arguments: (JSContext) -> [Any]
    ) -> Result<Any?, HanlinExpoWidgetError> {
        guard let ctx = getContext() else {
            return .failure(HanlinExpoWidgetError("Could not initialize JavaScriptCore context."))
        }

        guard layout.utf8.count <= 2 * 1_024 * 1_024 else { return .failure(.init("Expo layout exceeds its compiled-source budget")) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        let checkExecution: @convention(block) () -> Void = {
            if ContinuousClock.now >= deadline, let current = JSContext.current() {
                current.exception = JSValue(newErrorFromMessage: "Widget execution budget exceeded", in: current)
            }
        }
        ctx.setObject(checkExecution, forKeyedSubscript: "__scriptWidgetCheckExecution" as NSString)

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

        // Drop callback functions inside the owner VM. JSON is the immutable
        // transfer boundary; native views never receive a JSValue or closure.
        guard let res, !res.isUndefined, !res.isNull else { return .success(nil) }
        guard let json = ctx.objectForKeyedSubscript("JSON")?.invokeMethod("stringify", withArguments: [res])?.toString(),
              let data = json.data(using: .utf8), data.count <= 256 * 1_024,
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return .failure(.init("Expo output is not bounded JSON"))
        }
        guard ContinuousClock.now < deadline else { return .failure(.init("Expo execution budget exceeded")) }
        return .success(object)
    }

    private func getContext() -> JSContext? {
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

        return ctx
    }

    private func getBundleScript() -> String? { Self.bundleScript }

    // Only immutable resources embedded in the executable are trusted runtime code.
    private static let bundleScript: String? = {
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: "ExpoWidgets", withExtension: "bundle"),
           let value = try? String(contentsOf: url, encoding: .utf8) { return value }
        #endif
        if let url = Bundle.main.url(forResource: "ExpoWidgets", withExtension: "bundle"),
           let value = try? String(contentsOf: url, encoding: .utf8) { return value }
        return nil
    }()
}
