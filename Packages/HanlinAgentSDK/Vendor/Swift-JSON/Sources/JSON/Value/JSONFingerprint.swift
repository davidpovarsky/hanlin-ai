// SPDX-License-Identifier: Apache-2.0
/// A metered collision-prone accelerator, never an equality verdict or cryptographic digest.
package enum JSONFingerprint {
    private enum Step { case value(JSON), array(Int), object([UInt64]) }
    private static func mix(_ hash: UInt64, _ value: UInt64) -> UInt64 { (hash ^ value) &* 1099511628211 }
    package static func compute(_ value: JSON, meter: inout JSONWorkMeter) throws -> UInt64 {
        var pending: [Step] = [.value(value)]
        var results: [UInt64] = []
        try meter.retain(JSONLogicalWeights.frame)
        while let step = pending.popLast() {
            try meter.release(JSONLogicalWeights.frame); try meter.work()
            var result: UInt64 = 14695981039346656037
            switch step {
            case .value(let value):
                switch value {
                case .null: result = mix(result, 0)
                case .boolean(let v): result = mix(mix(result, 1), v ? 1 : 0)
                case .number(let number):
                    let c = number.components
                    result = mix(mix(result, 2), c.negative ? 1 : 0)
                    result = mix(result, UInt64(bitPattern: c.exponent))
                    for digit in c.digits { try meter.work(subsystem: .numericWorkUnits); result = mix(result, UInt64(digit)) }
                case .string(let text):
                    result = mix(result, 3)
                    for byte in text.utf8 { try meter.work(); result = mix(result, UInt64(byte)) }
                case .array(let values):
                    try meter.retain(JSONLogicalWeights.frame); pending.append(.array(values.count))
                    for value in values.reversed() { try meter.work(); try meter.retain(JSONLogicalWeights.frame); pending.append(.value(value)) }
                    continue
                case .object(let object):
                    var keys: [UInt64] = []
                    for member in object {
                        var key: UInt64 = 14695981039346656037
                        for byte in member.key.string.utf8 { try meter.work(); key = mix(key, UInt64(byte)) }
                        try meter.retain(8); keys.append(key)
                    }
                    try meter.retain(JSONLogicalWeights.frame); pending.append(.object(keys))
                    for member in object.reversed() { try meter.work(); try meter.retain(JSONLogicalWeights.frame); pending.append(.value(member.value)) }
                    continue
                }
            case .array(let count):
                result = mix(mix(result, 4), UInt64(count))
                for child in results.suffix(count) { try meter.work(); result = mix(result, child) }
                results.removeLast(count); try meter.release(UInt64(count) * 8)
            case .object(let keys):
                var unordered: UInt64 = 0
                for (key, child) in zip(keys, results.suffix(keys.count)) { try meter.work(); unordered &+= mix(key, child) }
                result = mix(mix(mix(result, 5), UInt64(keys.count)), unordered)
                results.removeLast(keys.count); try meter.release(UInt64(keys.count) * 16)
            }
            try meter.retain(8); results.append(result)
        }
        let result = results[0]; try meter.release(8); return result
    }
}
