// SPDX-License-Identifier: Apache-2.0
/// A source position with a zero-based byte offset and optional human coordinates.
///
/// Line, UTF-8 byte column and physical record numbers are one-based when present.
public struct JSONSourceLocation: Sendable, Equatable, Codable {
    /// The zero-based absolute source byte offset.
    public let byteOffset: UInt64
    /// The one-based source line, when available.
    public let line: UInt64?
    /// The one-based UTF-8 byte column, when available.
    public let column: UInt64?
    /// The one-based physical record number, when available.
    public let record: UInt64?
    /// Creates byte and optional one-based human coordinates without inspecting source bytes.
    ///
    /// - Parameters:
    ///   - byteOffset: Zero-based byte offset.
    ///   - line: Optional one-based line.
    ///   - column: Optional one-based UTF-8 byte column.
    ///   - record: Optional one-based physical record.
    public init(byteOffset: UInt64, line: UInt64? = nil, column: UInt64? = nil, record: UInt64? = nil) {
        self.byteOffset = byteOffset; self.line = line; self.column = column; self.record = record
    }
}
