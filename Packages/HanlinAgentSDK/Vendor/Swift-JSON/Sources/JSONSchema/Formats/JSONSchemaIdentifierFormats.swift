// SPDX-License-Identifier: Apache-2.0
import JSON

extension JSONSchemaFormats {
    private static func unreserved(_ b: UInt8) -> Bool { alpha(b) || digit(b) || [45,46,95,126].contains(b) }
    private static func subdelimiter(_ b: UInt8) -> Bool { [33,36,38,39,40,41,42,43,44,59,61].contains(b) }
    private static func component(_ b: ArraySlice<UInt8>, extras: [UInt8], international: Bool, meter: inout JSONWorkMeter) throws -> Bool {
        var i = b.startIndex
        while i < b.endIndex {
            try meter.work(); let byte = b[i]
            if byte == 37 { guard i+2 < b.endIndex, hex(b[i+1]) != nil, hex(b[i+2]) != nil else { return false }; i += 3; continue }
            guard unreserved(byte) || subdelimiter(byte) || extras.contains(byte) || (international && byte > 127) else { return false }; i += 1
        }
        return true
    }
    static func identifier(_ b: ArraySlice<UInt8>, absolute: Bool, international: Bool, meter: inout JSONWorkMeter) throws -> Bool {
        if international {
            try meter.retain(UInt64(b.count)); let text = String(decoding: b,as: UTF8.self)
            var query = false
            var valid = true
            for scalar in text.unicodeScalars {
                try meter.work(); let cp = scalar.value
                if cp == 63 { query = true }; if cp == 35 { query = false }
                if cp > 127 {
                    let ucs = (0xA0...0xD7FF).contains(cp) || (0xF900...0xFDCF).contains(cp) || (0xFDF0...0xFFEF).contains(cp) ||
                        ((0x10000...0xDFFFD).contains(cp) && cp & 0xFFFF <= 0xFFFD) || (0xE1000...0xEFFFD).contains(cp)
                    let `private` = (0xE000...0xF8FF).contains(cp) || (0xF0000...0xFFFFD).contains(cp) || (0x100000...0x10FFFD).contains(cp)
                    if !ucs && !(query && `private`) { valid = false }
                }
            }
            try meter.release(UInt64(b.count)); if !valid { return false }
        }
        var i = b.startIndex, schemeEnd: Int?
        while i < b.endIndex && ![47,63,35].contains(b[i]) {
            try meter.work(); if b[i] == 58 { schemeEnd = i; break }; i += 1
        }
        i = b.startIndex
        if let end = schemeEnd {
            guard end > i, alpha(b[i]) else { return false }
            for byte in b[i..<end] { try meter.work(); guard alpha(byte) || digit(byte) || [43,45,46].contains(byte) else { return false } }
            i = end+1
        } else if absolute { return false }
        if i+1 < b.endIndex && b[i] == 47 && b[i+1] == 47 {
            i += 2; let begin = i
            while i < b.endIndex && ![47,63,35].contains(b[i]) { try meter.work(); i += 1 }
            guard try authority(b[begin..<i],international: international,meter: &meter) else { return false }
        }
        let path = i
        while i < b.endIndex && b[i] != 63 && b[i] != 35 { try meter.work(); i += 1 }
        guard try component(b[path..<i],extras: [47,58,64],international: international,meter: &meter) else { return false }
        if i < b.endIndex && b[i] == 63 {
            i += 1; let begin = i
            while i < b.endIndex && b[i] != 35 { try meter.work(); i += 1 }
            guard try component(b[begin..<i],extras: [47,63,58,64],international: international,meter: &meter) else { return false }
        }
        if i < b.endIndex {
            i += 1
            guard try component(b[i...],extras: [47,63,58,64],international: international,meter: &meter) else { return false }
        }
        return true
    }
    private static func authority(_ b: ArraySlice<UInt8>, international: Bool, meter: inout JSONWorkMeter) throws -> Bool {
        var host = b.startIndex, at: Int?
        for i in b.indices { try meter.work(); if b[i] == 64 { guard at == nil else { return false }; at = i } }
        if let at { guard try component(b[host..<at],extras: [58],international: international,meter: &meter) else { return false }; host = at+1 }
        var end = b.endIndex
        if host < end && b[host] == 91 {
            var close = host+1
            while close < end && b[close] != 93 { try meter.work(); close += 1 }
            guard close < end else { return false }
            let address = b[host+1..<close]
            if address.first == 118 || address.first == 86 {
                var dot = address.startIndex+1
                while dot < address.endIndex && hex(address[dot]) != nil { try meter.work(); dot += 1 }
                guard dot > address.startIndex+1, dot < address.endIndex, address[dot] == 46, dot+1 < address.endIndex else { return false }
                for byte in address[(dot+1)...] { try meter.work(); guard unreserved(byte) || subdelimiter(byte) || byte == 58 else { return false } }
            } else if try !ipv6(address,meter: &meter) { return false }
            host = close+1
            if host == end { return true }
            guard b[host] == 58 else { return false }; host += 1
        } else {
            var colon: Int?
            for i in host..<end { try meter.work(); if b[i] == 58 { guard colon == nil else { return false }; colon = i } }
            if let colon { end = colon }
            guard try component(b[host..<end],extras: [],international: international,meter: &meter) else { return false }
            guard let colon else { return true }; host = colon+1; end = b.endIndex
        }
        for byte in b[host..<end] { try meter.work(); guard digit(byte) else { return false } }
        return true
    }
    static func template(_ b: ArraySlice<UInt8>, meter: inout JSONWorkMeter) throws -> Bool {
        var i = b.startIndex
        while i < b.endIndex {
            try meter.work()
            if b[i] != 123 {
                guard b[i] != 125, b[i] > 32, b[i] != 127, ![34,60,62,92,94,96,124].contains(b[i]) else { return false }
                if b[i] == 37 { guard i+2 < b.endIndex, hex(b[i+1]) != nil, hex(b[i+2]) != nil else { return false }; i += 2 }
                i += 1; continue
            }
            i += 1
            if i < b.endIndex && [43,35,46,47,59,63,38].contains(b[i]) { i += 1 }
            while true {
                let begin = i; var afterDot = true
                while i < b.endIndex {
                    try meter.work(); let byte = b[i]
                    if alpha(byte) || digit(byte) || byte == 95 { afterDot = false; i += 1 }
                    else if byte == 46 { guard !afterDot else { return false }; afterDot = true; i += 1 }
                    else if byte == 37 { guard i+2 < b.endIndex, hex(b[i+1]) != nil, hex(b[i+2]) != nil else { return false }; i += 3; afterDot = false }
                    else { break }
                }
                guard i > begin, !afterDot, i < b.endIndex else { return false }
                if b[i] == 42 { i += 1 }
                else if b[i] == 58 {
                    i += 1; let start = i
                    guard i < b.endIndex, (49...57).contains(b[i]) else { return false }
                    while i < b.endIndex && digit(b[i]) { try meter.work(); i += 1 }
                    guard i-start <= 4 else { return false }
                }
                guard i < b.endIndex else { return false }
                if b[i] == 125 { i += 1; break }
                guard b[i] == 44 else { return false }; i += 1
            }
        }
        return true
    }
}
