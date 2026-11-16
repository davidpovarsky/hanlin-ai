// SPDX-License-Identifier: Apache-2.0

/// Package-only preparation strategy; ordinary Copyable state cannot own the capability.
package protocol JSONReadPreparation {
    mutating func prepare(context: inout JSONReadPreparationContext) throws
}

/// Exclusive profile-only capability on the original read ledger, before admission.
/// No source, cursor, state, meter or nonmutating bound operation can leave this type.
package struct JSONReadPreparationContext: ~Copyable {
    private let scope: JSONReadScope
    internal init(scope: JSONReadScope) { self.scope = scope }

    package mutating func work(_ units: UInt64 = 1) throws {
        try scope.runPreparation { try $0.meter.work(units) }
    }
    package mutating func retain(_ bytes: UInt64) throws {
        try scope.runPreparation { try $0.meter.retain(bytes) }
    }
    package mutating func release(_ bytes: UInt64) throws {
        try scope.runPreparation { try $0.meter.release(bytes) }
    }
    package mutating func checkpoint() throws {
        try scope.runPreparation { try $0.meter.checkpoint() }
    }
    package mutating func admitText(_ text: String, key: Bool = false) throws {
        try scope.runPreparation { try JSONAdmission.text(text, key: key, meter: &$0.meter, owned: true) }
    }
    package mutating func equalStrings(_ lhs: String, _ rhs: String) throws -> Bool {
        try scope.runPreparation { try JSONComparison.textEquals(lhs, rhs, meter: &$0.meter) }
    }
    package mutating func recordFailure(_ error: any Error) throws {
        try scope.runPreparation { $0.meter.recordFailure(error); try $0.meter.checkpoint() }
    }
}
