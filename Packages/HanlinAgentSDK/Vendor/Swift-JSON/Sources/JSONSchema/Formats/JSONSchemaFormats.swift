// SPDX-License-Identifier: Apache-2.0
import JSON
import JSONRegexRuntime

/// Original scalar format recognizers. All loops use the invocation's meter.
package enum JSONSchemaFormats {
    package enum Name: String, Sendable {
        case date, time, dateTime = "date-time", duration, email, idnEmail = "idn-email"
        case hostname, idnHostname = "idn-hostname", ipv4, ipv6, uri, uriReference = "uri-reference"
        case iri, iriReference = "iri-reference", uuid, uriTemplate = "uri-template"
        case jsonPointer = "json-pointer", relativePointer = "relative-json-pointer", regex
    }
    package static func name(_ text: String, meter: inout JSONWorkMeter) throws -> Name? {
        for byte in text.utf8 { try meter.work(); if byte > 127 { return nil } }
        return Name(rawValue: text)
    }
    package static func test(_ text: String, name: Name, meter: inout JSONWorkMeter) throws -> Bool {
        if name == .regex {
            let before = meter.used(.retainedBytes)
            do { _ = try RegexCompiler.compile(text,meter: &meter) }
            catch is RegexFailure { try meter.release(meter.used(.retainedBytes)-before); return false }
            try meter.release(meter.used(.retainedBytes)-before); return true
        }
        var bytes: [UInt8] = []
        for byte in text.utf8 { try meter.work(); try meter.retain(1); bytes.append(byte) }
        let b = bytes[...], valid: Bool
        switch name {
        case .date: valid = try date(b,meter: &meter)
        case .time: valid = try time(b,meter: &meter)
        case .dateTime:
            valid = try b.count >= 20 && date(b.prefix(10),meter: &meter) && (b[10] == 84 || b[10] == 116) && time(b.dropFirst(11),meter: &meter)
        case .duration: valid = try duration(b,meter: &meter)
        case .ipv4: valid = try ipv4(b,meter: &meter)
        case .ipv6: valid = try ipv6(b,meter: &meter)
        case .uuid:
            var okay = b.count == 36
            for i in b.indices { try meter.work(); if [8,13,18,23].contains(i) ? b[i] != 45 : hex(b[i]) == nil { okay = false } }
            valid = okay
        case .jsonPointer: valid = try pointer(b,meter: &meter)
        case .relativePointer:
            var i = b.startIndex
            while i < b.endIndex && digit(b[i]) { try meter.work(); i += 1 }
            valid = try i > b.startIndex && (i-b.startIndex == 1 || b[b.startIndex] != 48) &&
                ((i+1 == b.endIndex && b[i] == 35) || pointer(b[i...],meter: &meter))
        case .uri,.uriReference,.iri,.iriReference:
            valid = try identifier(b,absolute: name == .uri || name == .iri,international: name == .iri || name == .iriReference,meter: &meter)
        case .uriTemplate: valid = try template(b,meter: &meter)
        case .email,.idnEmail: valid = try email(b,international: name == .idnEmail,meter: &meter)
        case .hostname,.idnHostname: valid = try hostname(b,international: name == .idnHostname,meter: &meter)
        case .regex: throw JSONSchemaEvaluationFailure(.backend)
        }
        try meter.release(UInt64(bytes.count)); return valid
    }
    static func digit(_ b: UInt8) -> Bool { (48...57).contains(b) }
    static func alpha(_ b: UInt8) -> Bool { (65...90).contains(b) || (97...122).contains(b) }
    static func hex(_ b: UInt8) -> UInt8? { switch b { case 48...57: b-48; case 65...70: b-55; case 97...102: b-87; default: nil } }
    static func decimal(_ b: ArraySlice<UInt8>, meter: inout JSONWorkMeter) throws -> Int? {
        var value = 0
        for byte in b { try meter.work(); guard digit(byte), value <= 10000 else { return nil }; value = value*10+Int(byte-48) }
        return b.isEmpty ? nil : value
    }
    static func date(_ b: ArraySlice<UInt8>, meter: inout JSONWorkMeter) throws -> Bool {
        guard b.count == 10 else { return false }; let s = b.startIndex
        guard b[s+4] == 45, b[s+7] == 45,
              let y = try decimal(b[s..<s+4],meter: &meter), let m = try decimal(b[s+5..<s+7],meter: &meter),
              let d = try decimal(b[s+8..<s+10],meter: &meter), (1...12).contains(m) else { return false }
        let days = [31,(y%4 == 0 && (y%100 != 0 || y%400 == 0)) ? 29 : 28,31,30,31,30,31,31,30,31,30,31]
        return d >= 1 && d <= days[m-1]
    }
    static func time(_ b: ArraySlice<UInt8>, meter: inout JSONWorkMeter) throws -> Bool {
        guard b.count >= 9 else { return false }; let s = b.startIndex
        guard b[s+2] == 58, b[s+5] == 58,
              let h = try decimal(b[s..<s+2],meter: &meter), let m = try decimal(b[s+3..<s+5],meter: &meter),
              let second = try decimal(b[s+6..<s+8],meter: &meter), h < 24, m < 60, second <= 60 else { return false }
        var i = s+8
        if b[i] == 46 {
            i += 1; let begin = i
            while i < b.endIndex && digit(b[i]) { try meter.work(); i += 1 }
            guard i > begin, i < b.endIndex else { return false }
        }
        var offset = 0
        if b[i] == 90 || b[i] == 122 { guard i+1 == b.endIndex else { return false } }
        else {
            guard b.endIndex-i == 6, b[i] == 43 || b[i] == 45, b[i+3] == 58,
                  let oh = try decimal(b[i+1..<i+3],meter: &meter), let om = try decimal(b[i+4..<i+6],meter: &meter), oh < 24, om < 60 else { return false }
            offset = (oh*60+om)*(b[i] == 43 ? 1 : -1)
        }
        return second != 60 || ((h*60+m-offset)%1440+1440)%1440 == 1439
    }
    static func duration(_ b: ArraySlice<UInt8>, meter: inout JSONWorkMeter) throws -> Bool {
        guard b.first == 80 else { return false }
        var i = b.startIndex+1, previous: Int?, any = false, inTime = false, timeAny = false
        while i < b.endIndex {
            try meter.work()
            if b[i] == 84 {
                guard !inTime else { return false }; inTime = true; previous = nil; i += 1; continue
            }
            let begin = i
            while i < b.endIndex && digit(b[i]) { try meter.work(); i += 1 }
            guard i > begin, i < b.endIndex else { return false }
            let unit = b[i]; i += 1
            if unit == 87 { return !any && !inTime && i == b.endIndex }
            let order: Int
            if inTime { switch unit { case 72: order = 0; case 77: order = 1; case 83: order = 2; default: return false }; timeAny = true }
            else { switch unit { case 89: order = 0; case 77: order = 1; case 68: order = 2; default: return false } }
            if let previous, order != previous+1 { return false }
            previous = order; any = true
        }
        return any && (!inTime || timeAny)
    }
    static func pointer(_ b: ArraySlice<UInt8>, meter: inout JSONWorkMeter) throws -> Bool {
        guard b.isEmpty || b.first == 47 else { return false }
        var i = b.startIndex
        while i < b.endIndex {
            try meter.work()
            if b[i] == 126 { guard i+1 < b.endIndex, b[i+1] == 48 || b[i+1] == 49 else { return false }; i += 1 }
            i += 1
        }
        return true
    }
    static func ipv4(_ b: ArraySlice<UInt8>, meter: inout JSONWorkMeter) throws -> Bool {
        var start = b.startIndex, count = 0
        for i in b.startIndex...b.endIndex {
            try meter.work()
            if i == b.endIndex || b[i] == 46 {
                guard i > start, i-start <= 3, i-start == 1 || b[start] != 48,
                      let value = try decimal(b[start..<i],meter: &meter), value <= 255 else { return false }
                count += 1; start = i+1
            }
        }
        return count == 4
    }
    static func ipv6(_ b: ArraySlice<UInt8>, meter: inout JSONWorkMeter) throws -> Bool {
        guard !b.isEmpty else { return false }
        var i = b.startIndex, groups = 0, compressed = false
        if b[i] == 58 { guard i+1 < b.endIndex && b[i+1] == 58 else { return false }; compressed = true; i += 2 }
        while i < b.endIndex {
            let begin = i; var dotted = false
            while i < b.endIndex && b[i] != 58 { try meter.work(); if b[i] == 46 { dotted = true }; i += 1 }
            if dotted {
                guard i == b.endIndex, try ipv4(b[begin..<i],meter: &meter) else { return false }; groups += 2
            } else {
                guard i > begin, i-begin <= 4 else { return false }
                for byte in b[begin..<i] { try meter.work(); guard hex(byte) != nil else { return false } }; groups += 1
            }
            guard groups <= 8 else { return false }
            if i < b.endIndex {
                i += 1
                if i < b.endIndex && b[i] == 58 { guard !compressed else { return false }; compressed = true; i += 1 }
                else if i == b.endIndex { return false }
            }
        }
        return compressed ? groups < 8 : groups == 8
    }
}
