import Foundation
import HanlinPlatformContracts

public enum HanlinModelToolInputError: String, Error, LocalizedError, Sendable {
    case numericArgumentsUnsupported
    public var errorDescription: String? {
        "The model-tool numeric input cannot be represented safely. No host operation was dispatched."
    }
}

/// Model-tool path ONLY. Missing/unverified original input rejects even small numeric
/// leaves. Verified original input still passes the canonical Int64/finite Double
/// parser and host schema/authority checks. This is not arbitrary-precision JSON.
public enum HanlinModelToolInputGuard {
    public static func validate(_ argumentsJSON: String, originalInputVerified: Bool = false) throws -> HanlinJSONValue {
        let value = try HanlinJSONValue.decodeCanonicalJSON(Data(argumentsJSON.utf8))
        guard originalInputVerified || !containsNumber(value) else { throw HanlinModelToolInputError.numericArgumentsUnsupported }
        if originalInputVerified { try validateDecimalRoundTrips(argumentsJSON) }
        return value
    }

    /// The session places ALL pending persistence and dispatch in this body. Keeping the
    /// validation boundary here makes zero-body-entry on rejection directly testable.
    public static func withValidatedArguments<Output: Sendable>(
        _ argumentsJSON: String,
        originalInputVerified: Bool = false,
        isolation: isolated (any Actor)? = #isolation,
        operation: (HanlinJSONValue) async throws -> Output
    ) async throws -> Output {
        let value = try validate(argumentsJSON, originalInputVerified: originalInputVerified)
        return try await operation(value)
    }

    private static func containsNumber(_ value: HanlinJSONValue) -> Bool {
        switch value {
        case .integer, .number: true
        case .array(let values): values.contains(where: containsNumber)
        case .object(let members): members.contains { containsNumber($0.value) }
        case .null, .bool, .string: false
        }
    }

    /// Canonical JSON supports Int64 and finite Double, not arbitrary decimals.
    /// Reject decimal/exponent tokens that change decimal value when represented
    /// by Double's shortest round-trip text. Integer tokens are checked by the
    /// canonical parser. Strings (including digit strings) are never interpreted.
    private static func validateDecimalRoundTrips(_ json: String) throws {
        let bytes = Array(json.utf8)
        var index = 0
        var inString = false
        while index < bytes.count {
            let byte = bytes[index]
            if inString {
                if byte == 92 { index += 2; continue }
                if byte == 34 { inString = false }
                index += 1; continue
            }
            if byte == 34 { inString = true; index += 1; continue }
            if byte == 45 || (48...57).contains(byte) {
                let start = index
                while index < bytes.count, ![9, 10, 13, 32, 44, 93, 125].contains(bytes[index]) { index += 1 }
                let token = String(decoding: bytes[start..<index], as: UTF8.self)
                if token.contains(".") || token.contains("e") || token.contains("E") {
                    guard let number = Double(token), number.isFinite,
                          let original = normalizedDecimal(token),
                          let represented = normalizedDecimal(String(number)), original == represented else {
                        throw HanlinModelToolInputError.numericArgumentsUnsupported
                    }
                }
                continue
            }
            index += 1
        }
    }

    private static func normalizedDecimal(_ token: String) -> String? {
        var text = token.lowercased()
        let negative = text.hasPrefix("-")
        if negative { text.removeFirst() }
        let parts = text.split(separator: "e", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return nil }
        let exponent: Int
        if parts.count == 2 {
            guard let value = Int(parts[1]), (-1_000_000...1_000_000).contains(value) else { return nil }
            exponent = value
        } else { exponent = 0 }
        let mantissa = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        let digits = Array(mantissa.joined().utf8)
        var scale = exponent - (mantissa.count == 2 ? mantissa[1].count : 0)
        var first = 0
        var last = digits.count
        while first < last, digits[first] == 48 { first += 1 }
        if first == last { return "0" }
        while last > first, digits[last - 1] == 48 { last -= 1; scale += 1 }
        return (negative ? "-" : "") + String(decoding: digits[first..<last], as: UTF8.self) + "e" + String(scale)
    }
}
