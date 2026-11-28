// SPDX-License-Identifier: Apache-2.0
extension JSONWorkMeter: JSONHashAccounting {
    package mutating func hashWork(_ amount: UInt64) throws {
        var remaining = amount
        while remaining != 0 {
            let next = min(remaining, limits[.cancellationQuantum])
            // Work can arrive after earlier parser/loader charges. Check before
            // each block rather than assuming the meter's prior quantum is empty.
            try checkpoint(); try work(next); remaining -= next
        }
    }
    package mutating func hashRetain(_ bytes: UInt64) throws { try retain(bytes) }
    package mutating func hashRelease(_ bytes: UInt64) throws { try release(bytes) }
    package mutating func hashInput(_ bytes: UInt64) throws { try require(.inputBytes, bytes) }
}
