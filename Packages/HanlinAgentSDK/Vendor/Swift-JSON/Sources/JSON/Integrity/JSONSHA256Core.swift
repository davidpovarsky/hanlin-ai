// SPDX-License-Identifier: Apache-2.0
// Original implementation of FIPS 180-4 SHA-256. No cryptography API is exported.
// This file is mirrored byte-for-byte by the trusted qualification executable;
// Scripts/public_check.py checks that mirror. Production uses JSONWorkMeter.
package protocol JSONHashAccounting: ~Copyable {
    mutating func hashWork(_ amount: UInt64) throws
    mutating func hashRetain(_ bytes: UInt64) throws
    mutating func hashRelease(_ bytes: UInt64) throws
    mutating func hashInput(_ bytes: UInt64) throws
}
package enum JSONHashFailure: Error { case lengthOverflow }

package enum JSONSHA256Core {
    // Fixed immutable standard constants, shared like the pinned Unicode tables.
    private static let constants: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
    ]
    private static func rotate(_ value: UInt32, by count: Int) -> UInt32 {
        (value >> count) | (value << (32 - count))
    }
    private static func compress<B: JSONHashAccounting & ~Copyable>(
        _ words: inout [UInt32], state: inout [UInt32], accounting: inout B
    ) throws {
        for i in 16..<64 {
            // Conservative primitive blocks include shifts, accesses and arithmetic.
            // Each block is <=64 units; the production meter checks cancellation.
            try accounting.hashWork(64)
            let x = words[i - 15], y = words[i - 2]
            let s0 = rotate(x, by: 7) ^ rotate(x, by: 18) ^ (x >> 3)
            let s1 = rotate(y, by: 17) ^ rotate(y, by: 19) ^ (y >> 10)
            // Wrapping UInt32 addition is required by SHA-256, never resource math.
            words[i] = words[i - 16] &+ s0 &+ words[i - 7] &+ s1
        }
        try accounting.hashWork(8)
        var a = state[0], b = state[1], c = state[2], d = state[3]
        var e = state[4], f = state[5], g = state[6], h = state[7]
        for i in 0..<64 {
            try accounting.hashWork(64)
            let s1 = rotate(e, by: 6) ^ rotate(e, by: 11) ^ rotate(e, by: 25)
            let choice = (e & f) ^ (~e & g)
            let t1 = h &+ s1 &+ choice &+ constants[i] &+ words[i]
            let s0 = rotate(a, by: 2) ^ rotate(a, by: 13) ^ rotate(a, by: 22)
            let majority = (a & b) ^ (a & c) ^ (b & c)
            let t2 = s0 &+ majority
            h = g; g = f; f = e; e = d &+ t1
            d = c; c = b; b = a; a = t1 &+ t2
        }
        try accounting.hashWork(32)
        state[0] = state[0] &+ a; state[1] = state[1] &+ b
        state[2] = state[2] &+ c; state[3] = state[3] &+ d
        state[4] = state[4] &+ e; state[5] = state[5] &+ f
        state[6] = state[6] &+ g; state[7] = state[7] &+ h
    }
    /// Returns 64 lowercase ASCII hex bytes, retaining that output in the caller's
    /// ledger. Scratch is released on success, rejection or cancellation.
    package static func hexadecimal<C: Collection, B: JSONHashAccounting & ~Copyable>(
        _ bytes: C, accounting: inout B
    ) throws -> String where C.Element == UInt8 {
        // 8 state words + 64 schedule words + 8 compression words + a fixed frame.
        let scratch: UInt64 = 336
        try accounting.hashRetain(scratch)
        defer { try? accounting.hashRelease(scratch) }
        try accounting.hashWork(72)
        var state: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                               0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
        var words = Array(repeating: UInt32(0), count: 64)
        var used = 0, length: UInt64 = 0
        for byte in bytes {
            guard length < UInt64.max / 8 else { throw JSONHashFailure.lengthOverflow }
            length += 1
            try accounting.hashInput(length); try accounting.hashWork(8)
            words[used / 4] |= UInt32(byte) << (24 - (used % 4) * 8)
            used += 1
            if used == 64 {
                try compress(&words, state: &state, accounting: &accounting)
                for i in 0..<16 { try accounting.hashWork(2); words[i] = 0 }
                used = 0
            }
        }
        try accounting.hashWork(8)
        words[used / 4] |= UInt32(0x80) << (24 - (used % 4) * 8)
        if used >= 56 {
            try compress(&words, state: &state, accounting: &accounting)
            for i in 0..<16 { try accounting.hashWork(2); words[i] = 0 }
        }
        try accounting.hashWork(8)
        let bits = length * 8 // Length was checked before increment, no overflow.
        words[14] = UInt32(bits >> 32); words[15] = UInt32(truncatingIfNeeded: bits)
        try compress(&words, state: &state, accounting: &accounting)
        try accounting.hashRetain(128) // Hex buffer and result are simultaneously live.
        var releaseOutput = true
        defer { if releaseOutput { try? accounting.hashRelease(128) } }
        var output: [UInt8] = []; output.reserveCapacity(64)
        for word in state {
            for shift in stride(from: 28, through: 0, by: -4) {
                try accounting.hashWork(4)
                let nibble = UInt8((word >> shift) & 15)
                output.append(nibble < 10 ? nibble + 48 : nibble + 87)
            }
        }
        try accounting.hashWork(64)
        let result = String(decoding: output, as: UTF8.self)
        try accounting.hashRelease(64); releaseOutput = false
        return result
    }
}
