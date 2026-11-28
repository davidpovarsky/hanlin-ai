// SPDX-License-Identifier: Apache-2.0
// Numeric storage is new code; reference JSONNumber.swift was reviewed, not copied.
/// An exact bounded decimal value with optional original JSON spelling.
///
/// Equality and hashing use the mathematical value. Zero has one identity, including
/// negative zero. Large exponents do not require exponent-sized zero storage.
public struct JSONNumber: Sendable, Hashable {
    private enum Storage: Sendable { case integer(Int64), decimal(DecimalComponents) }
    private let storage: Storage
    /// The original admitted JSON token spelling, or nil for constructed numbers.
    public let originalLexeme: String?
    package var components: DecimalComponents {
        switch storage {
        case .integer(let value): return .integer(value)
        case .decimal(let value): return value
        }
    }
    /// Constructs an exact decimal from a trusted Swift integer without a resource budget.
    ///
    /// - Parameters:
    ///   - integer: The exact integer value to represent.
    public init<T: BinaryInteger>(integer: T) {
        if let small = Int64(exactly: integer) { storage = .integer(small) }
        else { storage = .decimal(.integer(integer)) }
        originalLexeme = nil
    }
    package init(components: DecimalComponents, lexeme: String? = nil) {
        storage = .decimal(components); originalLexeme = lexeme
    }
    /// Parses one exact JSON decimal token under finite digit, exponent and work limits.
    /// Equivalent spellings normalize to mathematical identity while retaining the lexeme.
    ///
    /// - Throws: Invalid-number, resource/configuration errors or cancellation.
    ///
    /// - Parameters:
    ///   - text: Encoded input text admitted without repair.
    ///   - limits: Finite inclusive capacities and work quotas for this call.
    public init(parsing text: String, limits: JSONLimits = .balanced) throws {
        var meter = try JSONWorkMeter(limits: limits, domain: .core)
        self = try Self.parse(text.utf8, meter: &meter)
    }
    package static func parse<C: Collection>(_ bytes: C, meter: inout JSONWorkMeter) throws -> Self where C.Element == UInt8 {
        var input: [UInt8] = []
        for byte in bytes {
            try meter.work(subsystem: .numericWorkUnits)
            try meter.require(.numberTokenBytes, UInt64(input.count) + 1)
            try meter.retain(1); input.append(byte)
        }
        var index = 0
        func invalid() -> JSONFailure { .init(.syntax, code: .invalidNumber) }
        guard !input.isEmpty else { throw invalid() }
        let negative = input[0] == 45
        if negative { index += 1 }
        guard index < input.count else { throw invalid() }
        var digits: [UInt8] = []
        func appendDigit(_ byte: UInt8, meter: inout JSONWorkMeter) throws {
            try meter.work(subsystem: .numericWorkUnits)
            try meter.require(.numberDigits, UInt64(digits.count) + 1)
            try meter.retain(1); digits.append(byte - 48)
        }
        if input[index] == 48 {
            try appendDigit(48, meter: &meter); index += 1
        } else {
            guard (49...57).contains(input[index]) else { throw invalid() }
            while index < input.count && (48...57).contains(input[index]) {
                try appendDigit(input[index], meter: &meter); index += 1
            }
        }
        var fractional: Int64 = 0
        if index < input.count && input[index] == 46 {
            index += 1
            let start = index
            while index < input.count && (48...57).contains(input[index]) {
                try appendDigit(input[index], meter: &meter); fractional += 1; index += 1
            }
            guard index > start else { throw invalid() }
        }
        var exponent: Int64 = 0
        if index < input.count && (input[index] == 101 || input[index] == 69) {
            index += 1
            var minus = false
            if index < input.count && (input[index] == 43 || input[index] == 45) {
                minus = input[index] == 45; index += 1
            }
            let start = index
            var magnitude: UInt64 = 0
            while index < input.count && (48...57).contains(input[index]) {
                try meter.work(subsystem: .numericWorkUnits)
                let (scaled, overflow) = magnitude.multipliedReportingOverflow(by: 10)
                guard !overflow else { throw JSONFailure(.resource, code: .counterOverflow,
                    resource: .init(domain: meter.domain, metric: .absoluteExponent,
                        limit: meter.limits[.absoluteExponent], attemptedUsage: nil, overflow: true)) }
                magnitude = try meter.adding(.absoluteExponent, scaled, UInt64(input[index] - 48))
                index += 1
            }
            guard index > start else { throw invalid() }
            exponent = minus ? -Int64(magnitude) : Int64(magnitude)
        }
        guard index == input.count else { throw invalid() }
        let (adjusted, exponentOverflow) = exponent.subtractingReportingOverflow(fractional)
        guard !exponentOverflow else { throw JSONFailure(.resource, code: .counterOverflow,
            resource: .init(domain: meter.domain, metric: .absoluteExponent, limit: meter.limits[.absoluteExponent], attemptedUsage: nil, overflow: true)) }
        exponent = adjusted
        try meter.require(.absoluteExponent, exponent.magnitude)
        var first = 0
        while first < digits.count && digits[first] == 0 { try meter.work(subsystem: .numericWorkUnits); first += 1 }
        let components: DecimalComponents
        if first == digits.count { try meter.retain(1); components = .init(negative: false, digits: [0], exponent: 0) }
        else {
            var end = digits.count
            while end > first + 1 && digits[end - 1] == 0 {
                try meter.work(subsystem: .numericWorkUnits); end -= 1
                let (next, overflow) = exponent.addingReportingOverflow(1)
                guard !overflow else { throw invalid() }; exponent = next
            }
            try meter.require(.absoluteExponent, exponent.magnitude)
            var normalized: [UInt8] = []
            for digit in digits[first..<end] { try meter.work(subsystem: .numericWorkUnits); try meter.retain(1); normalized.append(digit) }
            components = .init(negative: negative, digits: normalized, exponent: exponent)
        }
        for _ in input { try meter.work(subsystem: .numericWorkUnits); try meter.retain(1) }
        let lexeme = String(decoding: input, as: UTF8.self)
        try meter.release(UInt64(input.count) + UInt64(digits.count))
        return Self(components: components, lexeme: lexeme)
    }
    /// Whether the mathematical value is zero, regardless of its original sign or spelling.
    public var isZero: Bool { components.isZero }
    /// Whether the normalized mathematical value is strictly negative.
    public var isNegative: Bool { components.negative }
    /// Whether the exact decimal has no fractional mathematical part.
    public var isInteger: Bool { isZero || components.exponent >= 0 }
    /// Compares semantic identity without a throwing work budget.
    ///
    /// - Parameters:
    ///   - lhs: The left value.
    ///   - rhs: The right value.
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.components == rhs.components }
    /// Hashes semantic identity; the randomized result is not a persistent digest.
    ///
    /// This protocol operation has no throwing work budget.
    ///
    /// - Parameters:
    ///   - hasher: The caller's randomized Swift hasher.
    public func hash(into hasher: inout Hasher) { hasher.combine(components) }
}

extension JSONNumber: ExpressibleByIntegerLiteral {
    /// Constructs a trusted literal value without a resource budget; bounded operations admit it later.
    ///
    /// - Parameters:
    ///   - value: The value supplied by the caller.
    public init(integerLiteral value: Int64) { self.init(integer: value) }
}
