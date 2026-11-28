// SPDX-License-Identifier: Apache-2.0
import Foundation
/// Finite traversal, output and exact-key redaction limits for diagnostic previews.
public struct JSONPreviewOptions: Sendable {
    /// Finite capacities and work quotas applied to library-owned operations.
    public var limits: JSONLimits
    /// The maximum preview container depth before omission.
    public var maxDepth: Int
    /// The maximum preview values visited before omission.
    public var maxNodes: UInt64
    /// The maximum UTF-8 bytes emitted by the preview.
    public var maxBytes: UInt64
    /// Exact keys whose payloads are replaced before traversal.
    public var redaction: JSONRedaction
    /// Creates the value configuration; finite limits are checked at operation entry.
    ///
    /// - Parameters:
    ///   - limits: Finite inclusive capacities and work quotas for this call.
    ///   - maxDepth: Maximum preview container depth.
    ///   - maxNodes: Maximum preview values visited.
    ///   - maxBytes: Maximum preview output UTF-8 bytes.
    ///   - redaction: Exact-key redaction policy.
    public init(limits: JSONLimits = .conservative, maxDepth: Int = 4, maxNodes: UInt64 = 32, maxBytes: UInt64 = 4096, redaction: JSONRedaction = .init()) {
        self.limits = limits; self.maxDepth = maxDepth; self.maxNodes = maxNodes; self.maxBytes = maxBytes; self.redaction = redaction
    }
}
/// A bounded redacted diagnostic snippet that may be incomplete JSON.
///
/// Use a writer for serialization. Redaction checks a member key before visiting its payload.
public struct JSONPreview: Sendable, Equatable {
    /// The bounded diagnostic snippet, possibly containing omission markers.
    public let text: String
    /// Whether rendering omitted no content; a false value does not represent serialized JSON.
    public let complete: Bool
    /// Renders a bounded diagnostic preview with redaction before payload access.
    ///
    /// - Returns: A snippet with explicit completeness; it may not be valid JSON.
    /// - Throws: Resource or configuration failure, or cancellation.
    ///
    /// - Parameters:
    ///   - value: The value to preview with redaction before visiting selected payloads.
    ///   - options: The value configuration used by this facade or operation.
    public static func render(_ value: JSON, options: JSONPreviewOptions = .init()) throws -> Self {
        try renderWithReport(value, options: options).result
    }
    /// Renders a redacted preview and reports successful traversal and retention.
    ///
    /// - Returns: The snippet, completeness and accounting.
    /// - Throws: Resource or configuration failure, or cancellation.
    ///
    /// - Parameters:
    ///   - value: The value to preview with redaction before visiting selected payloads.
    ///   - options: The value configuration used by this facade or operation.
    public static func renderWithReport(_ value: JSON, options: JSONPreviewOptions = .init()) throws -> JSONOperationReport<Self> {
        var meter = try JSONWorkMeter(limits: options.limits, domain: .core)
        guard options.maxDepth >= 0, options.maxBytes >= 7 else { throw JSONFailure(.configuration, code: .invalidLimits) }
        try meter.require(.maxDepth, UInt64(options.maxDepth)); try meter.require(.nodes, options.maxNodes)
        try meter.require(.diagnosticBytes, options.maxBytes); try meter.require(.objectMembers, UInt64(options.redaction.keys.count))
        for key in options.redaction.keys { try JSONAdmission.text(key.string, key: true, meter: &meter) }
        enum Step {
            case value(JSON, Int), array([JSON], Int, Int), object(JSONObject, Int, Int)
            case byte(UInt8), raw(String.UTF8View.Iterator), quoted(String.UTF8View.Iterator), digits([UInt8], Int)
        }
        var stack: [Step] = [], bytes: [UInt8] = [], visited: UInt64 = 0, complete = true
        func push(_ step: Step, meter: inout JSONWorkMeter) throws { try meter.retain(JSONLogicalWeights.frame); stack.append(step) }
        func quote(_ text: String, meter: inout JSONWorkMeter) throws {
            try push(.byte(34), meter: &meter); try push(.quoted(text.utf8.makeIterator()), meter: &meter); try push(.byte(34), meter: &meter)
        }
        func emit(_ byte: UInt8, meter: inout JSONWorkMeter) throws -> Bool {
            if UInt64(bytes.count) >= options.maxBytes - 7 { return false }
            try meter.work(); try meter.charge(.diagnosticBytes); try meter.retain(1); bytes.append(byte); return true
        }
        try push(.value(value, 0), meter: &meter)
        traversal: while let step = stack.popLast() {
            try meter.release(JSONLogicalWeights.frame); try meter.work()
            switch step {
            case .byte(let byte): if try !emit(byte, meter: &meter) { complete = false; break traversal }
            case .raw(var iterator):
                if let byte = iterator.next() { try push(.raw(iterator), meter: &meter); try push(.byte(byte), meter: &meter) }
            case .digits(let digits, let index):
                if index < digits.count { try push(.digits(digits, index + 1), meter: &meter); try push(.byte(digits[index] + 48), meter: &meter) }
            case .quoted(var iterator):
                if let byte = iterator.next() {
                    try push(.quoted(iterator), meter: &meter)
                    if byte == 34 || byte == 92 { try push(.byte(byte), meter: &meter); try push(.byte(92), meter: &meter) }
                    else if byte < 32 {
                        let hex = Array("0123456789abcdef".utf8)
                        for byte in [hex[Int(byte & 15)], hex[Int(byte >> 4)], 48, 48, 117, 92] { try push(.byte(byte), meter: &meter) }
                    } else { try push(.byte(byte), meter: &meter) }
                }
            case .value(let value, let depth):
                guard visited < options.maxNodes else { complete = false; break traversal }
                visited += 1; try meter.charge(.nodes)
                switch value {
                case .null: try push(.raw("null".utf8.makeIterator()), meter: &meter)
                case .boolean(let v): try push(.raw((v ? "true" : "false").utf8.makeIterator()), meter: &meter)
                case .string(let text): try quote(text, meter: &meter)
                case .number(let number):
                    let c = number.components
                    if c.exponent != 0 { try push(.raw(String(c.exponent).utf8.makeIterator()), meter: &meter); try push(.byte(101), meter: &meter) }
                    try push(.digits(c.digits, 0), meter: &meter)
                    if c.negative { try push(.byte(45), meter: &meter) }
                case .array(let array):
                    if depth == options.maxDepth { complete = false; try quote("[...]", meter: &meter) }
                    else { try push(.array(array, 0, depth + 1), meter: &meter); try push(.byte(91), meter: &meter) }
                case .object(let object):
                    if depth == options.maxDepth { complete = false; try quote("[...]", meter: &meter) }
                    else { try push(.object(object, 0, depth + 1), meter: &meter); try push(.byte(123), meter: &meter) }
                }
            case .array(let array, let index, let depth):
                if index == array.count { try push(.byte(93), meter: &meter) }
                else {
                    try push(.array(array, index + 1, depth), meter: &meter); try push(.value(array[index], depth), meter: &meter)
                    if index > 0 { try push(.byte(44), meter: &meter) }
                }
            case .object(let object, let index, let depth):
                if index == object.count { try push(.byte(125), meter: &meter) }
                else {
                    let member = object.members[index]
                    try push(.object(object, index + 1, depth), meter: &meter)
                    if try options.redaction.matches(member.key, meter: &meter) { try quote("[REDACTED]", meter: &meter) }
                    else { try push(.value(member.value, depth), meter: &meter) }
                    try push(.byte(58), meter: &meter); try quote(member.key.string, meter: &meter)
                    if index > 0 { try push(.byte(44), meter: &meter) }
                }
            }
        }
        while !stack.isEmpty { stack.removeLast(); try meter.release(JSONLogicalWeights.frame) }
        if !complete {
            // A byte ceiling may stop inside a UTF-8 scalar. Remove at most its partial tail.
            while String(bytes: bytes, encoding: .utf8) == nil { bytes.removeLast(); try meter.release(1) }
            for byte in "[...]".utf8 { try meter.work(); try meter.charge(.diagnosticBytes); try meter.retain(1); bytes.append(byte) }
        }
        for _ in bytes { try meter.work(); try meter.retain(1) }
        return .init(result: .init(text: String(decoding: bytes, as: UTF8.self), complete: complete), statistics: meter.statistics())
    }
}
