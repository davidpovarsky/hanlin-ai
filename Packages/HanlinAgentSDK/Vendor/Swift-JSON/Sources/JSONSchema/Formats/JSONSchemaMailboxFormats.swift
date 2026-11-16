// SPDX-License-Identifier: Apache-2.0
import JSON

extension JSONSchemaFormats {
    static func email(_ b: ArraySlice<UInt8>, international: Bool, meter: inout JSONWorkMeter) throws -> Bool {
        guard !b.isEmpty else { return false }
        var i = b.startIndex
        if b[i] == 34 {
            i += 1; var closed = false
            while i < b.endIndex {
                try meter.work(); let byte = b[i]; i += 1
                if byte == 34 { closed = true; break }
                if byte == 92 {
                    guard i < b.endIndex, (32...126).contains(b[i]) else { return false }; i += 1
                } else if !((32...33).contains(byte) || (35...91).contains(byte) || (93...126).contains(byte) || (international && byte > 127)) { return false }
            }
            guard closed else { return false }
        } else {
            var afterDot = true
            while i < b.endIndex && b[i] != 64 {
                try meter.work(); let byte = b[i]; i += 1
                if byte == 46 { guard !afterDot else { return false }; afterDot = true }
                else {
                    guard alpha(byte) || digit(byte) || [33,35,36,37,38,39,42,43,45,47,61,63,94,95,96,123,124,125,126].contains(byte) || (international && byte > 127) else { return false }
                    afterDot = false
                }
            }
            guard !afterDot else { return false }
        }
        guard i < b.endIndex, b[i] == 64, i-b.startIndex <= 64 else { return false }; i += 1
        let domain = b[i...]
        if domain.first == 91 {
            guard domain.last == 93 else { return false }
            let address = domain.dropFirst().dropLast()
            if address.count >= 5 {
                let prefix: [UInt8] = [73,80,118,54,58]
                var matches = true
                for n in 0..<5 { try meter.work(); let byte = address[address.startIndex+n]; if (byte | 32) != (prefix[n] | 32) { matches = false } }
                if matches { return try ipv6(address.dropFirst(5),meter: &meter) }
            }
            return try ipv4(address,meter: &meter)
        }
        return try hostname(domain,international: international,meter: &meter)
    }
    static func hostname(_ b: ArraySlice<UInt8>, international: Bool, meter: inout JSONWorkMeter) throws -> Bool {
        try JSONIDNA.hostname(b,international: international,meter: &meter)
    }
}
