//
//  NativeToolJSON.swift
//  AI_HLY
//
//  Native Agent Extensions - JSON helpers for Swift-only native tools.
//

import Foundation

enum NativeToolJSON {
    enum JSONError: LocalizedError {
        case invalidUTF8
        case invalidObject
        case missingRequiredString(String)

        var errorDescription: String? {
            switch self {
            case .invalidUTF8:
                return "Tool arguments are not valid UTF-8 JSON."
            case .invalidObject:
                return "Tool arguments must be a JSON object."
            case .missingRequiredString(let key):
                return "Missing required string argument: \(key)."
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
