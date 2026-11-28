// SPDX-License-Identifier: Apache-2.0
/// Invocation-owned while building; immutable after publication. Fingerprints
/// only select candidates. Every hit confirms the complete decoded UTF-8 key.
package struct JSONExactKeyIndex: Sendable {
    private struct Entry: Sendable { let key: JSONKey; let position: Int }
    private var linear: [Entry] = []
    private var table: [Entry?] = []
    private var capacity = 0
    private var count = 0
    private let fingerprintMask: UInt64
    package init(fingerprintMask: UInt64 = .max) { self.fingerprintMask = fingerprintMask }
    package var retainedBytes: UInt64 { UInt64(capacity) * JSONLogicalWeights.indexSlot }
    private func same(_ a: JSONKey, _ b: JSONKey, meter: inout JSONWorkMeter) throws -> Bool {
        try meter.work()
        guard a.fingerprint & fingerprintMask == b.fingerprint & fingerprintMask else { return false }
        return try JSONComparison.textEquals(a.string, b.string, meter: &meter)
    }
    private func slot(_ key: JSONKey, in slots: [Entry?], meter: inout JSONWorkMeter) throws -> (Int, Int?) {
        var index = Int(key.fingerprint & fingerprintMask & UInt64(slots.count - 1))
        for _ in slots.indices {
            try meter.work()
            guard let entry = slots[index] else { return (index, nil) }
            if try same(entry.key, key, meter: &meter) { return (index, entry.position) }
            index = (index + 1) & (slots.count - 1)
        }
        throw JSONFailure(.configuration, code: .invalidOperation)
    }
    package func find(_ key: JSONKey, meter: inout JSONWorkMeter) throws -> Int? {
        if !table.isEmpty { return try slot(key, in: table, meter: &meter).1 }
        for entry in linear {
            if try same(entry.key, key, meter: &meter) { return entry.position }
        }
        return nil
    }
    package func find(_ key: JSONKey) -> Int? {
        if table.isEmpty { return linear.first { $0.key == key }?.position }
        var index = Int(key.fingerprint & fingerprintMask & UInt64(table.count - 1))
        for _ in table.indices {
            guard let entry = table[index] else { return nil }
            if entry.key == key { return entry.position }
            index = (index + 1) & (table.count - 1)
        }
        return nil
    }
    private func bytes(_ slots: Int, meter: inout JSONWorkMeter) throws -> UInt64 {
        let (bytes, overflow) = UInt64(slots).multipliedReportingOverflow(by: JSONLogicalWeights.indexSlot)
        guard !overflow else { throw JSONFailure(.resource, code: .counterOverflow) }
        try meter.require(.retainedBytes, bytes)
        return bytes
    }
    /// No mutation occurs until all throwing probes, growth/copies and charges
    /// complete. A rejected append therefore preserves valid prior metadata.
    package mutating func insert(_ key: JSONKey, position: Int, meter: inout JSONWorkMeter) throws -> Bool {
        if try find(key, meter: &meter) != nil { return false }
        try meter.require(.objectMembers, UInt64(count) + 1)
        let entry = Entry(key: key, position: position)
        if count < 31 {
            if count == capacity {
                let next = min(Int(meter.limits[.objectMembers]), max(1, capacity * 2))
                let nextBytes = try bytes(next, meter: &meter)
                try meter.retain(nextBytes)
                // reserveCapacity can copy the old buffer; charge its traversal
                // while both old and replacement capacities are live.
                do { try meter.work(UInt64(count) + 1) }
                catch { try meter.release(nextBytes); throw error }
                linear.reserveCapacity(next)
                try meter.release(retainedBytes)
                capacity = next
            } else { try meter.work() }
            linear.append(entry); count += 1
            return true
        }
        if table.isEmpty || count >= table.count / 2 {
            let (next, overflow) = max(32, table.count).multipliedReportingOverflow(by: 2)
            guard !overflow else { throw JSONFailure(.resource, code: .counterOverflow) }
            let nextBytes = try bytes(next, meter: &meter)
            try meter.retain(nextBytes)
            var replacement: [Entry?] = []
            replacement.reserveCapacity(next)
            do {
                for _ in 0..<next { try meter.work(); replacement.append(nil) }
                if table.isEmpty {
                    for previous in linear {
                        let index = try slot(previous.key, in: replacement, meter: &meter).0
                        try meter.work(); replacement[index] = previous
                    }
                } else {
                    for previous in table {
                        try meter.work()
                        if let previous {
                            let index = try slot(previous.key, in: replacement, meter: &meter).0
                            try meter.work(); replacement[index] = previous
                        }
                    }
                }
                let index = try slot(key, in: replacement, meter: &meter).0
                try meter.work(); replacement[index] = entry
            } catch {
                try meter.release(nextBytes)
                throw error
            }
            try meter.release(retainedBytes)
            table = replacement; linear = []; capacity = next
        } else {
            let index = try slot(key, in: table, meter: &meter).0
            try meter.work(); table[index] = entry
        }
        count += 1
        return true
    }
}
