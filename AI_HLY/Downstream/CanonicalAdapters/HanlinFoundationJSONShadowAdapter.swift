import Foundation
import CoreFoundation
import HanlinPlatformContracts

/// Read-only conversion used by shadow catalog adapters.
///
/// Legacy sources: Foundation JSON-compatible values and native tool schema
/// dictionaries. Canonical target: `HanlinJSONValue`. Binary/Foundation objects,
/// non-finite values, non-string dictionary keys, and integers outside Int64 are
/// rejected. This adapter can be deleted when producers emit canonical values.
enum HanlinFoundationJSONShadowAdapter {
    static func project(_ source: Any, path: String = "") throws -> HanlinJSONValue {
        switch source {
        case is NSNull:
            return .null
        case let number as NSNumber:
            return try project(number: number, path: path)
        case let value as Bool:
            return .bool(value)
        case let value as Int:
            return .integer(Int64(value))
        case let value as Int8:
            return .integer(Int64(value))
        case let value as Int16:
            return .integer(Int64(value))
        case let value as Int32:
            return .integer(Int64(value))
        case let value as Int64:
            return .integer(value)
        case let value as UInt:
            guard let exact = Int64(exactly: value) else {
                throw HanlinContractError.integerOutOfRange(
                    value: String(value), destination: "Int64", path: path
                )
            }
            return .integer(exact)
        case let value as UInt8:
            return .integer(Int64(value))
        case let value as UInt16:
            return .integer(Int64(value))
        case let value as UInt32:
            return .integer(Int64(value))
        case let value as UInt64:
            guard let exact = Int64(exactly: value) else {
                throw HanlinContractError.integerOutOfRange(
                    value: String(value), destination: "Int64", path: path
                )
            }
            return .integer(exact)
        case let value as Float:
            return try .finiteNumber(Double(value))
        case let value as Double:
            return try .finiteNumber(value)
        case let value as String:
            return .string(value)
        case let values as [Any]:
            return try .array(values.enumerated().map { index, value in
                try project(value, path: append(String(index), to: path))
            })
        case let values as [String: Any]:
            return try .object(HanlinObject(uniqueMembers: values.map { key, value in
                (
                    key: key,
                    value: try project(value, path: append(key, to: path))
                )
            }))
        default:
            throw HanlinContractError.invalidJSON(
                reason: "Foundation value of type \(String(reflecting: type(of: source))) is not JSON",
                byteOffset: 0
            )
        }
    }

    private static func project(number: NSNumber, path: String) throws -> HanlinJSONValue {
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            return .bool(number.boolValue)
        }
        let encoding = String(cString: number.objCType)
        if ["c", "s", "i", "l", "q", "C", "S", "I", "L", "Q"].contains(encoding) {
            let text = number.stringValue
            guard let integer = Int64(text), String(integer) == text else {
                throw HanlinContractError.integerOutOfRange(
                    value: text,
                    destination: "Int64",
                    path: path
                )
            }
            return .integer(integer)
        }
        let value = number.doubleValue
        return try .finiteNumber(value)
    }

    private static func append(_ component: String, to path: String) -> String {
        let escaped = component
            .replacingOccurrences(of: "~", with: "~0")
            .replacingOccurrences(of: "/", with: "~1")
        return path + "/" + escaped
    }
}
