// SPDX-License-Identifier: Apache-2.0
import JSON

/// RFC 3986 syntax normalization over encoded UTF-8. Unicode path spelling is never normalized.
package enum JSONSchemaURINormalization {
    private static func hex(_ value: UInt8) -> UInt8? {
        switch value { case 48...57: value-48; case 65...70: value-55; case 97...102: value-87; default: nil }
    }
    private static func unreserved(_ value: UInt8) -> Bool {
        (65...90).contains(value) || (97...122).contains(value) || (48...57).contains(value) || value == 45 || value == 46 || value == 95 || value == 126
    }
    private static func lowercase(_ value: UInt8) -> UInt8 { (65...90).contains(value) ? value+32 : value }
    private static func bounds(_ bytes: [UInt8], meter: inout JSONWorkMeter) throws -> (Int, Range<Int>?) {
        var colon = 0
        while colon < bytes.count && bytes[colon] != 58 { try meter.work(); colon += 1 }
        guard colon < bytes.count else { throw JSONSchemaCompilationFailure(.identifier) }
        if colon+2 < bytes.count && bytes[colon+1] == 47 && bytes[colon+2] == 47 {
            var end = colon+3
            while end < bytes.count && bytes[end] != 47 && bytes[end] != 63 && bytes[end] != 35 { try meter.work(); end += 1 }
            return (colon, (colon+3)..<end)
        }
        return (colon, nil)
    }
    package static func normalize(_ text: String, meter: inout JSONWorkMeter) throws -> String {
        var input: [UInt8] = []
        for byte in text.utf8 { try meter.work(); try meter.retain(1); input.append(byte) }
        let (colon, authority) = try bounds(input, meter: &meter)
        var host = authority?.lowerBound ?? input.count
        if let authority { for index in authority { try meter.work(); if input[index] == 64 { host = index+1 } } }
        var bytes: [UInt8] = [], index = 0
        func append(_ byte: UInt8, meter: inout JSONWorkMeter) throws {
            try meter.work(); try meter.retain(1); bytes.append(byte)
        }
        while index < input.count {
            try meter.work()
            let folding = index < colon || (authority.map { index >= host && index < $0.upperBound } ?? false)
            let byte = input[index]
            if byte == 37 {
                guard index+2 < input.count, let a = hex(input[index+1]), let b = hex(input[index+2]) else { throw JSONSchemaCompilationFailure(.identifier) }
                let value = a*16+b
                if unreserved(value) { try append(folding ? lowercase(value) : value, meter: &meter) }
                else {
                    try append(37, meter: &meter)
                    try append(a < 10 ? a+48 : a+55, meter: &meter)
                    try append(b < 10 ? b+48 : b+55, meter: &meter)
                }
                index += 3
            } else { try append(folding ? lowercase(byte) : byte, meter: &meter); index += 1 }
        }
        try meter.release(UInt64(input.count)); input = []
        let (schemeEnd, normalizedAuthority) = try bounds(bytes, meter: &meter)
        let pathStart = normalizedAuthority?.upperBound ?? (schemeEnd+1)
        var pathEnd = pathStart
        while pathEnd < bytes.count && bytes[pathEnd] != 63 && bytes[pathEnd] != 35 { try meter.work(); pathEnd += 1 }
        var parts: [Range<Int>] = [], begin = pathStart
        func part(_ range: Range<Int>, meter: inout JSONWorkMeter) throws {
            try meter.work(); try meter.retain(16); parts.append(range)
        }
        for end in pathStart...pathEnd {
            try meter.work()
            if end == pathEnd || bytes[end] == 47 {
                let size = end-begin, last = end == pathEnd
                if size == 1 && bytes[begin] == 46 {
                    if last { try part(end..<end, meter: &meter) }
                } else if size == 2 && bytes[begin] == 46 && bytes[begin+1] == 46 {
                    if let previous = parts.last, !(parts.count == 1 && previous.isEmpty) { parts.removeLast(); try meter.release(16) }
                    if parts.isEmpty && begin > pathStart { try part(end..<end, meter: &meter) }
                    if last && begin > pathStart { try part(end..<end, meter: &meter) }
                } else { try part(begin..<end, meter: &meter) }
                begin = end+1
            }
        }
        var output: [UInt8] = []
        func emit(_ byte: UInt8, meter: inout JSONWorkMeter) throws { try meter.work(); try meter.retain(1); output.append(byte) }
        for i in 0..<pathStart { try emit(bytes[i], meter: &meter) }
        for (i, range) in parts.enumerated() {
            if i > 0 { try emit(47, meter: &meter) }
            for index in range { try emit(bytes[index], meter: &meter) }
        }
        for i in pathEnd..<bytes.count { try emit(bytes[i], meter: &meter) }
        for _ in output { try meter.work(); try meter.retain(1) }
        let normalized = String(decoding: output, as: UTF8.self)
        try meter.release(UInt64(bytes.count + output.count) + UInt64(parts.count)*16)
        return normalized
    }
}
