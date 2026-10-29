import Foundation
import JavaScriptCore

public struct HanlinScriptWidgetError: Error, LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public final class HanlinScriptWidgetRuntime: @unchecked Sendable {
    public static let shared = HanlinScriptWidgetRuntime()

    private let lock = NSRecursiveLock()
    private var compilerContext: JSContext?
    private var runtimeContext: JSContext?
    private var coreJs: String?
    private var momentJs: String?

    private init() {}

    public func execute(
        script: String,
        environment: [String: Any] = [:]
    ) -> Result<HanlinScriptWidgetElement, HanlinScriptWidgetError> {
        lock.lock()
        defer { lock.unlock() }

        // 1. Compile JSX to JS if needed
        let jsCode: String
        if script.contains("<") && script.contains(">") {
            switch compileJSX(script) {
            case let .success(compiled):
                jsCode = compiled
            case let .failure(err):
                return .failure(err)
            }
        } else {
            jsCode = script
        }

        // 2. Prepare runtime execution context
        guard let ctx = getRuntimeContext() else {
            return .failure(HanlinScriptWidgetError("Could not create JavaScript runtime context."))
        }

        ctx.exception = nil

        // Set environment variables
        for (k, v) in environment {
            ctx.setObject(v, forKeyedSubscript: k as NSString)
        }

        // Wrap execution in an IIFE to capture the return value
        let wrapped = """
        (function() {
            var __renderResult = null;
            function render(elem) { __renderResult = elem; return elem; }
            \(jsCode)
            if (typeof main === 'function') {
                var res = main();
                if (res) return res;
            }
            if (__renderResult) return __renderResult;
            return null;
        })()
        """

        let result = ctx.evaluateScript(wrapped)
        if let exception = ctx.exception {
            let msg = exception.toString() ?? "Script evaluation error"
            ctx.exception = nil
            return .failure(HanlinScriptWidgetError(msg))
        }

        guard let result, !result.isUndefined, !result.isNull else {
            return .failure(HanlinScriptWidgetError("Script did not return a widget element."))
        }

        guard let dict = result.toObject() as? [String: Any] else {
            return .failure(HanlinScriptWidgetError("Script result was not an element dictionary."))
        }

        return .success(HanlinScriptWidgetElement(dictionary: dict))
    }

    public func compileJSX(_ jsx: String) -> Result<String, HanlinScriptWidgetError> {
        guard let ctx = getCompilerContext() else {
            return .failure(HanlinScriptWidgetError("Could not initialize Babel compiler context."))
        }

        ctx.exception = nil
        guard let transformFn = ctx.objectForKeyedSubscript("HanlinBabelTransform"), !transformFn.isUndefined else {
            return .failure(HanlinScriptWidgetError("HanlinBabelTransform not available."))
        }

        let res = transformFn.call(withArguments: [jsx])
        if let exception = ctx.exception {
            let msg = exception.toString() ?? "Babel transformation failed"
            ctx.exception = nil
            return .failure(HanlinScriptWidgetError("JSX compilation error: \(msg)"))
        }

        guard let transformed = res?.toString() else {
            return .failure(HanlinScriptWidgetError("Babel transform produced empty output."))
        }

        return .success(transformed)
    }

    private func getCompilerContext() -> JSContext? {
        if let compilerContext { return compilerContext }
        guard let ctx = JSContext() else { return nil }

        guard let core = getResourceString(fileName: "core.js") else {
            print("[HanlinScriptWidget] Missing core.js for Babel compilation")
            return nil
        }

        ctx.evaluateScript(core)
        ctx.evaluateScript("""
        function HanlinBabelTransform(source) {
            return Babel.transform(source, {
                presets: ['react'],
                plugins: []
            }).code;
        }
        """)

        self.compilerContext = ctx
        return ctx
    }

    private func getRuntimeContext() -> JSContext? {
        if let runtimeContext { return runtimeContext }
        guard let ctx = JSContext() else { return nil }

        // Setup React.createElement stub for JSX runtime
        ctx.evaluateScript("""
        var React = {
            createElement: function(tag, props) {
                var children = [];
                for (var i = 2; i < arguments.length; i++) {
                    var child = arguments[i];
                    if (Array.isArray(child)) {
                        for (var j = 0; j < child.length; j++) children.push(child[j]);
                    } else if (child !== null && child !== undefined) {
                        children.push(child);
                    }
                }
                return {
                    tag: typeof tag === 'string' ? tag : (tag.name || 'custom'),
                    props: props || {},
                    children: children
                };
            }
        };
        var createElement = React.createElement;
        """)

        if let moment = getResourceString(fileName: "moment.min.js") {
            ctx.evaluateScript(moment)
        }

        self.runtimeContext = ctx
        return ctx
    }

    private func getResourceString(fileName: String) -> String? {
        // 1. Try Bundle.main url for support.bundle/fileName
        if let bundleURL = Bundle.main.url(forResource: "support", withExtension: "bundle"),
           let bundle = Bundle(url: bundleURL),
           let fileURL = bundle.url(forResource: fileName, withExtension: nil),
           let content = try? String(contentsOf: fileURL, encoding: .utf8) {
            return content
        }

        // 2. Try Bundle.module for support.bundle/fileName
        #if SWIFT_PACKAGE
        if let bundleURL = Bundle.module.url(forResource: "support", withExtension: "bundle"),
           let bundle = Bundle(url: bundleURL),
           let fileURL = bundle.url(forResource: fileName, withExtension: nil),
           let content = try? String(contentsOf: fileURL, encoding: .utf8) {
            return content
        }
        #endif

        // 3. Try App Group folder
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.itorah.chavrusachat") {
            let fileURL = container.appending(path: "ScriptingExtensions/support.bundle/\(fileName)")
            if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                return content
            }
        }

        return nil
    }
}
