// SPDX-License-Identifier: Apache-2.0
import Foundation

/// An immutable writer for strict UTF-8 JSON and exact decimal values.
///
/// Each call admits the complete value under its configured limits. Key sorting is
/// deterministic scalar order and makes no cryptographic canonicalization claim.
public struct JSONWriter: Sendable {
    /// The immutable configuration used to create each invocation.
    public let options: JSONWritingOptions
    /// Creates an immutable writer facade. Limits and indentation are checked when writing begins.
    ///
    /// - Parameters:
    ///   - options: The value configuration used by this facade or operation.
    public init(options: JSONWritingOptions = .init()) { self.options = options }
    /// Writes a complete strict UTF-8 document.
    ///
    /// - Returns: Owned encoded bytes.
    /// - Throws: Admission, output or configuration failure, or cancellation.
    ///
    /// - Parameters:
    ///   - value: The exact root to admit and write as strict UTF-8 JSON.
    public func write(_ value: JSON) throws -> Data { try writeWithReport(value).result }
    /// Writes strict JSON and charges the additional owned String result.
    ///
    /// - Returns: Complete UTF-8 JSON text.
    /// - Throws: Resource or configuration failure, or cancellation.
    ///
    /// - Parameters:
    ///   - value: The exact root to admit and write as strict UTF-8 JSON.
    public func writeString(_ value: JSON) throws -> String {
        var meter = try JSONWorkMeter(limits: options.limits, domain: .writing)
        let bytes = try write(value, meter: &meter)
        for _ in bytes { try meter.work(); try meter.retain(1) }
        return String(decoding: bytes, as: UTF8.self)
    }
    /// Writes strict JSON with successful operation accounting.
    ///
    /// - Returns: Owned bytes and counts; output bytes are charged before growth.
    /// - Throws: Resource or configuration failure, or cancellation.
    ///
    /// - Parameters:
    ///   - value: The exact root to admit and write as strict UTF-8 JSON.
    public func writeWithReport(_ value: JSON) throws -> JSONOperationReport<Data> {
        var meter = try JSONWorkMeter(limits: options.limits, domain: .writing)
        let bytes = try write(value, meter: &meter)
        for _ in bytes { try meter.work(); try meter.retain(1) }
        return .init(result: Data(bytes), statistics: meter.statistics())
    }
    package func write(_ value: JSON, meter: inout JSONWorkMeter) throws -> [UInt8] {
        if let indentation = options.indentation, !(0...8).contains(indentation) { throw JSONFailure(.configuration, code: .invalidLimits) }
        try JSONAdmission.value(value, meter: &meter)
        var cursor = JSONWritingCursor(value: value, options: options)
        var bytes: [UInt8] = []
        while let byte = try cursor.next(meter: &meter) {
            try meter.charge(.outputBytes); try meter.retain(1); bytes.append(byte)
        }
        return bytes
    }
}

/// Syntax classification attached to bytes from the single strict writer.
package enum JSONWritingTokenKind: String, Sendable {
    case key, string, number, boolean, null, punctuation, whitespace
}
package struct JSONWritingByte: Sendable {
    package let byte: UInt8
    package let kind: JSONWritingTokenKind
    package let beginsValue: Bool
}

/// Explicit traversal cursor also used by awaited streaming sinks.
package struct JSONWritingCursor {
    private enum Step {
        case value(JSON, Int), byte(UInt8, JSONWritingTokenKind = .punctuation)
        case text(String.UTF8View.Iterator, JSONWritingTokenKind), escaped(String.UTF8View.Iterator, JSONWritingTokenKind)
        case digits([UInt8], Int), indent(Int)
    }
    private var stack: [Step]
    private let options: JSONWritingOptions
    private var initialized = false
    private var beginsValue = false
    package init(value: JSON, options: JSONWritingOptions) { stack = [.value(value, 0)]; self.options = options }
    private mutating func push(_ step: Step, meter: inout JSONWorkMeter) throws {
        try meter.retain(JSONLogicalWeights.frame); stack.append(step)
    }
    private mutating func newline(_ depth: Int, meter: inout JSONWorkMeter) throws {
        if let indentation = options.indentation {
            let (units, overflow) = depth.multipliedReportingOverflow(by: indentation)
            guard !overflow else { throw JSONFailure(.configuration, code: .invalidLimits) }
            try push(.indent(units), meter: &meter); try push(.byte(10, .whitespace), meter: &meter)
        }
    }
    private mutating func quoted(_ text: String, kind: JSONWritingTokenKind = .string, meter: inout JSONWorkMeter) throws {
        try push(.byte(34, kind), meter: &meter); try push(.escaped(text.utf8.makeIterator(), kind), meter: &meter); try push(.byte(34, kind), meter: &meter)
    }
    private func scalarLess(_ a: JSONMember, _ b: JSONMember, meter: inout JSONWorkMeter) throws -> Bool {
        var l = a.key.string.utf8.makeIterator(), r = b.key.string.utf8.makeIterator()
        while true {
            try meter.work()
            let x = l.next(), y = r.next()
            if x != y { if let x, let y { return x < y }; return x == nil }
            if x == nil { return false }
        }
    }
    private func ordered(_ object: JSONObject, meter: inout JSONWorkMeter) throws -> [JSONMember] {
        if options.keyOrder == .insertion { return object.members }
        var values: [JSONMember] = [], scratch: [JSONMember] = []
        for member in object {
            try meter.work(); try meter.retain(JSONLogicalWeights.member * 2)
            values.append(member); scratch.append(member)
        }
        var width = 1
        while width < values.count {
            var start = 0
            while start < values.count {
                let middle = min(start + width, values.count), end = min(middle + width, values.count)
                var left = start, right = middle
                for target in start..<end {
                    try meter.work()
                    if try left < middle && (right == end || !scalarLess(values[right], values[left], meter: &meter)) {
                        scratch[target] = values[left]; left += 1
                    } else { scratch[target] = values[right]; right += 1 }
                }
                start = end
            }
            swap(&values, &scratch)
            if width > values.count / 2 { break }
            width *= 2
        }
        try meter.release(UInt64(values.count) * JSONLogicalWeights.member)
        return values
    }
    package mutating func next(meter: inout JSONWorkMeter) throws -> UInt8? {
        try nextToken(meter: &meter)?.byte
    }
    private mutating func token(_ byte: UInt8, _ kind: JSONWritingTokenKind) -> JSONWritingByte {
        let result = JSONWritingByte(byte: byte, kind: kind, beginsValue: beginsValue)
        beginsValue = false
        return result
    }
    package mutating func nextToken(meter: inout JSONWorkMeter) throws -> JSONWritingByte? {
        if !initialized { try meter.retain(JSONLogicalWeights.frame); initialized = true }
        while let step = stack.popLast() {
            try meter.release(JSONLogicalWeights.frame)
            try meter.work()
            switch step {
            case .byte(let byte, let kind): return token(byte, kind)
            case .indent(let count):
                if count > 0 { try push(.indent(count - 1), meter: &meter); return token(options.indentationUnit == .spaces ? 32 : 9, .whitespace) }
            case .text(var iterator, let kind):
                if let byte = iterator.next() { try push(.text(iterator, kind), meter: &meter); return token(byte, kind) }
            case .digits(let digits, let index):
                if index < digits.count { try push(.digits(digits, index + 1), meter: &meter); return token(digits[index] + 48, .number) }
            case .escaped(var iterator, let kind):
                if let byte = iterator.next() {
                    try push(.escaped(iterator, kind), meter: &meter)
                    switch byte {
                    case 34, 92: try push(.byte(byte, kind), meter: &meter); return token(92, kind)
                    case 0...31:
                        let hex: [UInt8] = Array("0123456789abcdef".utf8)
                        try push(.byte(hex[Int(byte & 15)], kind), meter: &meter); try push(.byte(hex[Int(byte >> 4)], kind), meter: &meter)
                        try push(.byte(48, kind), meter: &meter); try push(.byte(48, kind), meter: &meter); try push(.byte(117, kind), meter: &meter); return token(92, kind)
                    default: return token(byte, kind)
                    }
                }
            case .value(let value, let depth):
                beginsValue = true
                switch value {
                case .null: try push(.text("null".utf8.makeIterator(), .null), meter: &meter)
                case .boolean(let boolean): try push(.text((boolean ? "true" : "false").utf8.makeIterator(), .boolean), meter: &meter)
                case .string(let text): try quoted(text, meter: &meter)
                case .number(let number):
                    if options.numberStyle == .preserved, let lexeme = number.originalLexeme { try push(.text(lexeme.utf8.makeIterator(), .number), meter: &meter) }
                    else {
                        let c = number.components
                        if c.exponent != 0 { try push(.text(String(c.exponent).utf8.makeIterator(), .number), meter: &meter); try push(.byte(101, .number), meter: &meter) }
                        try push(.digits(c.digits, 0), meter: &meter)
                        if c.negative { try push(.byte(45, .number), meter: &meter) }
                    }
                case .array(let values):
                    try push(.byte(93), meter: &meter)
                    if !values.isEmpty { try newline(depth, meter: &meter) }
                    for index in values.indices.reversed() {
                        try meter.work(); try push(.value(values[index], depth + 1), meter: &meter)
                        try newline(depth + 1, meter: &meter)
                        if index > 0 { try push(.byte(44), meter: &meter) }
                    }
                    try push(.byte(91), meter: &meter)
                case .object(let object):
                    let members = try ordered(object, meter: &meter)
                    try push(.byte(125), meter: &meter)
                    if !members.isEmpty { try newline(depth, meter: &meter) }
                    for index in members.indices.reversed() {
                        try meter.work(); try push(.value(members[index].value, depth + 1), meter: &meter)
                        if options.indentation != nil { try push(.byte(32, .whitespace), meter: &meter) }
                        try push(.byte(58), meter: &meter); try quoted(members[index].key.string, kind: .key, meter: &meter)
                        try newline(depth + 1, meter: &meter)
                        if index > 0 { try push(.byte(44), meter: &meter) }
                    }
                    try push(.byte(123), meter: &meter)
                    if options.keyOrder == .scalar { try meter.release(UInt64(members.count) * JSONLogicalWeights.member) }
                }
            }
        }
        return nil
    }
}
