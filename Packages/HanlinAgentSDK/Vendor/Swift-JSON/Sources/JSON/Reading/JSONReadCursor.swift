// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Synchronous typed access to one admitted immutable root under a shared budget.
///
/// A cursor is deliberately not Sendable. Escaped handles become unusable when
/// their read scope exits; they retain no selected value or source snapshot.
/// Ordinary failures carry JSONAccessFailure's complete typed path. Resource
/// failure and cancellation are terminal even if caught inside the callback.
public struct JSONReadCursor {
    private let scope: JSONReadScope
    private let selection: JSONReadPath
    private var path: [JSONLocationComponent] { selection.components }
    package init(scope: JSONReadScope, selection: JSONReadPath) { self.scope = scope; self.selection = selection }
    /// Requires an exactly matching object member; keys are literal decoded scalars.
    /// - Parameter key: The member name; empty, slash, tilde and dotted keys are literal.
    /// - Throws: Bounded access failure, resource/configuration failure or cancellation.
    public subscript(_ key: String) -> Self {
        get throws {
            try scope.run(path) { state in
                try JSONAdmission.text(key, key: true, meter: &state.meter)
                return try child(.key(JSONKey(key, meter: &state.meter)), state: state)
            }
        }
    }
    /// Requires an exactly matching object member using an existing scalar key.
    /// - Parameter key: The exact member key, without canonical normalization.
    /// - Throws: Bounded access failure, resource/configuration failure or cancellation.
    public subscript(_ key: JSONKey) -> Self {
        get throws {
            try scope.run(path) { state in
                try JSONAdmission.text(key.string, key: true, meter: &state.meter)
                return try child(.key(key), state: state)
            }
        }
    }
    /// Requires an array and a nonnegative in-range element; numeric keys stay keys.
    /// - Parameter index: The zero-based element index, without negative indexing.
    /// - Throws: Bounded access failure, resource/configuration failure or cancellation.
    public subscript(_ index: Int) -> Self {
        get throws { try scope.run(path) { try child(.index(index), state: $0) } }
    }
    private func child(_ part: JSONLocationComponent, state: JSONCodingState) throws -> Self {
        let attempted = try scope.append(part, to: path, state: state)
        return try scope.run(attempted.components) { state in
            _ = try scope.select(attempted.components, state: state)
            return Self(scope: scope, selection: attempted)
        }
    }
    private func selected<T>(_ body: (JSON, JSONCodingState) throws -> T) throws -> T {
        try scope.run(path) { state in try body(scope.select(path, state: state), state) }
    }
    /// Returns the selected value, including JSON null, without coercion.
    /// Subsequent caller collection operations retain their ordinary accounting contracts.
    /// - Throws: Bounded access failure, resource/configuration failure or cancellation.
    public func requiredValue() throws -> JSON { try selected { value, state in try state.meter.work(); return value } }
    /// Requires a JSON string and admits its returned text under the active meter.
    /// - Throws: Wrong-kind access failure, resource/configuration failure or cancellation.
    public func requiredString() throws -> String {
        try selected { value, state in
            guard case .string(let text) = value else { throw JSONFailure(.typeMismatch, code: .wrongKind) }
            let before = state.meter.used(.retainedBytes)
            try JSONAdmission.text(text, meter: &state.meter, owned: true)
            try state.meter.release(state.meter.used(.retainedBytes) - before)
            return text
        }
    }
    /// Requires a JSON Boolean; numbers and strings are not coerced.
    /// - Throws: Wrong-kind access failure, resource/configuration failure or cancellation.
    public func requiredBoolean() throws -> Bool {
        try selected { value, _ in
            guard case .boolean(let result) = value else { throw JSONFailure(.typeMismatch, code: .wrongKind) }; return result
        }
    }
    /// Requires an exact JSON number, retaining its admitted original lexeme.
    /// - Throws: Wrong-kind access failure, resource/configuration failure or cancellation.
    public func requiredNumber() throws -> JSONNumber {
        try selected { value, _ in
            guard case .number(let result) = value else { throw JSONFailure(.typeMismatch, code: .wrongKind) }; return result
        }
    }
    /// Requires an ordered exact-key object; later direct lookup is caller work.
    /// - Throws: Wrong-kind access failure, resource/configuration failure or cancellation.
    public func requiredObject() throws -> JSONObject {
        try selected { value, _ in
            guard case .object(let result) = value else { throw JSONFailure(.typeMismatch, code: .wrongKind) }; return result
        }
    }
    /// Requires an array; later direct collection traversal is caller work.
    /// - Throws: Wrong-kind access failure, resource/configuration failure or cancellation.
    public func requiredArray() throws -> [JSON] {
        try selected { value, _ in
            guard case .array(let result) = value else { throw JSONFailure(.typeMismatch, code: .wrongKind) }; return result
        }
    }
    /// Requires an integral exact number within the target's signed/unsigned range.
    /// - Parameter type: The requested fixed-width integer type.
    /// - Throws: Kind/conversion access failure, resource/configuration failure or cancellation.
    public func requiredInteger<T: FixedWidthInteger>(as type: T.Type) throws -> T {
        try selected { value, state in
            guard case .number(let number) = value else { throw JSONFailure(.typeMismatch, code: .wrongKind) }
            return try number.integer(as: type, meter: &state.meter)
        }
    }
    /// Projects an exact number to a finite Double with an explicit fidelity choice.
    /// Decimal 0.1 rejects `.exact`; `.rounded` permits finite approximation.
    /// - Parameter policy: Mathematical equality or explicitly permitted finite rounding.
    /// - Throws: Kind/conversion access failure, resource/configuration failure or cancellation.
    public func requiredDouble(policy: JSONNumberConversionPolicy) throws -> Double {
        try selected { value, state in
            guard case .number(let number) = value else { throw JSONFailure(.typeMismatch, code: .wrongKind) }
            let before = state.meter.used(.retainedBytes)
            do {
                let result = try number.doubleValue(policy: policy, meter: &state.meter)
                try state.meter.release(state.meter.used(.retainedBytes) - before); return result
            } catch { try state.meter.release(state.meter.used(.retainedBytes) - before); throw error }
        }
    }
    /// Projects an exact number to finite Decimal with an explicit fidelity choice.
    /// - Parameter policy: Mathematical equality or explicitly permitted finite rounding.
    /// - Throws: Kind/conversion access failure, resource/configuration failure or cancellation.
    public func requiredDecimal(policy: JSONNumberConversionPolicy) throws -> Decimal {
        try selected { value, state in
            guard case .number(let number) = value else { throw JSONFailure(.typeMismatch, code: .wrongKind) }
            let before = state.meter.used(.retainedBytes)
            do {
                let result = try number.decimalValue(policy: policy, meter: &state.meter)
                try state.meter.release(state.meter.used(.retainedBytes) - before); return result
            } catch { try state.meter.release(state.meter.used(.retainedBytes) - before); throw error }
        }
    }
    private func field<T>(_ key: JSONKey, _ body: (JSON, JSONCodingState) throws -> T) throws -> JSONPresence<T> {
        try scope.run(path) { state in
            try JSONAdmission.text(key.string, key: true, meter: &state.meter)
            let attempted = try scope.append(.key(key), to: path, state: state)
            return try scope.run(attempted.components) { state in
                guard case .object(let object) = try scope.select(path, state: state) else { throw JSONFailure(.typeMismatch, code: .wrongKind) }
                guard let value = try object.lookup(key.string, meter: &state.meter) else { return .absent }
                if value.isNull { return .null }
                return .value(try body(value, state))
            }
        }
    }
    private func admitted<T>(_ key: String, _ body: (JSONKey) throws -> JSONPresence<T>) throws -> JSONPresence<T> {
        try scope.run(path) { state in
            try JSONAdmission.text(key, key: true, meter: &state.meter)
            return try body(JSONKey(key, meter: &state.meter))
        }
    }
    /// Distinguishes absence, explicit null and an existing member's exact value.
    /// - Parameter key: The exact decoded-scalar member key.
    /// - Throws: Kind/access failure, resource/configuration failure or cancellation.
    public func presence(of key: JSONKey) throws -> JSONPresence<JSON> { try field(key) { value, state in try state.meter.work(); return value } }
    /// Distinguishes absence, explicit null and an existing member's exact value.
    /// - Parameter key: The literal decoded-scalar member name.
    /// - Throws: Kind/access failure, resource/configuration failure or cancellation.
    public func presence(of key: String) throws -> JSONPresence<JSON> { try admitted(key) { try presence(of: $0) } }

    /// Distinguishes absence and null while requiring a non-null JSON string.
    /// - Parameter key: The exact decoded-scalar member key.
    /// - Throws: Kind/access failure, resource/configuration failure or cancellation.
    public func stringPresence(of key: JSONKey) throws -> JSONPresence<String> {
        try field(key) { value, state in
            guard case .string(let result) = value else { throw JSONFailure(.typeMismatch, code: .wrongKind) }
            let before = state.meter.used(.retainedBytes)
            try JSONAdmission.text(result, meter: &state.meter, owned: true)
            try state.meter.release(state.meter.used(.retainedBytes) - before)
            return result
        }
    }
    /// Distinguishes absence and null while requiring a non-null JSON string.
    /// - Parameter key: The literal decoded-scalar member name.
    /// - Throws: Kind/access failure, resource/configuration failure or cancellation.
    public func stringPresence(of key: String) throws -> JSONPresence<String> { try admitted(key) { try stringPresence(of: $0) } }

    /// Distinguishes absence and null while requiring a non-null JSON boolean.
    /// - Parameter key: The exact decoded-scalar member key.
    /// - Throws: Kind/access failure, resource/configuration failure or cancellation.
    public func booleanPresence(of key: JSONKey) throws -> JSONPresence<Bool> {
        try field(key) { value, state in
            guard case .boolean(let result) = value else { throw JSONFailure(.typeMismatch, code: .wrongKind) }
            try state.meter.work()
            return result
        }
    }
    /// Distinguishes absence and null while requiring a non-null JSON boolean.
    /// - Parameter key: The literal decoded-scalar member name.
    /// - Throws: Kind/access failure, resource/configuration failure or cancellation.
    public func booleanPresence(of key: String) throws -> JSONPresence<Bool> { try admitted(key) { try booleanPresence(of: $0) } }

    /// Distinguishes absence and null while requiring a non-null JSON number.
    /// - Parameter key: The exact decoded-scalar member key.
    /// - Throws: Kind/access failure, resource/configuration failure or cancellation.
    public func numberPresence(of key: JSONKey) throws -> JSONPresence<JSONNumber> {
        try field(key) { value, state in
            guard case .number(let result) = value else { throw JSONFailure(.typeMismatch, code: .wrongKind) }
            try state.meter.work()
            return result
        }
    }
    /// Distinguishes absence and null while requiring a non-null JSON number.
    /// - Parameter key: The literal decoded-scalar member name.
    /// - Throws: Kind/access failure, resource/configuration failure or cancellation.
    public func numberPresence(of key: String) throws -> JSONPresence<JSONNumber> { try admitted(key) { try numberPresence(of: $0) } }
    private func project<T: Decodable>(_ type: T.Type, value: JSON, coding: JSONCodingOptions, state: JSONCodingState) throws -> T {
        let before = state.meter.used(.retainedBytes)
        do {
            let result = try state.withOptions(coding) { try JSONNativeDecoder(value: value, state: state, codingPath: []).decode(type) }
            try state.meter.release(state.meter.used(.retainedBytes) - before)
            return result
        } catch { try state.meter.release(state.meter.used(.retainedBytes) - before); throw error }
    }
    /// Projects the selected value through the existing native decoder and ledger.
    /// Coding ceilings permanently tighten this scope against prior usage. Caller
    /// Decodable computation remains caller work; its errors propagate.
    /// - Parameters:
    ///   - type: The target Decodable model.
    ///   - coding: Native strategies/context and intersected finite limits.
    /// - Throws: Native/caller decoding errors, resource/configuration failure or cancellation.
    public func decode<T: Decodable>(_ type: T.Type, coding: JSONCodingOptions = .init()) throws -> T {
        try selected { value, state in
            try project(type, value: value, coding: coding, state: state)
        }
    }
    /// Decodes an existing non-null member, without calling the model for absence/null.
    /// - Parameters:
    ///   - key: The exact decoded-scalar member key.
    ///   - type: The target Decodable model.
    ///   - coding: Native strategies/context and intersected finite limits.
    /// - Throws: Native/caller decoding errors, resource/configuration failure or cancellation.
    public func presence<T: Decodable>(of key: JSONKey, as type: T.Type, coding: JSONCodingOptions = .init()) throws -> JSONPresence<T> {
        try field(key) { value, state in
            try project(type, value: value, coding: coding, state: state)
        }
    }
    /// Decodes an existing non-null member, without calling the model for absence/null.
    /// - Parameters:
    ///   - key: The literal decoded-scalar member name.
    ///   - type: The target Decodable model.
    ///   - coding: Native strategies/context and intersected finite limits.
    /// - Throws: Native/caller decoding errors, resource/configuration failure or cancellation.
    public func presence<T: Decodable>(of key: String, as type: T.Type, coding: JSONCodingOptions = .init()) throws -> JSONPresence<T> {
        try scope.run(path) { state in
            try JSONAdmission.text(key, key: true, meter: &state.meter)
            return try presence(of: JSONKey(key, meter: &state.meter), as: type, coding: coding)
        }
    }
}

extension JSON {
    /// Runs related typed reads with one root admission and cumulative finite budget.
    /// The synchronous callback receives a non-Sendable, scope-bound cursor.
    /// - Parameters:
    ///   - limits: Inclusive root, path, work, numeric and logical retention ceilings.
    ///   - body: Caller computation; returned payloads retain ordinary value semantics.
    /// - Throws: Access/caller errors, resource/configuration failure or cancellation.
    public func read<Result>(limits: JSONLimits = .balanced, _ body: (JSONReadCursor) throws -> Result) throws -> Result {
        try readWithReport(limits: limits, body).result
    }
    /// Runs related reads and reports all successful owned work in the core domain.
    /// Catching terminal failure in the callback cannot produce a successful report.
    /// - Parameters:
    ///   - limits: Inclusive root, path, work, numeric and logical retention ceilings.
    ///   - body: Synchronous caller computation, outside owned instruction/RSS claims.
    /// - Throws: Access/caller errors, resource/configuration failure or cancellation.
    public func readWithReport<Result>(limits: JSONLimits = .balanced, _ body: (JSONReadCursor) throws -> Result) throws -> JSONOperationReport<Result> {
        try JSONDocument(root: self).readWithReport(limits: limits, body)
    }
}
extension JSONDocument {
    /// Runs related typed reads with optional coherent mapped source diagnostics.
    /// - Parameters:
    ///   - limits: Inclusive root, source, path and cumulative work/retention ceilings.
    ///   - body: Synchronous caller computation using a scope-bound non-Sendable cursor.
    /// - Throws: Access/caller errors, resource/configuration failure or cancellation.
    public func read<Result>(limits: JSONLimits = .balanced, _ body: (JSONReadCursor) throws -> Result) throws -> Result {
        try readWithReport(limits: limits, body).result
    }
    /// Reports successful reads while preserving this document's source coherence.
    /// Scope exit releases library root/source ownership and invalidates escaped handles.
    /// - Parameters:
    ///   - limits: Inclusive root, source, path and cumulative work/retention ceilings.
    ///   - body: Synchronous caller computation, outside owned instruction/RSS claims.
    /// - Throws: Access/caller errors, resource/configuration failure or cancellation.
    public func readWithReport<Result>(limits: JSONLimits = .balanced, _ body: (JSONReadCursor) throws -> Result) throws -> JSONOperationReport<Result> {
        let scope = try JSONReadScope(self, limits: limits)
        defer { scope.invalidate() }
        let root = JSONReadCursor(scope: scope, selection: JSONReadPath(scope: scope, components: [], bytes: 0))
        return try scope.complete(body(root))
    }
}
