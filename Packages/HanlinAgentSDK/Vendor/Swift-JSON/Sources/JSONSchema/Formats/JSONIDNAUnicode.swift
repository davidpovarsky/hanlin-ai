// SPDX-License-Identifier: Apache-2.0
import JSON

package enum JSONIDNAUnicode {
    package static func properties(_ cp: UInt32, meter: inout JSONWorkMeter) throws -> UInt32 {
        let table = JSONIDNAData.properties
        var low = 0, high = table.count/3
        while low < high {
            try meter.work(); let middle = low+(high-low)/2, i = middle*3
            if cp < table[i] { high = middle }
            else if cp > table[i+1] { low = middle+1 }
            else { return table[i+2] }
        }
        return 0
    }
    private static func ccc(_ cp: UInt32, meter: inout JSONWorkMeter) throws -> UInt32 { try properties(cp,meter: &meter) >> 8 & 255 }
    private static func decomposition(_ cp: UInt32, meter: inout JSONWorkMeter) throws -> Range<Int>? {
        let table = JSONIDNAData.decompositionIndex
        var low = 0, high = table.count/3
        while low < high {
            try meter.work(); let middle = low+(high-low)/2, i = middle*3
            if cp < table[i] { high = middle }
            else if cp > table[i] { low = middle+1 }
            else { return Int(table[i+1])..<Int(table[i+1]+table[i+2]) }
        }
        return nil
    }
    private static func compose(_ a: UInt32, _ b: UInt32, meter: inout JSONWorkMeter) throws -> UInt32? {
        try meter.work()
        if (0x1100...0x1112).contains(a), (0x1161...0x1175).contains(b) { return 0xAC00+(a-0x1100)*588+(b-0x1161)*28 }
        if (0xAC00...0xD7A3).contains(a), (a-0xAC00)%28 == 0, (0x11A8...0x11C2).contains(b) { return a+b-0x11A7 }
        let key = UInt64(a)<<21 | UInt64(b), table = JSONIDNAData.composition
        var low = 0, high = table.count
        while low < high {
            try meter.work(); let middle = low+(high-low)/2, candidate = table[middle] >> 21
            if key < candidate { high = middle }
            else if key > candidate { low = middle+1 }
            else { return UInt32(table[middle] & 0x1FFFFF) }
        }
        return nil
    }
    package static func normalize(_ input: [UInt32], meter: inout JSONWorkMeter) throws -> [UInt32] {
        var ordered: [UInt32] = [], result: [UInt32] = []
        func append(_ cp: UInt32, meter: inout JSONWorkMeter) throws {
            try meter.work(); try meter.retain(8); ordered.append(cp)
            let order = try ccc(cp,meter: &meter)
            var position = ordered.count-1
            if order != 0 {
                while position > 0 {
                    try meter.work(); guard try ccc(ordered[position-1],meter: &meter) > order else { break }
                    ordered[position] = ordered[position-1]; position -= 1
                }
                ordered[position] = cp
            }
        }
        for cp in input {
            try meter.work()
            if (0xAC00...0xD7A3).contains(cp) {
                let n = cp-0xAC00
                try append(0x1100+n/588,meter: &meter); try append(0x1161+(n%588)/28,meter: &meter)
                if n%28 != 0 { try append(0x11A7+n%28,meter: &meter) }
            } else if let range = try decomposition(cp,meter: &meter) {
                for i in range { try meter.work(); try append(JSONIDNAData.decompositionScalars[i],meter: &meter) }
            } else { try append(cp,meter: &meter) }
        }
        var starter: Int?, last: UInt32 = 0
        for cp in ordered {
            let order = try ccc(cp,meter: &meter)
            let composed = try starter.flatMap { position in last < order || last == 0 ? try compose(result[position],cp,meter: &meter) : nil }
            if let composed, let starter { result[starter] = composed }
            else {
                if order == 0 { starter = result.count }
                try meter.retain(8); result.append(cp); last = order
            }
        }
        try meter.release(UInt64(ordered.count)*8); return result
    }
    package static func isNFC(_ input: [UInt32], meter: inout JSONWorkMeter) throws -> Bool {
        let result = try normalize(input,meter: &meter)
        var equal = input.count == result.count
        if equal { for i in input.indices { try meter.work(); if input[i] != result[i] { equal = false; break } } }
        try meter.release(UInt64(result.count)*8); return equal
    }
}
