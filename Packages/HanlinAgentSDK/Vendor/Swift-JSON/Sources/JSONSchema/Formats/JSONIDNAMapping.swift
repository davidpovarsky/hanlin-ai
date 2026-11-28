// SPDX-License-Identifier: Apache-2.0
import JSON

package enum JSONIDNAMapping {
    package static func apply(_ bytes: ArraySlice<UInt8>, meter: inout JSONWorkMeter) throws -> [UInt8]? {
        let before = meter.used(.retainedBytes)
        try meter.retain(UInt64(bytes.count)); let text = String(decoding: bytes,as: UTF8.self)
        var points: [UInt32] = [], payload: UInt64 = 0
        func append(_ cp: UInt32, meter: inout JSONWorkMeter) throws {
            try meter.work(); payload = try meter.adding(.stringBytes,payload,cp < 0x80 ? 1 : (cp < 0x800 ? 2 : (cp < 0x10000 ? 3 : 4)))
            try meter.retain(8); points.append(cp)
        }
        let table = JSONIDNAData.mappingIndex
        for scalar in text.unicodeScalars {
            let cp = scalar.value; var low = 0, high = table.count/5, row: Int?
            while low < high {
                try meter.work(); let middle = low+(high-low)/2, i = middle*5
                if cp < table[i] { high = middle }
                else if cp > table[i+1] { low = middle+1 }
                else { row = i; break }
            }
            guard let row else { return nil }
            switch table[row+2] {
            case 1: try append(cp,meter: &meter)
            case 2:
                let start = Int(table[row+3]), count = Int(table[row+4])
                for i in start..<start+count { try meter.work(); try append(JSONIDNAData.mappingScalars[i],meter: &meter) }
            case 3: break
            default: return nil
            }
        }
        let normalized = try JSONIDNAUnicode.normalize(points,meter: &meter)
        var output: [UInt8] = []
        func byte(_ b: UInt8, meter: inout JSONWorkMeter) throws {
            try meter.work(); try meter.require(.stringBytes,UInt64(output.count)+1); try meter.retain(1); output.append(b)
        }
        for cp in normalized {
            try meter.work()
            if cp < 0x80 { try byte(UInt8(cp),meter: &meter) }
            else if cp < 0x800 { try byte(UInt8(0xC0 | cp>>6),meter: &meter); try byte(UInt8(0x80 | cp&63),meter: &meter) }
            else if cp < 0x10000 { try byte(UInt8(0xE0 | cp>>12),meter: &meter); try byte(UInt8(0x80 | cp>>6&63),meter: &meter); try byte(UInt8(0x80 | cp&63),meter: &meter) }
            else { try byte(UInt8(0xF0 | cp>>18),meter: &meter); try byte(UInt8(0x80 | cp>>12&63),meter: &meter); try byte(UInt8(0x80 | cp>>6&63),meter: &meter); try byte(UInt8(0x80 | cp&63),meter: &meter) }
        }
        try meter.release(meter.used(.retainedBytes)-before-UInt64(output.count)); return output
    }
}
