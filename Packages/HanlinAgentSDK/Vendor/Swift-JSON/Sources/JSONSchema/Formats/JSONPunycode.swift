// SPDX-License-Identifier: Apache-2.0
import JSON

/// Original checked RFC 3492 implementation; arithmetic overflow rejects malformed encoded labels.
package enum JSONPunycode {
    private static func adapt(_ delta: UInt64, points: UInt64, first: Bool, meter: inout JSONWorkMeter) throws -> UInt64? {
        var d = first ? delta/700 : delta/2
        let (sum,overflow) = d.addingReportingOverflow(d/points); guard !overflow else { return nil }; d = sum
        var k: UInt64 = 0
        while d > 455 { try meter.work(); d /= 35; k += 36 }
        return k+36*d/(d+38)
    }
    package static func decode(_ input: ArraySlice<UInt8>, meter: inout JSONWorkMeter) throws -> [UInt32]? {
        var output: [UInt32] = [], lastDash: Int?
        for i in input.indices { try meter.work(); if input[i] == 45 { lastDash = i } }
        var cursor = input.startIndex
        if let dash = lastDash {
            for byte in input[..<dash] { try meter.work(); guard byte < 128 else { return nil }; try meter.retain(8); output.append(UInt32((65...90).contains(byte) ? byte+32 : byte)) }
            cursor = dash+1
        }
        var n: UInt64 = 128, i: UInt64 = 0, bias: UInt64 = 72
        while cursor < input.endIndex {
            let old = i; var weight: UInt64 = 1, k: UInt64 = 36
            while true {
                try meter.work(); guard cursor < input.endIndex else { return nil }
                let byte = input[cursor]; cursor += 1
                let digit: UInt64
                switch byte { case 65...90: digit = UInt64(byte-65); case 97...122: digit = UInt64(byte-97); case 48...57: digit = UInt64(byte-22); default: return nil }
                let (product,o1) = digit.multipliedReportingOverflow(by: weight), (sum,o2) = i.addingReportingOverflow(product)
                guard !o1 && !o2 else { return nil }; i = sum
                let threshold = k <= bias ? 1 : (k >= bias+26 ? 26 : k-bias)
                if digit < threshold { break }
                let (next,overflow) = weight.multipliedReportingOverflow(by: 36-threshold); guard !overflow else { return nil }; weight = next; k += 36
            }
            let size = UInt64(output.count)+1
            guard let nextBias = try adapt(i-old,points: size,first: old == 0,meter: &meter) else { return nil }; bias = nextBias
            let (next,overflow) = n.addingReportingOverflow(i/size); guard !overflow, next <= 0x10FFFF, !(0xD800...0xDFFF).contains(next) else { return nil }
            n = next; i %= size
            try meter.retain(8)
            // Insert explicitly so every shifted scalar participates in cancellation/work limits.
            output.append(0); var position = output.count-1
            while position > Int(i) { try meter.work(); output[position] = output[position-1]; position -= 1 }
            output[position] = UInt32(n); i += 1
        }
        return output
    }
    package static func encode(_ input: [UInt32], meter: inout JSONWorkMeter) throws -> [UInt8]? {
        var output: [UInt8] = [], basic = 0
        func append(_ byte: UInt8, meter: inout JSONWorkMeter) throws -> Bool {
            try meter.work(); guard output.count < 59 else { return false }; try meter.retain(1); output.append(byte); return true
        }
        for cp in input { try meter.work(); if cp < 128 { guard try append(UInt8(cp),meter: &meter) else { return nil }; basic += 1 } }
        var handled = basic
        if basic > 0 { guard try append(45,meter: &meter) else { return nil } }
        var n: UInt64 = 128, delta: UInt64 = 0, bias: UInt64 = 72
        while handled < input.count {
            var minimum: UInt64 = 0x110000
            for cp in input { try meter.work(); if UInt64(cp) >= n { minimum = min(minimum,UInt64(cp)) } }
            let (product,o1) = (minimum-n).multipliedReportingOverflow(by: UInt64(handled)+1)
            let (sum,o2) = delta.addingReportingOverflow(product); guard !o1 && !o2 else { return nil }; delta = sum; n = minimum
            for cp in input {
                try meter.work()
                if UInt64(cp) < n { let (next,overflow) = delta.addingReportingOverflow(1); guard !overflow else { return nil }; delta = next }
                if UInt64(cp) == n {
                    var q = delta, k: UInt64 = 36
                    while true {
                        try meter.work(); let threshold = k <= bias ? 1 : (k >= bias+26 ? 26 : k-bias)
                        if q < threshold { break }
                        let digit = threshold+(q-threshold)%(36-threshold)
                        guard try append(UInt8(digit < 26 ? digit+97 : digit+22),meter: &meter) else { return nil }
                        q = (q-threshold)/(36-threshold); k += 36
                    }
                    guard try append(UInt8(q < 26 ? q+97 : q+22),meter: &meter),
                          let next = try adapt(delta,points: UInt64(handled)+1,first: handled == basic,meter: &meter) else { return nil }
                    bias = next; delta = 0; handled += 1
                }
            }
            let (next,overflow) = delta.addingReportingOverflow(1); guard !overflow else { return nil }; delta = next; n += 1
        }
        return output
    }
}
