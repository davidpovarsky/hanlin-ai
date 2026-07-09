//
//  NativeTool.swift
//  AI_HLY
//
//  Swift-only native tool protocol. No JS/TS runtime is used.
//

import Foundation
import SwiftData

@MainActor
protocol NativeTool {
    var name: String { get }
    var catalogEntry: NativeToolCatalogEntry { get }

    /// OpenAI-compatible schema object:
    /// ["type": "function", "function": ["name": ..., "description": ..., "parameters": ...]]
    func openAIToolSchema() -> [String: Any]

    func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult
}

struct NativeToolExecutionContext {
    var localeIdentifier: String
    var modelContext: ModelContext?

    init(localeIdentifier: String, modelContext: ModelContext? = nil) {
        self.localeIdentifier = localeIdentifier
        self.modelContext = modelContext
    }

    var isHebrew: Bool { localeIdentifier.hasPrefix("he") }
    var isChinese: Bool { localeIdentifier.hasPrefix("zh") }
}

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

    static func number(description: String, minimum: Int? = nil, maximum: Int? = nil) -> [String: Any] {
        var schema: [String: Any] = ["type": "number", "description": description]
        if let minimum { schema["minimum"] = minimum }
        if let maximum { schema["maximum"] = maximum }
        return schema
    }
}
