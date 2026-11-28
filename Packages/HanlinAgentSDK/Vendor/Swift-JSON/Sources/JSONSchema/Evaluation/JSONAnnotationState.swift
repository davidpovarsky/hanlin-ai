// SPDX-License-Identifier: Apache-2.0
import JSON

/// Evaluated locations are exact sets. Mutable state belongs to one evaluation frame.
package struct JSONAnnotationState {
    package private(set) var keys: [JSONKey] = []
    package private(set) var items: [Int] = []
    private var bytes: UInt64 = 0
    package func contains(_ key: JSONKey, meter: inout JSONWorkMeter) throws -> Bool {
        for existing in keys { if try JSONComparison.textEquals(existing.string, key.string, meter: &meter) { return true } }
        return false
    }
    package func contains(_ index: Int, meter: inout JSONWorkMeter) throws -> Bool {
        for existing in items { try meter.work(); if index == existing { return true } }
        return false
    }
    package mutating func insert(_ key: JSONKey, meter: inout JSONWorkMeter) throws {
        if try contains(key, meter: &meter) { return }
        var size = JSONLogicalWeights.annotationEntry
        for _ in key.string.utf8 { try meter.work(); size += 1 }
        try meter.charge(.annotationEntries); try meter.charge(.annotationBytes, size); try meter.retain(size)
        bytes += size; keys.append(key)
    }
    package mutating func insert(_ index: Int, meter: inout JSONWorkMeter) throws {
        if try contains(index, meter: &meter) { return }
        try meter.charge(.annotationEntries); try meter.charge(.annotationBytes, JSONLogicalWeights.annotationEntry)
        try meter.retain(JSONLogicalWeights.annotationEntry); bytes += JSONLogicalWeights.annotationEntry; items.append(index)
    }
    package mutating func merge(_ other: Self, meter: inout JSONWorkMeter) throws {
        for key in other.keys { try meter.work(); try insert(key, meter: &meter) }
        for item in other.items { try meter.work(); try insert(item, meter: &meter) }
    }
    package mutating func release(meter: inout JSONWorkMeter) throws {
        try meter.release(bytes); try meter.releaseAnnotationState(bytes)
        keys = []; items = []; bytes = 0
    }
}
