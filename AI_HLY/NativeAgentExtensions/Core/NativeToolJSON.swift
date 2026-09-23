//
//  NativeToolJSON.swift
//  AI_HLY
//
//  Native Agent Extensions - JSON helpers for Swift-only native tools.
//

import CoreFoundation
import Foundation

enum NativeToolJSON {
    enum JSONError: LocalizedError {
        case invalidUTF8
        case invalidObject
        case missingRequiredString(String)
        case invalidType(key: String, expected: String)
        case unknownArguments([String])
        case invalidValue(key: String, description: String)

        var errorDescription: String? {
            switch self {
            case .invalidUTF8:
                return "Tool arguments are not valid UTF-8 JSON."
            case .invalidObject:
                return "Tool arguments must be a JSON object."
            case .missingRequiredString(let key):
                return "Missing required string argument: \(key)."
            case .invalidType(let key, let expected):
                return "Argument '\(key)' must be \(expected)."
            case .unknownArguments(let keys):
                return "Unknown tool argument(s): \(keys.sorted().joined(separator: ", "))."
            case .invalidValue(let key, let description):
                return "Invalid value for argument '\(key)': \(description)"
            }
        }
    }

    static func dictionary(from jsonString: String) throws -> [String: Any] {
        guard let data = jsonString.data(using: .utf8) else {
            throw JSONError.invalidUTF8
        }
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dictionary = object as? [String: Any] else {
            throw JSONError.invalidObject
        }
        return dictionary
    }

    static func validatedDictionary(
        from jsonString: String,
        allowedKeys: Set<String>
    ) throws -> [String: Any] {
        let dictionary = try dictionary(from: jsonString)
        let unknown = Set(dictionary.keys).subtracting(allowedKeys)
        guard unknown.isEmpty else { throw JSONError.unknownArguments(Array(unknown)) }
        return dictionary
    }

    static func strictRequiredString(_ dictionary: [String: Any], _ key: String) throws -> String {
        guard let raw = dictionary[key] else { throw JSONError.missingRequiredString(key) }
        guard let value = raw as? String else {
            throw JSONError.invalidType(key: key, expected: "a string")
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw JSONError.missingRequiredString(key) }
        return value
    }

    static func strictOptionalString(_ dictionary: [String: Any], _ key: String) throws -> String? {
        guard let raw = dictionary[key] else { return nil }
        guard let value = raw as? String else {
            throw JSONError.invalidType(key: key, expected: "a string")
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : value
    }

    static func strictStringArray(_ dictionary: [String: Any], _ key: String) throws -> [String] {
        guard let raw = dictionary[key] else { return [] }
        guard let values = raw as? [Any], values.allSatisfy({ $0 is String }) else {
            throw JSONError.invalidType(key: key, expected: "an array of strings")
        }
        return values.compactMap { $0 as? String }
    }

    static func strictBool(_ dictionary: [String: Any], _ key: String, default defaultValue: Bool = false) throws -> Bool {
        guard let raw = dictionary[key] else { return defaultValue }
        guard let number = raw as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else {
            throw JSONError.invalidType(key: key, expected: "a boolean")
        }
        return number.boolValue
    }

    static func strictInt(
        _ dictionary: [String: Any],
        _ key: String,
        default defaultValue: Int,
        range: ClosedRange<Int>? = nil
    ) throws -> Int {
        guard let raw = dictionary[key] else { return defaultValue }
        guard let number = raw as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            throw JSONError.invalidType(key: key, expected: "an integer")
        }
        let double = number.doubleValue
        guard double.isFinite, double.rounded() == double, let value = Int(exactly: double) else {
            throw JSONError.invalidType(key: key, expected: "an integer")
        }
        if let range, !range.contains(value) {
            throw JSONError.invalidValue(key: key, description: "expected \(range.lowerBound)...\(range.upperBound)")
        }
        return value
    }

    static func optionalString(_ dictionary: [String: Any], _ key: String) -> String? {
        if let value = dictionary[key] as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let value = dictionary[key] as? CustomStringConvertible {
            let trimmed = value.description.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    static func requiredString(_ dictionary: [String: Any], _ key: String) throws -> String {
        guard let value = optionalString(dictionary, key) else {
            throw JSONError.missingRequiredString(key)
        }
        return value
    }

    static func int(_ dictionary: [String: Any], _ key: String, default defaultValue: Int) -> Int {
        if let value = dictionary[key] as? Int { return value }
        if let value = dictionary[key] as? Double { return Int(value) }
        if let value = dictionary[key] as? String, let intValue = Int(value) { return intValue }
        return defaultValue
    }

    static func double(_ dictionary: [String: Any], _ key: String) -> Double? {
        if let value = dictionary[key] as? Double { return value }
        if let value = dictionary[key] as? Int { return Double(value) }
        if let value = dictionary[key] as? String { return Double(value) }
        return nil
    }

    static func bool(_ dictionary: [String: Any], _ key: String, default defaultValue: Bool = false) -> Bool {
        if let value = dictionary[key] as? Bool { return value }
        if let value = dictionary[key] as? String {
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: return defaultValue
            }
        }
        return defaultValue
    }

    static func jsonString(from object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]),
              let string = String(data: data, encoding: .utf8) else {
            return String(describing: object)
        }
        return string
    }
}
