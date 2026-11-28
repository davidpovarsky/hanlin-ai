// SPDX-License-Identifier: Apache-2.0
import JSON

/// IDNA2008 with UTS46 nontransitional/STD3 processing, fixed Unicode 13.0.0. No network lookup.
package enum JSONIDNA {
    private static func label(_ points: [UInt32], meter: inout JSONWorkMeter) throws -> Bool {
        guard !points.isEmpty, points.first != 45, points.last != 45,
              points.count < 4 || points[2] != 45 || points[3] != 45,
              try JSONIDNAUnicode.properties(points[0],meter: &meter) & 4 == 0,
              try JSONIDNAUnicode.isNFC(points,meter: &meter) else { return false }
        var kana = false, arabic = false, extended = false
        for cp in points {
            try meter.work(); let property = try JSONIDNAUnicode.properties(cp,meter: &meter)
            if property & 3 == 0 { return false }
            if (3...5).contains(property >> 21 & 7) { kana = true }
            if (0x660...0x669).contains(cp) { arabic = true }
            if (0x6F0...0x6F9).contains(cp) { extended = true }
        }
        if arabic && extended { return false }
        for i in points.indices {
            try meter.work(); let cp = points[i]
            switch cp {
            case 0xB7: guard i > 0, i+1 < points.count, points[i-1] == 108, points[i+1] == 108 else { return false }
            case 0x375: guard i+1 < points.count, try JSONIDNAUnicode.properties(points[i+1],meter: &meter) >> 21 & 7 == 1 else { return false }
            case 0x5F3,0x5F4: guard i > 0, try JSONIDNAUnicode.properties(points[i-1],meter: &meter) >> 21 & 7 == 2 else { return false }
            case 0x30FB: guard kana else { return false }
            case 0x200D: guard i > 0, try JSONIDNAUnicode.properties(points[i-1],meter: &meter) >> 8 & 255 == 9 else { return false }
            case 0x200C:
                if i > 0, try JSONIDNAUnicode.properties(points[i-1],meter: &meter) >> 8 & 255 == 9 { continue }
                var previous = i, next = i+1
                while previous > 0 { try meter.work(); if try JSONIDNAUnicode.properties(points[previous-1],meter: &meter) >> 24 == 4 { previous -= 1 } else { break } }
                while next < points.count { try meter.work(); if try JSONIDNAUnicode.properties(points[next],meter: &meter) >> 24 == 4 { next += 1 } else { break } }
                guard previous > 0, next < points.count else { return false }
                let left = try JSONIDNAUnicode.properties(points[previous-1],meter: &meter) >> 24
                let right = try JSONIDNAUnicode.properties(points[next],meter: &meter) >> 24
                guard left == 1 || left == 2, right == 1 || right == 3 else { return false }
            default: break
            }
        }
        return true
    }
    private static func bidi(_ points: [UInt32], meter: inout JSONWorkMeter) throws -> Bool {
        let first = try JSONIDNAUnicode.properties(points[0],meter: &meter) >> 16 & 31
        guard first == 1 || first == 2 || first == 3 else { return false }
        let rtl = first != 3
        var european = false, arabic = false, last = first
        for cp in points {
            let value = try JSONIDNAUnicode.properties(cp,meter: &meter) >> 16 & 31
            guard rtl ? [1,2,4,5,6,7,8,9,10,11].contains(value) : [3,4,6,7,8,9,10,11].contains(value) else { return false }
            if value == 4 { european = true }; if value == 5 { arabic = true }; if value != 11 { last = value }
        }
        return rtl ? [1,2,4,5].contains(last) && !(european && arabic) : [3,4].contains(last)
    }
    package static func hostname(_ input: ArraySlice<UInt8>, international: Bool, meter: inout JSONWorkMeter) throws -> Bool {
        let before = meter.used(.retainedBytes)
        let valid: Bool
        if international {
            if let mapped = try JSONIDNAMapping.apply(input,meter: &meter) { valid = try validate(mapped[...],international: true,meter: &meter) }
            else { valid = false }
        } else { valid = try validate(input,international: false,meter: &meter) }
        try meter.release(meter.used(.retainedBytes)-before); return valid
    }
    private static func validate(_ input: ArraySlice<UInt8>, international: Bool, meter: inout JSONWorkMeter) throws -> Bool {
        guard !input.isEmpty, input.last != 46, input.count <= 1016 else { return false }
        let before = meter.used(.retainedBytes)
        var labels: [[UInt32]] = [], start = input.startIndex, length = 0, rtl = false, valid = true
        for end in input.startIndex...input.endIndex {
            try meter.work(); if end != input.endIndex && input[end] != 46 { continue }
            guard end > start else { valid = false; break }
            let bytes = input[start..<end]
            var points: [UInt32] = [], encoded = false, nonASCII = false
            if bytes.count >= 4, (bytes[start] | 32) == 120, (bytes[start+1] | 32) == 110, bytes[start+2] == 45, bytes[start+3] == 45 {
                guard bytes.count <= 63, let decoded = try JSONPunycode.decode(bytes.dropFirst(4),meter: &meter) else { valid = false; break }
                points = decoded; encoded = true
                guard let encodedBytes = try JSONPunycode.encode(points,meter: &meter), encodedBytes.count == bytes.count-4 else { valid = false; break }
                var same = true
                for i in encodedBytes.indices { try meter.work(); let byte = bytes[start+4+i]; if encodedBytes[i] != ((65...90).contains(byte) ? byte+32 : byte) { same = false } }
                guard same else { valid = false; break }
            } else {
                try meter.retain(UInt64(bytes.count)); let text = String(decoding: bytes,as: UTF8.self)
                for scalar in text.unicodeScalars {
                    try meter.work(); var cp = scalar.value
                    if cp > 127 { nonASCII = true }
                    if (65...90).contains(cp) { cp += 32 }
                    try meter.retain(8); points.append(cp)
                }
                try meter.release(UInt64(bytes.count))
                guard international || !nonASCII else { valid = false; break }
            }
            for cp in points { try meter.work(); if cp > 127 { nonASCII = true }; let prop = try JSONIDNAUnicode.properties(cp,meter: &meter) >> 16 & 31; if prop == 1 || prop == 2 || prop == 5 { rtl = true } }
            if encoded || nonASCII {
                guard nonASCII, try label(points,meter: &meter), let encodedBytes = try JSONPunycode.encode(points,meter: &meter) else { valid = false; break }
                length += encodedBytes.count+4
            } else {
                guard bytes.count <= 63, points.first != 45, points.last != 45 else { valid = false; break }
                for cp in points { try meter.work(); guard (97...122).contains(cp) || (48...57).contains(cp) || cp == 45 else { valid = false; break } }
                if !valid { break }; length += bytes.count
            }
            try meter.retain(16); labels.append(points); start = end+1; if labels.count > 1 { length += 1 }
            if length > 253 { valid = false; break }
        }
        if valid && rtl { for points in labels { try meter.work(); if try !bidi(points,meter: &meter) { valid = false; break } } }
        try meter.release(meter.used(.retainedBytes)-before); return valid
    }
}
