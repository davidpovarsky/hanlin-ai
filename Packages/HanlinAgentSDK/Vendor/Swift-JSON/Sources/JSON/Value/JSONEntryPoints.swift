// SPDX-License-Identifier: Apache-2.0
import Foundation

extension JSON {
    /// Parses one strict document, including trailing whitespace and EOF.
    ///
    /// Delegates to `JSONParser.parse(_:)` with the same String input and options.
    /// Use the parser's report or document methods for accounting or source maps.
    /// - Parameters:
    ///   - text: JSON source text, without permissive syntax or Unicode normalization.
    ///   - options: Finite parsing limits forwarded unchanged to the parser.
    /// - Returns: The admitted exact root.
    /// - Throws: The parser's syntax, resource or configuration error, or cancellation.
    public static func parse(_ text: String, options: JSONParsingOptions = .init()) throws -> JSON {
        try JSONParser(options: options).parse(text)
    }

    /// Parses one strict UTF-8 document from Data, including EOF.
    ///
    /// Delegates to `JSONParser.parse(_:)` with the same Data input and options.
    /// - Parameters:
    ///   - data: Encoded JSON bytes; malformed UTF-8 and duplicate decoded keys fail.
    ///   - options: Finite parsing limits forwarded unchanged to the parser.
    /// - Returns: The admitted exact root.
    /// - Throws: The parser's syntax, resource or configuration error, or cancellation.
    public static func parse(_ data: Data, options: JSONParsingOptions = .init()) throws -> JSON {
        try JSONParser(options: options).parse(data)
    }

    /// Parses one strict UTF-8 document from bytes, including EOF.
    ///
    /// Delegates to `JSONParser.parse(_:)` with the same array and options.
    /// - Parameters:
    ///   - bytes: Encoded JSON bytes; no replacement decoding is performed.
    ///   - options: Finite parsing limits forwarded unchanged to the parser.
    /// - Returns: The admitted exact root.
    /// - Throws: The parser's syntax, resource or configuration error, or cancellation.
    public static func parse(_ bytes: [UInt8], options: JSONParsingOptions = .init()) throws -> JSON {
        try JSONParser(options: options).parse(bytes)
    }

    /// Builds an exact ordered object using one exclusive checked accumulator.
    ///
    /// Delegates once to `JSONObject.build(limits:_:)`, then wraps its result.
    /// Appends share its cumulative budget; callback computation is caller work.
    /// - Parameters:
    ///   - limits: Finite construction limits forwarded unchanged to the builder.
    ///   - body: A synchronous callback borrowing the noncopyable accumulator.
    /// - Returns: The built object as a JSON value.
    /// - Throws: Duplicate keys, resource failure, cancellation or the callback's error.
    public static func buildObject(limits: JSONLimits = .balanced, _ body: (inout JSONObjectAccumulator) throws -> Void) throws -> JSON {
        .object(try JSONObject.build(limits: limits, body))
    }

    /// Admits the exact decimal meaning of one strict JSON number token.
    ///
    /// Delegates once to `JSONNumber.init(parsing:limits:)`; no binary floating
    /// conversion occurs. The admitted original lexeme remains available.
    /// - Parameters:
    ///   - text: A complete strict numeric token, such as `"0.1"`.
    ///   - limits: Finite numeric admission limits forwarded unchanged.
    /// - Returns: The admitted number as a JSON value.
    /// - Throws: Numeric syntax, resource or configuration failure, or cancellation.
    public static func number(parsing text: String, limits: JSONLimits = .balanced) throws -> JSON {
        .number(try JSONNumber(parsing: text, limits: limits))
    }

    /// Resolves a previously parsed RFC 6901 Pointer from this root.
    ///
    /// Delegates once to `JSONPointer.resolve(in:limits:)`. Pointer construction
    /// remains a separate caller operation. Missing targets and wrong kinds throw.
    /// - Parameters:
    ///   - pointer: A reusable Pointer with exact decoded tokens.
    ///   - limits: Finite admission and traversal limits forwarded unchanged.
    /// - Returns: The selected value; an empty Pointer selects this root.
    /// - Throws: Pointer, type, resource or configuration failure, or cancellation.
    public func value(at pointer: JSONPointer, limits: JSONLimits = .balanced) throws -> JSON {
        try pointer.resolve(in: self, limits: limits)
    }
}

extension JSONObject {
    /// Tests exact scalar-key membership, including members whose value is null.
    ///
    /// Uses the existing unmetered indexed subscript. For bounded reads use
    /// `JSON.read(limits:_:)` and cursor presence. Dynamic Strings require `JSONKey`.
    /// - Parameter key: The exact key; string literals are accepted without normalization.
    /// - Returns: Whether the member exists, independently of its value kind.
    public func containsKey(_ key: JSONKey) -> Bool { self[key] != nil }
}
