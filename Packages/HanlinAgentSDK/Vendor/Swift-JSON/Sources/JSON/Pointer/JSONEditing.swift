// SPDX-License-Identifier: Apache-2.0
package enum JSONEditing {
    package enum Change { case add(JSON), replace(JSON), remove }
    /// Rebuild a path using explicit ancestor frames; no implicit parent creation.
    package static func edit(_ value: JSON, at pointer: JSONPointer, change: Change, meter: inout JSONWorkMeter) throws -> JSON? {
        if pointer.tokens.isEmpty {
            switch change { case .add(let v), .replace(let v): return v; case .remove: return nil }
        }
        var current = value, ancestors: [(JSON, JSONKey)] = []
        for token in pointer.tokens.dropLast() {
            try meter.work(); try meter.retain(JSONLogicalWeights.frame)
            ancestors.append((current, token))
            switch current {
            case .object(let object):
                guard let child = try object.lookup(token.string, meter: &meter) else { throw JSONFailure(.pointer, code: .missingTarget) }; current = child
            case .array(let array): current = array[try JSONPointer.arrayIndex(token.string, count: array.count, allowEnd: false, meter: &meter)]
            default: throw JSONFailure(.typeMismatch, code: .wrongKind)
            }
        }
        var result = try modify(current, token: pointer.tokens.last!, change: change, meter: &meter)
        while let (ancestor, token) = ancestors.popLast() {
            try meter.release(JSONLogicalWeights.frame)
            result = try modify(ancestor, token: token, change: .replace(result), meter: &meter)
        }
        return result
    }
    package static func modify(_ value: JSON, token: JSONKey, change: Change, meter: inout JSONWorkMeter) throws -> JSON {
        try meter.work()
        switch value {
        case .object(let object):
            var members: [JSONMember] = [], found = false
            for member in object {
                try meter.work()
                if try JSONComparison.textEquals(member.key.string, token.string, meter: &meter) {
                    found = true
                    switch change {
                    case .remove: continue
                    case .add(let value), .replace(let value):
                        try meter.retain(JSONLogicalWeights.member); members.append(JSONMember(member.key, value: value)); continue
                    }
                }
                try meter.retain(JSONLogicalWeights.member); members.append(member)
            }
            if !found {
                guard case .add(let value) = change else { throw JSONFailure(.pointer, code: .missingTarget) }
                try meter.require(.objectMembers, UInt64(members.count) + 1)
                try meter.retain(JSONLogicalWeights.member); members.append(JSONMember(token, value: value))
            }
            return .object(try JSONObject.indexed(admitted: members, meter: &meter))
        case .array(let array):
            let add: Bool
            if case .add = change { add = true } else { add = false }
            let index = try JSONPointer.arrayIndex(token.string, count: array.count, allowEnd: add, meter: &meter)
            if add { try meter.require(.arrayItems, UInt64(array.count) + 1) }
            var values: [JSON] = []
            for offset in 0...array.count {
                try meter.work()
                if offset == index {
                    switch change {
                    case .add(let value): try meter.retain(JSONLogicalWeights.arraySlot); values.append(value)
                    case .replace(let value): try meter.retain(JSONLogicalWeights.arraySlot); values.append(value); continue
                    case .remove: continue
                    }
                }
                if offset < array.count { try meter.retain(JSONLogicalWeights.arraySlot); values.append(array[offset]) }
            }
            return .array(values)
        default: throw JSONFailure(.typeMismatch, code: .wrongKind)
        }
    }
}
