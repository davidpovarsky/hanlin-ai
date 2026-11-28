// SPDX-License-Identifier: Apache-2.0
import Foundation
/// An immutable value and optional coherent owned source snapshot.
///
/// Replacing the root discards source bytes and spans so stale locations cannot escape.
public struct JSONDocument: Sendable {
    /// The immutable root value associated with this document.
    public let root: JSON
    /// An optional caller-supplied source label, unrelated to network resolution.
    public let source: String?
    /// Owned original UTF-8 input when parsed with source mapping, otherwise nil.
    public let sourceBytes: Data?
    /// Optional bounded mapping from typed value paths to original source byte spans.
    public let sourceMap: JSONSourceMap?
    /// Creates a root-only document with no source label, bytes or mapping.
    ///
    /// - Parameters:
    ///   - root: The trusted root value; no source mapping is retained.
    public init(root: JSON) { self.root = root; source = nil; sourceBytes = nil; sourceMap = nil }
    package init(root: JSON, source: String?, bytes: Data, map: JSONSourceMap) {
        self.root = root; self.source = source; sourceBytes = bytes; sourceMap = map
    }
    /// Returns a root-only document, discarding source bytes, label and stale spans.
    ///
    /// - Parameters:
    ///   - root: The trusted root value; no source mapping is retained.
    public func replacingRoot(_ root: JSON) -> Self { Self(root: root) }
}

extension JSONParser {
    /// Parses a strict document while owning the input and bounded source mapping.
    ///
    /// - Returns: A coherent immutable root, source bytes and half-open spans.
    /// - Throws: Syntax, source-map, retention or work failure, or cancellation.
    ///
    /// - Parameters:
    ///   - data: The owned input bytes supplied by the caller.
    ///   - source: An optional diagnostic source label; no resource is fetched.
    public func parseDocument(_ data: Data, source: String? = nil) throws -> JSONDocument {
        var meter = try JSONWorkMeter(limits: options.limits, domain: .parsing)
        if let source { try JSONAdmission.text(source, meter: &meter, owned: true) }
        var bytes: [UInt8] = []
        for byte in data { try meter.work(); try meter.require(.inputBytes, UInt64(bytes.count) + 1); try meter.retain(1); bytes.append(byte) }
        return try parseDocument(bytes, source: source, meter: &meter)
    }
    package func parseDocument(_ bytes: [UInt8], source: String?, meter: inout JSONWorkMeter) throws -> JSONDocument {
        var machine = JSONTokenMachine(), assembler = JSONValueAssembler(), mapping = JSONSourceMapBuilder(), index = 0
        var result: JSON?
        while index < bytes.count {
            if let event = try machine.next(in: bytes, index: &index, meter: &meter) {
                try mapping.consume(event, meter: &meter)
                if let value = try assembler.consume(event, meter: &meter) { result = value }
            }
        }
        while machine.state != .finished {
            if let event = try machine.finish(meter: &meter) {
                try mapping.consume(event, meter: &meter)
                if let value = try assembler.consume(event, meter: &meter) { result = value }
            }
        }
        guard let result else { throw JSONFailure(.syntax, code: .unexpectedEOF) }
        for _ in bytes { try meter.work(); try meter.retain(1) }
        return .init(root: result, source: source, bytes: Data(bytes), map: mapping.finish())
    }
}
