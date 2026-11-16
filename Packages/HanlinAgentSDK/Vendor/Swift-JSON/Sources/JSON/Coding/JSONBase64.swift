// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Native base64 loops share the coder's meter. Foundation performs no input decoding.
package enum JSONBase64 {
    private static func digit(_ value: UInt8) -> UInt8 {
        switch value { case 0..<26: value+65; case 26..<52: value+71; case 52..<62: value-4; case 62: 43; default: 47 }
    }
    private static func value(_ byte: UInt8) -> UInt8? {
        switch byte { case 65...90: byte-65; case 97...122: byte-71; case 48...57: byte+4; case 43: 62; case 47: 63; default: nil }
    }
    package static func encode(_ data: Data,meter: inout JSONWorkMeter) throws -> (text: String,bytes: UInt64) {
        var iterator = data.makeIterator(), bytes: [UInt8] = []
        func emit(_ byte: UInt8,meter: inout JSONWorkMeter) throws {
            try meter.work(); try meter.require(.stringBytes,UInt64(bytes.count)+1)
            try meter.retain(1); bytes.append(byte)
        }
        while let a = iterator.next() {
            try meter.work(); let b = iterator.next(), c = b == nil ? nil : iterator.next()
            try emit(digit(a >> 2),meter: &meter)
            try emit(digit((a & 3) << 4 | (b ?? 0) >> 4),meter: &meter)
            try emit(b == nil ? 61 : digit(((b ?? 0) & 15) << 2 | (c ?? 0) >> 6),meter: &meter)
            try emit(c == nil ? 61 : digit((c ?? 0) & 63),meter: &meter)
        }
        let count = UInt64(bytes.count)
        for _ in bytes { try meter.work() }
        try meter.retain(count); try meter.checkpoint()
        let text = String(decoding: bytes,as: UTF8.self)
        try meter.checkpoint(); try meter.release(count)
        return (text,count)
    }
    package static func decode(_ string: String,meter: inout JSONWorkMeter) throws -> Data {
        let before = meter.used(.retainedBytes)
        do {
            var iterator = string.utf8.makeIterator(), bytes: [UInt8] = []
            func malformed() -> JSONFailure { .init(.syntax,code: .invalidSyntax) }
            func emit(_ byte: UInt8,meter: inout JSONWorkMeter) throws {
                try meter.work(); try meter.retain(1); bytes.append(byte)
            }
            while let a = iterator.next() {
                try meter.work()
                guard let b = iterator.next(),let c = iterator.next(),let d = iterator.next(),let x = value(a),let y = value(b) else { throw malformed() }
                try emit(x << 2 | y >> 4,meter: &meter)
                if c == 61 {
                    guard d == 61, y & 15 == 0, iterator.next() == nil else { throw malformed() }; break
                }
                guard let z = value(c) else { throw malformed() }
                try emit(y << 4 | z >> 2,meter: &meter)
                if d == 61 { guard z & 3 == 0, iterator.next() == nil else { throw malformed() }; break }
                guard let w = value(d) else { throw malformed() }
                try emit(z << 6 | w,meter: &meter)
            }
            for _ in bytes { try meter.work() }
            try meter.retain(UInt64(bytes.count)); try meter.checkpoint()
            let result = Data(bytes)
            try meter.checkpoint(); try meter.release(UInt64(bytes.count))
            return result
        } catch {
            // No result owns failed scratch. Refund live bytes, never consumed
            // work or terminal health, so ordinary corruption can be handled.
            try meter.release(meter.used(.retainedBytes) - before)
            throw error
        }
    }
}
