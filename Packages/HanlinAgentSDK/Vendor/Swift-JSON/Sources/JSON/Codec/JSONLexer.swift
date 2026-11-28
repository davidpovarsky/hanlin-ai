// SPDX-License-Identifier: Apache-2.0
package enum JSONTokenKind: Sendable {
    case leftObject, rightObject, leftArray, rightArray, colon, comma
    case string(String), number(JSONNumber), boolean(Bool), null
}
package struct JSONToken: Sendable {
    package let kind: JSONTokenKind
    package let start: UInt64
    package let end: UInt64
}

/// Scalar reference lexer. It never repairs UTF-8 or incomplete escapes.
package struct JSONLexer {
    private enum Mode { case idle, string, number, literal([UInt8], Int) }
    private enum Escape { case normal, escaped, unicode(Int, UInt32), lowSlash, lowU, lowDigits(Int, UInt32) }
    private var mode: Mode = .idle
    private var escape: Escape = .normal
    private var bytes: [UInt8] = []
    private var start: UInt64 = 0
    private var key = false
    private var high: UInt32 = 0
    private var utf8Remaining = 0
    private var scalar: UInt32 = 0
    private var minimum: UInt32 = 0
    package var idle: Bool { if case .idle = mode { return true }; return false }
    package static func whitespace(_ b: UInt8) -> Bool { b == 32 || b == 9 || b == 10 || b == 13 }
    private func failure(_ offset: UInt64, _ code: JSONFailure.Code = .invalidSyntax) -> JSONFailure {
        .init(.syntax, code: code, location: .init(byteOffset: offset))
    }
    private mutating func append(_ byte: UInt8, meter: inout JSONWorkMeter) throws {
        try meter.require(key ? .keyBytes : .stringBytes, UInt64(bytes.count) + 1)
        try meter.charge(.aggregateTextBytes); try meter.retain(1); bytes.append(byte)
    }
    private mutating func appendScalar(_ value: UInt32, meter: inout JSONWorkMeter, offset: UInt64) throws {
        guard let scalar = Unicode.Scalar(value) else { throw failure(offset) }
        for byte in String(scalar).utf8 { try meter.work(); try append(byte, meter: &meter) }
    }
    private func hex(_ byte: UInt8) -> UInt32? {
        switch byte {
        case 48...57: return UInt32(byte - 48)
        case 65...70: return UInt32(byte - 55)
        case 97...102: return UInt32(byte - 87)
        default: return nil
        }
    }
    /// A false consumed result asks the grammar to process the same delimiter once.
    package mutating func feed(_ byte: UInt8, offset: UInt64, isKey: Bool, meter: inout JSONWorkMeter) throws -> (JSONToken?, Bool) {
        switch mode {
        case .idle:
            if Self.whitespace(byte) { return (nil, true) }
            start = offset
            let punctuation: JSONTokenKind?
            switch byte {
            case 123: punctuation = .leftObject
            case 125: punctuation = .rightObject
            case 91: punctuation = .leftArray
            case 93: punctuation = .rightArray
            case 58: punctuation = .colon
            case 44: punctuation = .comma
            default: punctuation = nil
            }
            if let punctuation { return (.init(kind: punctuation, start: offset, end: offset + 1), true) }
            if byte == 34 { mode = .string; key = isKey; escape = .normal; bytes = []; return (nil, true) }
            if byte == 45 || (48...57).contains(byte) {
                mode = .number; try meter.require(.numberTokenBytes, 1); try meter.retain(1); bytes = [byte]; return (nil, true)
            }
            let literal: [UInt8]
            switch byte { case 116: literal = [116,114,117,101]; case 102: literal = [102,97,108,115,101]; case 110: literal = [110,117,108,108]; default: throw failure(offset) }
            mode = .literal(literal, 1); return (nil, true)
        case .literal(let expected, let index):
            guard byte == expected[index] else { throw failure(offset) }
            if index + 1 == expected.count {
                mode = .idle
                let kind: JSONTokenKind = expected[0] == 110 ? .null : .boolean(expected[0] == 116)
                return (.init(kind: kind, start: start, end: offset + 1), true)
            }
            mode = .literal(expected, index + 1); return (nil, true)
        case .number:
            if (48...57).contains(byte) || byte == 46 || byte == 101 || byte == 69 || byte == 43 || byte == 45 {
                try meter.require(.numberTokenBytes, UInt64(bytes.count) + 1); try meter.retain(1); bytes.append(byte); return (nil, true)
            }
            let token = try finishNumber(end: offset, meter: &meter)
            return (token, false)
        case .string:
            if utf8Remaining > 0 {
                guard (128...191).contains(byte) else { throw failure(offset, .invalidUTF8) }
                scalar = (scalar << 6) | UInt32(byte & 63); utf8Remaining -= 1
                if utf8Remaining == 0 {
                    guard scalar >= minimum, scalar <= 0x10ffff, !(0xd800...0xdfff).contains(scalar) else { throw failure(offset, .invalidUTF8) }
                }
                try append(byte, meter: &meter); return (nil, true)
            }
            switch escape {
            case .normal:
                if byte == 34 {
                    for _ in bytes { try meter.work(); try meter.retain(1) }
                    let text = String(decoding: bytes, as: UTF8.self)
                    try meter.release(UInt64(bytes.count)); bytes = []; mode = .idle
                    return (.init(kind: .string(text), start: start, end: offset + 1), true)
                }
                if byte == 92 { escape = .escaped; return (nil, true) }
                guard byte >= 32 else { throw failure(offset) }
                if byte >= 128 {
                    switch byte {
                    case 194...223: utf8Remaining = 1; scalar = UInt32(byte & 31); minimum = 0x80
                    case 224...239: utf8Remaining = 2; scalar = UInt32(byte & 15); minimum = 0x800
                    case 240...244: utf8Remaining = 3; scalar = UInt32(byte & 7); minimum = 0x10000
                    default: throw failure(offset, .invalidUTF8)
                    }
                }
                try append(byte, meter: &meter)
            case .escaped:
                escape = .normal
                switch byte {
                case 34, 92, 47: try append(byte, meter: &meter)
                case 98: try append(8, meter: &meter)
                case 102: try append(12, meter: &meter)
                case 110: try append(10, meter: &meter)
                case 114: try append(13, meter: &meter)
                case 116: try append(9, meter: &meter)
                case 117: escape = .unicode(0, 0)
                default: throw failure(offset)
                }
            case .unicode(let count, let value):
                guard let hex = hex(byte) else { throw failure(offset) }
                let value = value * 16 + hex
                if count == 3 {
                    if (0xd800...0xdbff).contains(value) { high = value; escape = .lowSlash }
                    else {
                        guard !(0xdc00...0xdfff).contains(value) else { throw failure(offset) }
                        try appendScalar(value, meter: &meter, offset: offset); escape = .normal
                    }
                } else { escape = .unicode(count + 1, value) }
            case .lowSlash: guard byte == 92 else { throw failure(offset) }; escape = .lowU
            case .lowU: guard byte == 117 else { throw failure(offset) }; escape = .lowDigits(0, 0)
            case .lowDigits(let count, let value):
                guard let hex = hex(byte) else { throw failure(offset) }
                let value = value * 16 + hex
                if count == 3 {
                    guard (0xdc00...0xdfff).contains(value) else { throw failure(offset) }
                    try appendScalar(0x10000 + (high - 0xd800) * 1024 + value - 0xdc00, meter: &meter, offset: offset)
                    escape = .normal
                } else { escape = .lowDigits(count + 1, value) }
            }
            return (nil, true)
        }
    }
    private mutating func finishNumber(end: UInt64, meter: inout JSONWorkMeter) throws -> JSONToken {
        let number = try JSONNumber.parse(bytes, meter: &meter)
        try meter.release(UInt64(bytes.count)); bytes = []; mode = .idle
        return .init(kind: .number(number), start: start, end: end)
    }
    package mutating func finish(offset: UInt64, meter: inout JSONWorkMeter) throws -> JSONToken? {
        switch mode {
        case .idle: return nil
        case .number: return try finishNumber(end: offset, meter: &meter)
        default: throw failure(offset, .unexpectedEOF)
        }
    }
}
