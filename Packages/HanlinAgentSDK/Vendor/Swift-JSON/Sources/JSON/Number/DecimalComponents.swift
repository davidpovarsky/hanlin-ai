// SPDX-License-Identifier: Apache-2.0
/// Canonical coefficient digits, with no exponent-sized allocation.
package struct DecimalComponents: Sendable, Hashable {
    package let negative: Bool
    package let digits: [UInt8]
    package let exponent: Int64

    package init(negative: Bool, digits: [UInt8], exponent: Int64) {
        self.negative = negative; self.digits = digits; self.exponent = exponent
    }
    package static func integer<T: BinaryInteger>(_ value: T) -> Self {
        let text = String(value)
        var digits = text.utf8.filter { $0 != 45 }.map { $0 - 48 }
        var exponent: Int64 = 0
        while digits.count > 1 && digits.last == 0 { digits.removeLast(); exponent += 1 }
        return Self(negative: value < 0, digits: digits, exponent: exponent)
    }
    package var isZero: Bool { digits == [0] }
}

extension JSONNumber {
    /// Exact divisibility with sparse exponent iteration and bounded long division.
    package func isMultiple(of divisor: JSONNumber, meter: inout JSONWorkMeter) throws -> Bool {
        let a = components, b = divisor.components
        guard !b.isZero && !b.negative else { throw JSONFailure(.configuration, code: .invalidNumber) }
        if a.isZero { return true }
        let (shift, overflow) = a.exponent.subtractingReportingOverflow(b.exponent)
        guard !overflow else { throw JSONFailure(.resource, code: .counterOverflow) }
        if shift < 0 { return false }
        var remainder: [UInt8] = [0]
        try meter.retain(UInt64(b.digits.count) + 1)
        func consume(_ digit: UInt8, meter: inout JSONWorkMeter) throws {
            try meter.work(subsystem: .numericWorkUnits)
            if remainder == [0] { remainder[0] = digit } else { remainder.append(digit) }
            func atLeastDivisor(meter: inout JSONWorkMeter) throws -> Bool {
                if remainder.count != b.digits.count { return remainder.count > b.digits.count }
                for index in remainder.indices {
                    try meter.work(subsystem: .numericWorkUnits)
                    if remainder[index] != b.digits[index] { return remainder[index] > b.digits[index] }
                }
                return true
            }
            while try atLeastDivisor(meter: &meter) {
                var borrow: Int = 0
                for offset in 0..<remainder.count {
                    try meter.work(subsystem: .numericWorkUnits)
                    let index = remainder.count - 1 - offset
                    let subtrahend = offset < b.digits.count ? Int(b.digits[b.digits.count - 1 - offset]) : 0
                    var result = Int(remainder[index]) - subtrahend - borrow
                    borrow = result < 0 ? 1 : 0
                    if result < 0 { result += 10 }
                    remainder[index] = UInt8(result)
                }
                while remainder.count > 1 && remainder[0] == 0 {
                    for _ in remainder { try meter.work(subsystem: .numericWorkUnits) }
                    remainder.removeFirst()
                }
            }
        }
        for digit in a.digits { try consume(digit, meter: &meter) }
        for _ in 0..<shift {
            if remainder == [0] { break }
            try consume(0, meter: &meter)
        }
        try meter.release(UInt64(b.digits.count) + 1)
        return remainder == [0]
    }
}
