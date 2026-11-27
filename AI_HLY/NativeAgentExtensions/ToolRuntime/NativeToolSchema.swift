import Foundation

enum NativeToolSchema {
    static func function(name: String, description: String, parameters: [String: Any]) -> [String: Any] {
        [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": parameters
            ]
        ]
    }

    static func object(properties: [String: Any], required: [String] = []) -> [String: Any] {
        var schema: [String: Any] = [
            "type": "object",
            "properties": properties,
            "additionalProperties": false
        ]
        if !required.isEmpty {
            schema["required"] = required
        }
        return schema
    }

    static func string(description: String, enumValues: [String]? = nil) -> [String: Any] {
        var schema: [String: Any] = ["type": "string", "description": description]
        if let enumValues { schema["enum"] = enumValues }
        return schema
    }

    static func boolean(description: String) -> [String: Any] {
        ["type": "boolean", "description": description]
    }

    static func number(description: String, minimum: Int? = nil, maximum: Int? = nil) -> [String: Any] {
        var schema: [String: Any] = ["type": "number", "description": description]
        if let minimum { schema["minimum"] = minimum }
        if let maximum { schema["maximum"] = maximum }
        return schema
    }

    static func integer(description: String, minimum: Int? = nil, maximum: Int? = nil) -> [String: Any] {
        var schema: [String: Any] = ["type": "integer", "description": description]
        if let minimum { schema["minimum"] = minimum }
        if let maximum { schema["maximum"] = maximum }
        return schema
    }

    static func stringArray(description: String, maximumItems: Int? = nil) -> [String: Any] {
        var schema: [String: Any] = [
            "type": "array",
            "items": ["type": "string"],
            "description": description
        ]
        if let maximumItems { schema["maxItems"] = maximumItems }
        return schema
    }
}
