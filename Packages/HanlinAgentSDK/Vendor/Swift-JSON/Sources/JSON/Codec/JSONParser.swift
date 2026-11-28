// SPDX-License-Identifier: Apache-2.0
import Foundation
/// An immutable strict UTF-8 parser with invocation-owned state.
///
/// Each call accepts exactly one root, trailing JSON whitespace and EOF. Duplicate
/// decoded keys, BOMs, malformed UTF-8 and unpaired surrogate escapes fail. Calls may
/// run concurrently; limits and cancellation apply to the work owned by each call.
public struct JSONParser: Sendable {
    /// The immutable configuration used to create each invocation.
    public let options: JSONParsingOptions
    /// Creates an immutable parser facade. Limits are checked when parsing begins.
    ///
    /// - Parameters:
    ///   - options: The value configuration used by this facade or operation.
    public init(options: JSONParsingOptions = .init()) { self.options = options }
    /// Parses exactly one strict UTF-8 JSON document.
    ///
    /// - Returns: The admitted root after trailing whitespace and EOF.
    /// - Throws: `JSONFailure` for syntax, admission or configuration failure, or cancellation.
    ///
    /// - Parameters:
    ///   - text: The encoded input text to admit.
    public func parse(_ text: String) throws -> JSON { try copyAndParse(text.utf8) }
    /// Parses exactly one strict UTF-8 JSON document.
    ///
    /// - Returns: The admitted root after trailing whitespace and EOF.
    /// - Throws: `JSONFailure` for syntax, admission or configuration failure, or cancellation.
    ///
    /// - Parameters:
    ///   - data: The owned input bytes supplied by the caller.
    public func parse(_ data: Data) throws -> JSON { try copyAndParse(data) }
    private func copyAndParse<C: Collection>(_ input: C) throws -> JSON where C.Element == UInt8 {
        var meter = try JSONWorkMeter(limits: options.limits, domain: .parsing)
        var bytes: [UInt8] = []
        for byte in input {
            try meter.work(); try meter.require(.inputBytes, UInt64(bytes.count) + 1)
            try meter.retain(1); bytes.append(byte)
        }
        return try parse(bytes, meter: &meter)
    }
    /// Parses exactly one strict UTF-8 JSON document.
    ///
    /// - Returns: The admitted root after trailing whitespace and EOF.
    /// - Throws: `JSONFailure` for syntax, admission or configuration failure, or cancellation.
    ///
    /// - Parameters:
    ///   - bytes: The UTF-8 bytes supplied by the caller.
    public func parse(_ bytes: [UInt8]) throws -> JSON { try parseWithReport(bytes).result }
    /// Parses owned UTF-8 bytes and returns successful parsing accounting.
    ///
    /// - Returns: A certified root and versioned charged counts.
    /// - Throws: Syntax, resource or configuration failure, or cancellation; no report exists on failure.
    ///
    /// - Parameters:
    ///   - bytes: The UTF-8 bytes supplied by the caller.
    public func parseWithReport(_ bytes: [UInt8]) throws -> JSONOperationReport<JSON> {
        var meter = try JSONWorkMeter(limits: options.limits, domain: .parsing)
        let value = try parse(bytes, meter: &meter)
        return .init(result: value, statistics: meter.statistics())
    }
    package func parse(_ bytes: [UInt8], meter: inout JSONWorkMeter) throws -> JSON {
        try meter.require(.inputBytes, UInt64(bytes.count))
        var machine = JSONTokenMachine(), assembler = JSONValueAssembler(), index = 0
        var result: JSON?
        while index < bytes.count {
            if let event = try machine.next(in: bytes, index: &index, meter: &meter),
               let value = try assembler.consume(event, meter: &meter) { result = value }
        }
        while machine.state != .finished {
            if let event = try machine.finish(meter: &meter), let value = try assembler.consume(event, meter: &meter) { result = value }
        }
        guard let result else { throw JSONFailure(.syntax, code: .unexpectedEOF) }
        return result
    }
}
