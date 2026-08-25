@preconcurrency import JavaScriptCore
import CoreFoundation
import Foundation
import HanlinPlatformContracts
import HanlinScriptUI

@MainActor
final class HanlinScriptingApplicationSession {
    let model: HanlinScriptUIModel

    private let context: JSContext
    private let virtualMachine: JSVirtualMachine
    private let storage: HanlinScriptingPackageStorage
    private var disposed = false

    init(
        installedPackageID: HanlinInstalledPackageID,
        program: String,
        filename: String,
        storageAllowed: Bool
    ) throws {
        guard let virtualMachine = JSVirtualMachine(),
              let context = JSContext(virtualMachine: virtualMachine) else {
            throw HanlinScriptingApplicationError.runtimeInitializationFailed
        }
        self.virtualMachine = virtualMachine
        self.context = context
        storage = try HanlinScriptingPackageStorage(
            installedPackageID: installedPackageID,
            allowed: storageAllowed
        )

        let router = HanlinScriptingUIEventRouter()
        model = HanlinScriptUIModel(root: .init(kind: .fragment)) { handlerID, payload in
            router.dispatch(handlerID: handlerID, payload: payload)
        }
        router.session = self

        installNativeBridges()
        try evaluate(Self.bootstrap, filename: "hanlin-scripting-ui-runtime.js")
        try evaluate(program, filename: filename)
        guard context.objectForKeyedSubscript("__hanlinHasPresentedUI")?.toBool() == true else {
            throw HanlinScriptingApplicationError.missingPresentedUI
        }
    }

    func dispatch(handlerID: String, payload: HanlinValue) {
        guard !disposed,
              let payloadJSON = try? payload.jsonValue(destination: .javaScriptBinary64).canonicalJSONData(),
              let payloadString = String(data: payloadJSON, encoding: .utf8),
              let handlerLiteral = Self.javaScriptLiteral(handlerID),
              let payloadLiteral = Self.javaScriptLiteral(payloadString) else { return }
        do {
            try evaluate(
                "globalThis.__hanlinDispatch(\(handlerLiteral), \(payloadLiteral));",
                filename: "hanlin-event.js"
            )
        } catch {
            // Runtime errors remain contained to this package session. The UI keeps
            // its last valid tree rather than replacing it with an unsafe partial tree.
        }
    }

    func dismiss() {
        guard !disposed else { return }
        context.evaluateScript("globalThis.__hanlinDismiss?.();")
        dispose()
    }

    func dispose() {
        guard !disposed else { return }
        disposed = true
        context.evaluateScript("globalThis.__hanlinDispose?.();")
        context.exceptionHandler = nil
        context.setObject(nil, forKeyedSubscript: "__hanlinNativeRender" as NSString)
        context.setObject(nil, forKeyedSubscript: "__hanlinNativeStorageGet" as NSString)
        context.setObject(nil, forKeyedSubscript: "__hanlinNativeStorageSet" as NSString)
        context.setObject(nil, forKeyedSubscript: "__hanlinNativeStorageClear" as NSString)
    }

    private func installNativeBridges() {
        let render: @convention(block) (String) -> Void = { [weak self] json in
            guard let self, !self.disposed,
                  json.utf8.count <= 1_048_576,
                  let data = json.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let node = try? Self.decodeNode(object, depth: 0) else { return }
            try? self.model.apply(.render(node))
        }
        let storageGet: @convention(block) (String) -> String = { [storage] key in
            storage.response(for: key)
        }
        let storageSet: @convention(block) (String, String) -> Bool = { [storage] key, json in
            storage.set(json: json, for: key)
        }
        let storageClear: @convention(block) () -> Bool = { [storage] in storage.clear() }
        context.setObject(render, forKeyedSubscript: "__hanlinNativeRender" as NSString)
        context.setObject(storageGet, forKeyedSubscript: "__hanlinNativeStorageGet" as NSString)
        context.setObject(storageSet, forKeyedSubscript: "__hanlinNativeStorageSet" as NSString)
        context.setObject(storageClear, forKeyedSubscript: "__hanlinNativeStorageClear" as NSString)
    }

    private func evaluate(_ source: String, filename: String) throws {
        var exception: JSValue?
        context.exceptionHandler = { _, value in exception = value }
        context.evaluateScript(
            source,
            withSourceURL: URL(string: "hanlin-package:///\(filename)")
        )
        context.exceptionHandler = nil
        if let exception {
            let message = exception.toString() ?? "script_failure"
            throw HanlinScriptingApplicationError.evaluationFailed(String(message.prefix(512)))
        }
    }

    private static func decodeNode(_ value: Any, depth: Int) throws -> HanlinScriptUINode {
        guard depth <= 128,
              let object = value as? [String: Any],
              let kindName = object["kind"] as? String,
              let kind = HanlinScriptUIPrimitive(rawValue: kindName) else {
            throw HanlinScriptingApplicationError.invalidUITree
        }
        let properties = try (object["properties"] as? [String: Any] ?? [:]).mapValues {
            try bridgeValue($0, depth: depth + 1)
        }
        let children = try (object["children"] as? [Any] ?? []).map {
            try decodeNode($0, depth: depth + 1)
        }
        return .init(
            kind: kind,
            key: object["key"] as? String,
            properties: properties,
            children: children
        )
    }

    private static func bridgeValue(_ value: Any, depth: Int) throws -> HanlinValue {
        guard depth <= 128 else { throw HanlinScriptingApplicationError.invalidUITree }
        switch value {
        case is NSNull:
            return .null
        case let value as String:
            return .string(value)
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() { return .bool(value.boolValue) }
            let double = value.doubleValue
            if double.rounded(.towardZero) == double,
               double >= Double(Int64.min), double <= Double(Int64.max) {
                return .integer(value.int64Value)
            }
            return try .finiteNumber(double)
        case let value as [Any]:
            return .array(try value.map { try bridgeValue($0, depth: depth + 1) })
        case let value as [String: Any]:
            return .object(try HanlinObject(uniqueMembers: value.map {
                (key: $0.key, value: try bridgeValue($0.value, depth: depth + 1))
            }))
        default:
            throw HanlinScriptingApplicationError.invalidUITree
        }
    }

    private static func javaScriptLiteral(_ value: String) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

@MainActor
private final class HanlinScriptingUIEventRouter {
    weak var session: HanlinScriptingApplicationSession?

    func dispatch(handlerID: String, payload: HanlinValue) {
        session?.dispatch(handlerID: handlerID, payload: payload)
    }
}

private final class HanlinScriptingPackageStorage: @unchecked Sendable {
    private let lock = NSLock()
    private let defaults: UserDefaults
    private let suiteName: String
    private let allowed: Bool
    private let maximumBytes = 1_048_576

    init(installedPackageID: HanlinInstalledPackageID, allowed: Bool) throws {
        let suiteName = "com.hanlin.scripting.storage.\(installedPackageID.rawValue)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw HanlinScriptingApplicationError.storageInitializationFailed
        }
        self.defaults = defaults
        self.suiteName = suiteName
        self.allowed = allowed
    }

    func response(for key: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        guard allowed, Self.valid(key: key) else { return #"{"allowed":false}"# }
        guard let json = defaults.string(forKey: key) else { return #"{"allowed":true,"found":false}"# }
        guard let encoded = try? JSONEncoder().encode(json),
              let literal = String(data: encoded, encoding: .utf8) else {
            return #"{"allowed":true,"found":false}"#
        }
        return #"{"allowed":true,"found":true,"json":\#(literal)}"#
    }

    func set(json: String, for key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard allowed, Self.valid(key: key), json.utf8.count <= maximumBytes,
              let data = json.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil else {
            return false
        }
        let existingValues = defaults.persistentDomain(forName: suiteName) ?? [:]
        let existingBytes = existingValues.keys.reduce(0) {
            $0 + ((existingValues[$1] as? String)?.utf8.count ?? 0)
        }
        let replacedBytes = defaults.string(forKey: key)?.utf8.count ?? 0
        guard existingBytes - replacedBytes + json.utf8.count <= maximumBytes else { return false }
        defaults.set(json, forKey: key)
        return true
    }

    func clear() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard allowed else { return false }
        defaults.removePersistentDomain(forName: suiteName)
        return true
    }

    private static func valid(key: String) -> Bool {
        !key.isEmpty && key.utf8.count <= 1_024 && !key.contains("\0")
    }
}

private enum HanlinScriptingApplicationError: Error, LocalizedError {
    case runtimeInitializationFailed
    case storageInitializationFailed
    case evaluationFailed(String)
    case invalidUITree
    case missingPresentedUI

    var errorDescription: String? {
        switch self {
        case .runtimeInitializationFailed: "The Scripting JavaScript runtime could not be created."
        case .storageInitializationFailed: "Package-scoped storage could not be created."
        case let .evaluationFailed(message): "The script failed during launch: \(message)"
        case .invalidUITree: "The script produced an invalid or unsupported UI tree."
        case .missingPresentedUI: "The app entrypoint did not call Navigation.present."
        }
    }
}

private extension HanlinScriptingApplicationSession {
    static let bootstrap = #"""
    (() => {
      "use strict";
      const state = [];
      const effects = new Map();
      const handlers = new Map();
      const contexts = new Map();
      let hookCursor = 0;
      let handlerCursor = 0;
      let presentedElement = null;
      let dismissPresentation = null;
      let rendering = false;
      let renderPending = false;

      const hostKinds = Object.freeze({
        Text: "text", Image: "image", Button: "button", TextField: "textField",
        SecureField: "textField", HStack: "hStack", VStack: "vStack", ZStack: "zStack",
        ScrollView: "scrollView", Group: "group", Spacer: "spacer", Divider: "divider",
        ProgressView: "progress", NavigationStack: "navigationStack",
        NavigationLink: "navigationLink", TabView: "tabView", Tab: "tab",
        List: "scrollView", Form: "scrollView", Section: "group", GroupBox: "group",
        LazyVStack: "vStack", LazyVGrid: "vStack", Grid: "vStack", LazyHStack: "hStack",
        LazyHGrid: "hStack", ControlGroup: "hStack", Toolbar: "group", ToolbarItem: "group",
        Label: "hStack", Menu: "menu", Link: "button", Toggle: "toggle", Picker: "group",
        Slider: "progress", BarChart: "barChart", Chart: "chart",
        RoundedRectangle: "roundedRectangle", Rectangle: "rectangle", Capsule: "roundedRectangle",
        Circle: "circle", ContentUnavailableView: "vStack", EmptyView: "group", Markdown: "text"
      });

      function flatten(value, output = []) {
        if (Array.isArray(value)) value.forEach(item => flatten(item, output));
        else if (value !== null && value !== undefined && value !== false && value !== true) output.push(value);
        return output;
      }

      function component(type, properties, children) {
        return { __hanlinComponent: true, type, properties, children };
      }

      function createElement(type, properties, ...children) {
        const props = properties == null ? {} : { ...properties };
        const normalizedChildren = flatten(children);
        props.children = normalizedChildren.length === 1 ? normalizedChildren[0] : normalizedChildren;
        if (type === Fragment) return normalizedChildren;
        if (typeof type !== "function") throw new TypeError("HANLIN_UI:invalid_component");
        if (type.__hanlinKind) return {
          __hanlinHost: true, kind: type.__hanlinKind, hostName: type.__hanlinName,
          properties: props, children: normalizedChildren
        };
        return component(type, props, normalizedChildren);
      }

      function Fragment(properties) { return properties?.children ?? []; }

      for (const [name, kind] of Object.entries(hostKinds)) {
        const marker = function HanlinHostComponent() {};
        Object.defineProperty(marker, "__hanlinKind", { value: kind });
        Object.defineProperty(marker, "__hanlinName", { value: name });
        Object.defineProperty(globalThis, name, { configurable: false, enumerable: true, value: marker });
      }

      function nextState(initialValue) {
        const index = hookCursor++;
        if (!(index in state)) state[index] = typeof initialValue === "function" ? initialValue() : initialValue;
        return index;
      }

      function useState(initialValue) {
        const index = nextState(initialValue);
        return [state[index], value => {
          state[index] = typeof value === "function" ? value(state[index]) : value;
          requestRender();
        }];
      }

      function useObservable(initialValue) {
        const index = nextState(initialValue);
        return Object.freeze({
          __hanlinObservable: true,
          get value() { return state[index]; },
          setValue(value) { state[index] = typeof value === "function" ? value(state[index]) : value; requestRender(); }
        });
      }

      function useRef(initialValue) {
        const index = nextState({ current: initialValue });
        return state[index];
      }

      function dependenciesChanged(left, right) {
        return !left || left.length !== right.length || right.some((value, index) => !Object.is(value, left[index]));
      }

      function useMemo(factory, dependencies = []) {
        const index = nextState(null);
        const previous = state[index];
        if (!previous || dependenciesChanged(previous.dependencies, dependencies)) {
          state[index] = { dependencies: [...dependencies], value: factory() };
        }
        return state[index].value;
      }

      function useCallback(callback, dependencies = []) { return useMemo(() => callback, dependencies); }

      function useEffect(setup, dependencies = []) {
        const index = hookCursor++;
        const previous = effects.get(index);
        if (dependenciesChanged(previous?.dependencies, dependencies)) {
          previous?.dispose?.();
          const dispose = setup();
          effects.set(index, { dependencies: [...dependencies], dispose: typeof dispose === "function" ? dispose : null });
        }
      }

      function useEffectEvent(callback) { return (...argumentsList) => callback(...argumentsList); }
      function createContext(defaultValue) {
        const id = Symbol("HanlinContext");
        contexts.set(id, defaultValue);
        return Object.freeze({
          __hanlinContext: id,
          Provider: ({ value, children }) => { contexts.set(id, value); return children; }
        });
      }
      function useContext(context) { return contexts.get(context.__hanlinContext); }

      function registerHandler(callback) {
        const id = `event-${handlerCursor++}`;
        handlers.set(id, callback);
        return id;
      }

      function sanitize(value, depth = 0) {
        if (depth > 64) throw new TypeError("HANLIN_UI:property_depth");
        if (value === undefined || value === null) return null;
        if (typeof value === "function") return registerHandler(value);
        if (typeof value === "string" || typeof value === "boolean") return value;
        if (typeof value === "number") {
          if (!Number.isFinite(value)) throw new TypeError("HANLIN_UI:non_finite_number");
          return value;
        }
        if (typeof value === "bigint") return value.toString();
        if (value.__hanlinObservable) return sanitize(value.value, depth + 1);
        if (value instanceof Date) return value.toISOString();
        if (Array.isArray(value)) return value.map(item => sanitize(item, depth + 1));
        if (value.__hanlinComponent || value.__hanlinHost) return null;
        const output = {};
        for (const [key, member] of Object.entries(value)) output[key] = sanitize(member, depth + 1);
        return output;
      }

      function materialize(value) {
        if (value === null || value === undefined || value === false || value === true) return [];
        if (Array.isArray(value)) return flatten(value.map(materialize));
        if (typeof value === "string" || typeof value === "number" || typeof value === "bigint") {
          return [{ kind: "text", key: null, properties: { text: String(value) }, children: [] }];
        }
        if (value.__hanlinComponent) return materialize(value.type(value.properties));
        if (!value.__hanlinHost) throw new TypeError("HANLIN_UI:invalid_node");
        let children = flatten(value.children.map(materialize));
        if (value.hostName === "Section") {
          children = [
            ...materialize(value.properties.header),
            ...children,
            ...materialize(value.properties.footer)
          ];
        }
        const properties = {};
        for (const [key, member] of Object.entries(value.properties)) {
          if (key !== "children") properties[key] = sanitize(member);
        }
        if (value.kind === "text" && properties.text == null) {
          properties.text = children.filter(child => child.kind === "text").map(child => child.properties.text).join("");
        }
        if (value.kind === "button") {
          properties.onPress = properties.action ?? properties.onPress ?? properties.onChanged ?? null;
          properties.title = properties.title ?? properties.label ?? "";
        }
        if (value.kind === "toggle") {
          const source = value.properties.value ?? value.properties.isOn;
          const current = source?.__hanlinObservable ? source.value : source;
          properties.value = current === true;
          properties.onChange = registerHandler(next => {
            if (source?.__hanlinObservable) source.setValue(next);
            if (typeof value.properties.onChanged === "function") value.properties.onChanged(next);
          });
        }
        if (value.kind === "textField") properties.onChange = properties.onChanged ?? properties.onChange ?? null;
        if (value.kind === "tabView" && value.properties.selection?.__hanlinObservable) {
          properties.onChange = registerHandler(selectedValue => {
            const current = value.properties.selection.value;
            value.properties.selection.setValue(
              typeof current === "number" ? Number(selectedValue) : selectedValue
            );
          });
        }
        if (value.kind === "tab") properties.id = String(properties.value ?? properties.id ?? properties.title ?? "tab");
        const node = {
          kind: value.kind,
          key: value.properties.key == null ? null : String(value.properties.key),
          properties,
          children
        };
        const presentations = [];
        for (const [propertyName, style, contentName] of [
          ["sheet", "sheet", "content"],
          ["fullScreenCover", "fullScreen", "content"],
          ["confirmationDialog", "dialog", "actions"]
        ]) {
          const configured = value.properties[propertyName];
          const candidates = Array.isArray(configured) ? configured : configured ? [configured] : [];
          const active = candidates.find(candidate => {
            const presented = candidate?.isPresented;
            return presented?.__hanlinObservable ? presented.value === true : presented === true;
          });
          if (active) {
            const onDismiss = registerHandler(() => {
              if (active.isPresented?.__hanlinObservable) active.isPresented.setValue(false);
              if (typeof active.onChanged === "function") active.onChanged(false);
            });
            presentations.push({
              kind: "presentation", key: null,
              properties: {
                id: `${style}-${onDismiss}`, style, onDismiss,
                title: active.title ?? "", message: active.message ?? ""
              },
              children: materialize(active[contentName])
            });
            break;
          }
        }
        return [node, ...presentations];
      }

      function render() {
        if (rendering || presentedElement == null) { renderPending = true; return; }
        rendering = true;
        try {
          hookCursor = 0;
          handlerCursor = 0;
          handlers.clear();
          const nodes = materialize(presentedElement);
          const root = nodes.length === 1 ? nodes[0] : { kind: "fragment", key: null, properties: {}, children: nodes };
          __hanlinNativeRender(JSON.stringify(root));
        } finally {
          rendering = false;
          if (renderPending) { renderPending = false; render(); }
        }
      }

      function requestRender() { render(); }

      function ForEach(properties) {
        const source = properties.data ?? properties.values ?? [];
        const data = source?.__hanlinObservable ? source.value : source;
        const builder = properties.builder ?? properties.children;
        if (!Array.isArray(data) || typeof builder !== "function") return [];
        return data.map((item, index) => builder(item, index));
      }

      const Navigation = Object.freeze({
        present(options) {
          globalThis.__hanlinHasPresentedUI = true;
          presentedElement = options && Object.hasOwn(options, "element") ? options.element : options;
          render();
          return new Promise(resolve => { dismissPresentation = resolve; });
        },
        useDismiss() { return value => { dismissPresentation?.(value); dismissPresentation = null; }; }
      });
      const Storage = Object.freeze({
        get(key) {
          const response = JSON.parse(__hanlinNativeStorageGet(String(key)));
          if (!response.allowed) throw new Error("HANLIN_PERMISSION:storage");
          return response.found ? JSON.parse(response.json) : null;
        },
        set(key, value) {
          if (!__hanlinNativeStorageSet(String(key), JSON.stringify(value))) throw new Error("HANLIN_STORAGE:write_failed");
        },
        remove(key) { return this.set(key, null); },
        clear() { if (!__hanlinNativeStorageClear()) throw new Error("HANLIN_STORAGE:clear_failed"); }
      });
      const Script = Object.freeze({
        name: "Hanlin Scripting App", queryParameters: {}, shareFiles: [],
        exit() {}, minimize() {}, onResume() { return () => {}; }
      });
      const Device = Object.freeze({ systemLanguageCode: "en", systemName: "iOS" });
      const Widget = Object.freeze({ family: "systemMedium", reloadAll() {}, present() {} });
      const AppIntentProtocol = Object.freeze({ AppIntent: "AppIntent" });
      const AppIntentManager = Object.freeze({ register(options) { return options; } });

      Object.assign(globalThis, {
        createElement, Fragment, useState, useObservable, useRef, useMemo, useCallback,
        useEffect, useEffectEvent, createContext, useContext, ForEach, Navigation,
        Storage, Script, Device, Widget, AppIntentProtocol, AppIntentManager,
        Color: Object.freeze({}),
        __hanlinHasPresentedUI: false,
        __hanlinDispatch(handlerID, payloadJSON) {
          const handler = handlers.get(handlerID);
          if (typeof handler !== "function") throw new Error("HANLIN_UI:unknown_handler");
          const result = handler(JSON.parse(payloadJSON));
          Promise.resolve(result).catch(() => {});
        },
        __hanlinDismiss() { dismissPresentation?.(null); dismissPresentation = null; },
        __hanlinDispose() {
          for (const effect of effects.values()) effect.dispose?.();
          effects.clear(); handlers.clear(); presentedElement = null;
        }
      });
    })();
    """#
}
