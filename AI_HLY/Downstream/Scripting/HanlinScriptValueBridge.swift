enum HanlinScriptValueBridge {
    static let bootstrap = #"""
    (() => {
      "use strict";
      const limits = Object.freeze({
        maximumDepth: 64,
        maximumNodes: 100000,
        maximumArrayItems: 65536,
        maximumObjectMembers: 4096,
        maximumStringBytes: 1048576,
        maximumKeyBytes: 16384
      });
      const minimumInteger = -(1n << 63n);
      const maximumInteger = (1n << 63n) - 1n;
      const executeTools = [];

      function fail(code) {
        throw new TypeError(`HANLIN_BRIDGE:${code}`);
      }

      function checkText(value, maximum, code) {
        let length = 0;
        for (let index = 0; index < value.length; index += 1) {
          const first = value.charCodeAt(index);
          if (first <= 0x7f) length += 1;
          else if (first <= 0x7ff) length += 2;
          else if (first >= 0xd800 && first <= 0xdbff) {
            const second = value.charCodeAt(index + 1);
            if (!(second >= 0xdc00 && second <= 0xdfff)) fail("invalid_unicode");
            length += 4;
            index += 1;
          } else if (first >= 0xdc00 && first <= 0xdfff) {
            fail("invalid_unicode");
          } else length += 3;
          if (length > maximum) fail(code);
        }
      }

      function binary64FromHex(hex) {
        if (!/^[0-9a-f]{16}$/.test(hex)) fail("invalid_binary64");
        const bytes = new ArrayBuffer(8);
        const view = new DataView(bytes);
        view.setBigUint64(0, BigInt(`0x${hex}`), false);
        const value = view.getFloat64(0, false);
        if (!Number.isFinite(value)) fail("non_finite_number");
        return value;
      }

      function binary64Hex(value) {
        if (!Number.isFinite(value)) fail("non_finite_number");
        const bytes = new ArrayBuffer(8);
        const view = new DataView(bytes);
        view.setFloat64(0, value, false);
        return view.getBigUint64(0, false).toString(16).padStart(16, "0");
      }

      function decode(value, depth = 0, state = { nodes: 0 }) {
        if (depth > limits.maximumDepth) fail("depth_limit");
        state.nodes += 1;
        if (state.nodes > limits.maximumNodes) fail("node_limit");
        if (value === null || typeof value !== "object") fail("invalid_tagged_value");
        switch (value.type) {
        case "null": return null;
        case "bool":
          if (typeof value.value !== "boolean") fail("invalid_bool");
          return value.value;
        case "integer": {
          if (typeof value.value !== "string" || !/^-?(0|[1-9][0-9]*)$/.test(value.value)) {
            fail("invalid_integer");
          }
          const integer = BigInt(value.value);
          if (integer < minimumInteger || integer > maximumInteger) fail("integer_range");
          return integer;
        }
        case "number":
          return binary64FromHex(value.value);
        case "string":
          if (typeof value.value !== "string") fail("invalid_string");
          checkText(value.value, limits.maximumStringBytes, "string_limit");
          return value.value;
        case "data":
          fail("binary_unsupported");
          break;
        case "array":
          if (!Array.isArray(value.value) || value.value.length > limits.maximumArrayItems) {
            fail("array_limit");
          }
          return value.value.map((item) => decode(item, depth + 1, state));
        case "object": {
          if (value.value === null || typeof value.value !== "object" || Array.isArray(value.value)) {
            fail("invalid_object_member");
          }
          const keys = Object.keys(value.value);
          if (keys.length > limits.maximumObjectMembers) fail("object_limit");
          const object = Object.create(null);
          for (const key of keys) {
            checkText(key, limits.maximumKeyBytes, "key_limit");
            Object.defineProperty(object, key, {
              configurable: true,
              enumerable: true,
              writable: true,
              value: decode(value.value[key], depth + 1, state)
            });
          }
          return object;
        }
        default:
          fail("unknown_tag");
        }
      }

      function encode(value, depth = 0, state = { nodes: 0, active: new WeakSet() }) {
        if (depth > limits.maximumDepth) fail("depth_limit");
        state.nodes += 1;
        if (state.nodes > limits.maximumNodes) fail("node_limit");
        if (value === null) return { type: "null" };
        switch (typeof value) {
        case "boolean": return { type: "bool", value };
        case "string":
          checkText(value, limits.maximumStringBytes, "string_limit");
          return { type: "string", value };
        case "bigint":
          if (value < minimumInteger || value > maximumInteger) fail("integer_range");
          return { type: "integer", value: value.toString(10) };
        case "number":
          return { type: "number", value: binary64Hex(value) };
        case "undefined": fail("undefined_unsupported"); break;
        case "function": fail("function_unsupported"); break;
        case "symbol": fail("symbol_unsupported"); break;
        case "object": break;
        default: fail("unsupported_type");
        }
        if (state.active.has(value)) fail("cyclic_value");
        if (value instanceof Date) fail("date_unsupported");
        if (value instanceof ArrayBuffer || ArrayBuffer.isView(value)) {
          fail("binary_unsupported");
        }
        state.active.add(value);
        try {
          if (Array.isArray(value)) {
            if (value.length > limits.maximumArrayItems) fail("array_limit");
            return {
              type: "array",
              value: value.map((item) => encode(item, depth + 1, state))
            };
          }
          const prototype = Object.getPrototypeOf(value);
          if (prototype !== Object.prototype && prototype !== null) fail("object_prototype");
          const keys = Reflect.ownKeys(value);
          if (keys.length > limits.maximumObjectMembers) fail("object_limit");
          const members = Object.create(null);
          for (const key of keys) {
            if (typeof key !== "string") fail("symbol_key");
            checkText(key, limits.maximumKeyBytes, "key_limit");
            const descriptor = Object.getOwnPropertyDescriptor(value, key);
            if (!descriptor || !descriptor.enumerable) continue;
            if (!("value" in descriptor)) fail("accessor_unsupported");
            Object.defineProperty(members, key, {
              configurable: true,
              enumerable: true,
              writable: true,
              value: encode(descriptor.value, depth + 1, state)
            });
          }
          return { type: "object", value: members };
        } finally {
          state.active.delete(value);
        }
      }

      const assistantTool = {
        registerExecuteTool(execute) {
          if (typeof execute !== "function") fail("execute_not_function");
          if (executeTools.length >= 64) fail("tool_registration_limit");
          executeTools.push(execute);
          return async (parameters) => execute(parameters);
        }
      };

      Object.defineProperty(globalThis, "AssistantTool", {
        configurable: false,
        enumerable: true,
        writable: false,
        value: Object.freeze(assistantTool)
      });
      Object.defineProperty(globalThis, "__hanlinHasTool", {
        configurable: false,
        enumerable: false,
        writable: false,
        value: () => executeTools.length > 0
      });
      Object.defineProperty(globalThis, "__hanlinToolCount", {
        configurable: false,
        enumerable: false,
        writable: false,
        value: () => executeTools.length
      });
      Object.defineProperty(globalThis, "__hanlinInvoke", {
        configurable: false,
        enumerable: false,
        writable: false,
        value: async (canonicalInput) => {
          if (executeTools.length === 0) throw new Error("HANLIN_ABI:missing_execute_tool");
          const decoded = decode(JSON.parse(canonicalInput));
          const isNamedInvocation = decoded !== null
            && typeof decoded === "object"
            && !Array.isArray(decoded)
            && typeof decoded.__hanlinToolIndex === "bigint"
            && Object.hasOwn(decoded, "parameters");
          const toolIndex = isNamedInvocation ? Number(decoded.__hanlinToolIndex) : 0;
          if (!Number.isSafeInteger(toolIndex) || toolIndex < 0 || toolIndex >= executeTools.length) {
            throw new Error("HANLIN_ABI:unknown_tool");
          }
          const parameters = isNamedInvocation ? decoded.parameters : decoded;
          const result = await executeTools[toolIndex](parameters);
          if (result === null || typeof result !== "object") {
            throw new TypeError("HANLIN_ABI:invalid_tool_result");
          }
          const encodedResult = encode(result);
          const resultKeys = Reflect.ownKeys(result);
          if ((resultKeys.length !== 2 && resultKeys.length !== 3)
              || !resultKeys.includes("success")
              || !resultKeys.includes("message")
              || (resultKeys.length === 3 && !resultKeys.includes("data"))) {
            throw new TypeError("HANLIN_ABI:invalid_tool_result");
          }
          if (typeof result.success !== "boolean"
              || typeof result.message !== "string") {
            throw new TypeError("HANLIN_ABI:invalid_tool_result");
          }
          return JSON.stringify(encodedResult);
        }
      });
    })();
    """#
}
