// SPDX-License-Identifier: Apache-2.0
import Foundation

/// The required numeric fidelity when projecting an exact decimal.
public enum JSONNumberConversionPolicy: Sendable {
    /// Require mathematical equality with the finite target representation.
    case exact
    /// Allow finite rounding within the target representation; overflow still fails.
    case rounded
}
/// The decimal spelling used when writing an exact number.
public enum JSONNumberTextStyle: Sendable {
    /// Render normalized coefficient and exponent, with one zero identity.
    case normalized
    /// Use the original admitted lexeme when available, otherwise normalized text.
    case preserved
}

extension JSONNumber {
    /// Renders the exact number without exponent-sized zero expansion.
    ///
    /// Preserved style falls back to normalized spelling when there is no original lexeme.
    /// - Returns: Admitted numeric text.
    /// - Throws: Resource or configuration failure, or cancellation.
    ///
    /// - Parameters:
    ///   - style: The requested rendering or output format.
    ///   - limits: Finite inclusive capacities and work quotas for this call.
    public func numericText(style: JSONNumberTextStyle = .normalized, limits: JSONLimits = .balanced) throws -> String {
        var meter = try JSONWorkMeter(limits: limits, domain: .core)
        return try numericText(style: style, meter: &meter)
    }
    package func numericText(style: JSONNumberTextStyle = .normalized, meter: inout JSONWorkMeter) throws -> String {
        let c = components
        var output: [UInt8] = []
        func append(_ byte: UInt8, meter: inout JSONWorkMeter) throws {
            try meter.work(subsystem: .numericWorkUnits)
            try meter.charge(.outputBytes); try meter.retain(1); output.append(byte)
        }
        if style == .preserved, let lexeme = originalLexeme {
            for byte in lexeme.utf8 { try append(byte, meter: &meter) }
        } else {
            if c.negative { try append(45, meter: &meter) }
            for digit in c.digits { try append(digit + 48, meter: &meter) }
            if c.exponent != 0 {
                try append(101, meter: &meter)
                for byte in String(c.exponent).utf8 { try append(byte, meter: &meter) }
            }
        }
        // The result String and its construction buffer overlap until this call returns.
        for _ in output { try meter.work(subsystem: .numericWorkUnits) }
        try meter.retain(UInt64(output.count)); try meter.checkpoint()
        let result = String(decoding: output, as: UTF8.self)
        try meter.checkpoint(); try meter.release(UInt64(output.count))
        return result
    }
    /// Converts the mathematical value exactly to a fixed-width integer.
    ///
    /// - Returns: An integral, in-range result.
    /// - Throws: Inexact conversion for fractions, sign mismatch or overflow; resource failure or cancellation.
    ///
    /// - Parameters:
    ///   - type: The target Swift type.
    ///   - limits: Finite inclusive capacities and work quotas for this call.
    public func integer<T: FixedWidthInteger>(as type: T.Type, limits: JSONLimits = .balanced) throws -> T {
        var meter = try JSONWorkMeter(limits: limits, domain: .core)
        return try integer(as: type, meter: &meter)
    }
    package func integer<T: FixedWidthInteger>(as type: T.Type, meter: inout JSONWorkMeter) throws -> T {
        let c = components
        guard c.exponent >= 0, !c.negative || T.isSigned else { throw JSONFailure(.conversion, code: .inexactConversion) }
        var magnitude: T.Magnitude = 0
        func append(_ digit: UInt8, meter: inout JSONWorkMeter) throws {
            try meter.work(subsystem: .numericWorkUnits)
            let (scaled, overflow1) = magnitude.multipliedReportingOverflow(by: 10)
            let (sum, overflow2) = scaled.addingReportingOverflow(T.Magnitude(digit))
            guard !overflow1 && !overflow2 else { throw JSONFailure(.conversion, code: .inexactConversion) }
            magnitude = sum
        }
        for digit in c.digits { try append(digit, meter: &meter) }
        // A nonzero magnitude fails at the machine integer boundary, without dense expansion.
        if magnitude != 0 { for _ in 0..<c.exponent { try append(0, meter: &meter) } }
        if c.negative {
            guard magnitude <= T.min.magnitude else { throw JSONFailure(.conversion, code: .inexactConversion) }
            return 0 &- T(truncatingIfNeeded: magnitude)
        }
        guard let value = T(exactly: magnitude) else { throw JSONFailure(.conversion, code: .inexactConversion) }
        return value
    }
    /// A binary64 rounding midpoint has a finite decimal coefficient of at most
    /// 769 digits: a <=54-bit integer times 5^1075. Keeping 800 significant
    /// digits and a nonzero sticky digit preserves which side of every midpoint
    /// the original exact decimal occupies. Binary32's midpoint bound is smaller.
    /// The system converter therefore sees <=822 bytes, independent of input size.
    package func binaryConversionText(meter: inout JSONWorkMeter) throws -> String {
        let c = components
        let kept = min(800,c.digits.count), shortened = c.digits.count > kept
        let coefficientCount = kept + (shortened ? 1 : 0)
        let adjustment = Int64(c.digits.count - coefficientCount)
        let (exponent,overflow) = c.exponent.addingReportingOverflow(adjustment)
        guard !overflow else { throw JSONFailure(.resource,code: .counterOverflow) }
        var output: [UInt8] = []
        func append(_ byte: UInt8,meter: inout JSONWorkMeter) throws {
            try meter.work(subsystem: .numericWorkUnits); try meter.charge(.outputBytes)
            try meter.retain(1); output.append(byte)
        }
        if c.negative { try append(45,meter: &meter) }
        for (i,digit) in c.digits.enumerated() {
            try meter.work(subsystem: .numericWorkUnits)
            if i < kept { try append(digit+48,meter: &meter) }
        }
        // Normalized coefficients end in a nonzero digit, so a discarded tail
        // is strictly positive. A sticky 1 preserves that fact without rounding.
        if shortened { try append(49,meter: &meter) }
        if exponent != 0 {
            try append(101,meter: &meter)
            for byte in String(exponent).utf8 { try append(byte,meter: &meter) }
        }
        for _ in output { try meter.work(subsystem: .numericWorkUnits) }
        try meter.retain(UInt64(output.count)); try meter.checkpoint()
        let text = String(decoding: output,as: UTF8.self)
        try meter.checkpoint(); try meter.release(UInt64(output.count))
        return text
    }
    /// Constructs the exact decimal meaning of Swift's round-trip rendering of a finite Double.
    ///
    /// This does not recover an earlier JSON token or the exact mathematical value of
    /// the binary floating-point representation; it adopts Swift's round-trip text.
    /// - Returns: An admitted exact decimal.
    /// - Throws: Inexact conversion for NaN/infinity, resource failure or cancellation.
    ///
    /// - Parameters:
    ///   - value: The finite binary64 value whose Swift round-trip text to parse.
    ///   - limits: Finite inclusive capacities and work quotas for this call.
    public static func fromFiniteDouble(_ value: Double, limits: JSONLimits = .balanced) throws -> Self {
        guard value.isFinite else { throw JSONFailure(.conversion, code: .inexactConversion) }
        return try Self(parsing: String(value), limits: limits)
    }
    /// Projects the decimal to a finite Double under the selected fidelity policy.
    ///
    /// Exact mode proves mathematical equality; decimal 0.1 therefore fails in exact mode.
    /// - Returns: A finite binary64 value.
    /// - Throws: Inexact or overflowing conversion, resource failure or cancellation.
    ///
    /// - Parameters:
    ///   - policy: The required exact or finite-rounded conversion fidelity.
    ///   - limits: Finite inclusive capacities and work quotas for this call.
    public func doubleValue(policy: JSONNumberConversionPolicy = .exact, limits: JSONLimits = .balanced) throws -> Double {
        var meter = try JSONWorkMeter(limits: limits, domain: .core)
        return try doubleValue(policy: policy, meter: &meter)
    }
    package func doubleValue(policy: JSONNumberConversionPolicy, meter: inout JSONWorkMeter) throws -> Double {
        let text = try binaryConversionText(meter: &meter)
        try meter.checkpoint()
        guard let value = Double(text), value.isFinite else { throw JSONFailure(.conversion, code: .inexactConversion) }
        try meter.checkpoint()
        if policy == .exact {
            let binary = try Self.exactBinary(value, meter: &meter)
            guard try compare(to: binary, meter: &meter) == .orderedSame else {
                throw JSONFailure(.conversion, code: .inexactConversion)
            }
        }
        return value
    }
    /// Projects the decimal to Foundation Decimal under the selected fidelity policy.
    ///
    /// The fixed precision and exponent range remain bounded in either policy.
    /// - Returns: A finite Decimal; exact mode verifies equality by native decimal comparison.
    /// - Throws: Range/precision failure, resource failure or cancellation.
    ///
    /// - Parameters:
    ///   - policy: The required exact or finite-rounded conversion fidelity.
    ///   - limits: Finite inclusive capacities and work quotas for this call.
    public func decimalValue(policy: JSONNumberConversionPolicy = .exact, limits: JSONLimits = .balanced) throws -> Decimal {
        var meter = try JSONWorkMeter(limits: limits, domain: .core)
        return try decimalValue(policy: policy, meter: &meter)
    }
    package func decimalValue(policy: JSONNumberConversionPolicy, meter: inout JSONWorkMeter) throws -> Decimal {
        let c = components
        guard c.digits.count <= 39, c.exponent >= -128, c.exponent <= 165 else {
            throw JSONFailure(.conversion, code: .inexactConversion)
        }
        let text = try numericText(meter: &meter)
        guard var decimal = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), !decimal.isNaN else {
            throw JSONFailure(.conversion, code: .inexactConversion)
        }
        if policy == .exact {
            // Decimal is fixed precision/exponent. Reserve a conservative 256-byte foreign
            // formatting result before the synchronous bridge; native parsing is still exact.
            try meter.retain(256); try meter.checkpoint()
            let description = JSONDecimalBridge.text(&decimal)
            try meter.checkpoint()
            let admitted = try Self.parse(description.utf8,meter: &meter)
            try meter.release(256)
            guard try compare(to: admitted, meter: &meter) == .orderedSame else {
                throw JSONFailure(.conversion, code: .inexactConversion)
            }
        }
        return decimal
    }
    package static func exactBinary(_ value: Double, meter: inout JSONWorkMeter) throws -> Self {
        if value == 0 { return Self(integer: 0) }
        let bits = value.bitPattern
        let exponentBits = Int((bits >> 52) & 0x7ff)
        let fraction = bits & ((UInt64(1) << 52) - 1)
        let significand = exponentBits == 0 ? fraction : fraction | (UInt64(1) << 52)
        let binaryExponent = exponentBits == 0 ? -1074 : exponentBits - 1023 - 52
        var digits = Array(String(significand).utf8.reversed().map { $0 - 48 })
        try meter.retain(UInt64(digits.count))
        let multiplier: UInt8 = binaryExponent < 0 ? 5 : 2
        for _ in 0..<abs(binaryExponent) {
            var carry: UInt8 = 0
            for index in digits.indices {
                try meter.work(subsystem: .numericWorkUnits)
                let product = digits[index] * multiplier + carry
                digits[index] = product % 10; carry = product / 10
            }
            if carry != 0 { try meter.retain(1); digits.append(carry) }
        }
        var exponent = Int64(min(binaryExponent, 0))
        var first = 0
        while first < digits.count - 1 && digits[first] == 0 {
            try meter.work(subsystem: .numericWorkUnits); first += 1; exponent += 1
        }
        var coefficient: [UInt8] = []
        for digit in digits[first...].reversed() {
            try meter.work(subsystem: .numericWorkUnits); try meter.retain(1); coefficient.append(digit)
        }
        return Self(components: .init(negative: bits >> 63 != 0, digits: coefficient, exponent: exponent))
    }
    package func compare(to other: Self, meter: inout JSONWorkMeter) throws -> ComparisonResult {
        let a = components, b = other.components
        try meter.work(subsystem: .numericWorkUnits)
        if a.isZero && b.isZero { return .orderedSame }
        if a.negative != b.negative { return a.negative ? .orderedAscending : .orderedDescending }
        var result: ComparisonResult = .orderedSame
        if a.isZero { result = .orderedAscending }
        else if b.isZero { result = .orderedDescending }
        else {
            let (aOrder, ao) = a.exponent.addingReportingOverflow(Int64(a.digits.count))
            let (bOrder, bo) = b.exponent.addingReportingOverflow(Int64(b.digits.count))
            guard !ao && !bo else { throw JSONFailure(.resource, code: .counterOverflow) }
            if aOrder != bOrder { result = aOrder < bOrder ? .orderedAscending : .orderedDescending }
            else {
                for index in 0..<max(a.digits.count, b.digits.count) {
                    try meter.work(subsystem: .numericWorkUnits)
                    let l = index < a.digits.count ? a.digits[index] : 0
                    let r = index < b.digits.count ? b.digits[index] : 0
                    if l != r { result = l < r ? .orderedAscending : .orderedDescending; break }
                }
            }
        }
        if a.negative {
            if result == .orderedAscending { return .orderedDescending }
            if result == .orderedDescending { return .orderedAscending }
        }
        return result
    }
}

/// Narrow Foundation Decimal interoperability, outside the exact arithmetic authority.
/// The pointer addresses one live stack value for the duration of a synchronous read-only
/// NSDecimalString call; it is neither stored nor returned and never crosses await.
package enum JSONDecimalBridge {
    package static func text(_ value: inout Decimal) -> String {
        unsafe NSDecimalString(&value,Locale(identifier: "en_US_POSIX"))
    }
}
