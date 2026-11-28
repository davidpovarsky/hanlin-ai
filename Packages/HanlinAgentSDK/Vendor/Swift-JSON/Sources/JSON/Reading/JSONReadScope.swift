// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Guarded synchronous ownership; deliberately not Sendable. An escaped handle
/// stores only a bounded path and this invalidated scope, never a selected DOM.
package final class JSONReadScope {
    private enum Phase { case preparing, admitted, invalidated }
    private var phase = Phase.admitted
    private let owner = ObjectIdentifier(Thread.current)
    package var document: JSONDocument?
    package var state: JSONCodingState?
    private var rootBytes: UInt64 = 0
    private var pathBytes: UInt64 = 0
    private var retiredPathBytes: UInt64 = 0
    private var resultOwnsDocument = false
    package init(_ document: JSONDocument, limits: JSONLimits) throws {
        let state = JSONCodingState(options: .init(limits: limits), meter: try JSONWorkMeter(limits: limits, domain: .core, trackAcceptedCapacities: true))
        try JSONAdmission.value(document.root, meter: &state.meter, owned: true)
        if let source = document.source { try JSONAdmission.text(source, meter: &state.meter, owned: true) }
        if let bytes = document.sourceBytes {
            try state.meter.require(.inputBytes, UInt64(bytes.count))
            for _ in bytes { try state.meter.work(); try state.meter.retain(1) }
        }
        if let map = document.sourceMap {
            for entry in map.entries {
                try state.meter.work(); try state.meter.charge(.sourceMapEntries)
                try state.meter.retain(JSONLogicalWeights.sourceMapEntry)
                for part in entry.path {
                    try state.meter.work(); try state.meter.retain(JSONLogicalWeights.frame)
                    if case .key(let key) = part { try JSONAdmission.text(key.string, key: true, meter: &state.meter, owned: true) }
                }
            }
        }
        self.document = document; self.state = state
        rootBytes = state.meter.used(.retainedBytes)
    }
    /// A prepared entry creates the same native ledger but has no source authority yet.
    package init(preparingWith limits: JSONLimits) throws {
        state = JSONCodingState(options: .init(limits: limits), meter: try JSONWorkMeter(
            limits: limits, domain: .core, trackAcceptedCapacities: true))
        phase = .preparing
    }
    internal func runPreparation<T>(_ body: (JSONCodingState) throws -> T) throws -> T {
        do {
            guard ObjectIdentifier(Thread.current) == owner, phase == .preparing,
                  document == nil, let state else {
                throw JSONFailure(.configuration, code: .invalidOperation)
            }
            try state.check()
            return try body(state)
        } catch {
            state?.meter.recordFailure(error)
            if let state { try state.meter.checkpoint() }
            throw error
        }
    }
    package func prepare<Preparation: JSONReadPreparation>(_ preparation: inout Preparation) throws {
        var context = JSONReadPreparationContext(scope: self)
        do { try preparation.prepare(context: &context); try context.checkpoint() }
        catch {
            state?.meter.recordFailure(error)
            if let state { try state.meter.checkpoint() }
            throw error
        }
    }
    /// Admit once using the prepared ledger. Profile reservations are not input refunds.
    package func admitPrepared(_ source: JSONDocument) throws {
        try runPreparation { state in
            let before = state.meter.used(.retainedBytes)
            try JSONAdmission.value(source.root, meter: &state.meter, owned: true)
            if let label = source.source { try JSONAdmission.text(label, meter: &state.meter, owned: true) }
            if let bytes = source.sourceBytes {
                try state.meter.require(.inputBytes, UInt64(bytes.count))
                for _ in bytes { try state.meter.work(); try state.meter.retain(1) }
            }
            if let map = source.sourceMap {
                for entry in map.entries {
                    try state.meter.work(); try state.meter.charge(.sourceMapEntries)
                    try state.meter.retain(JSONLogicalWeights.sourceMapEntry)
                    for part in entry.path {
                        try state.meter.work(); try state.meter.retain(JSONLogicalWeights.frame)
                        if case .key(let key) = part {
                            try JSONAdmission.text(key.string, key: true, meter: &state.meter, owned: true)
                        }
                    }
                }
            }
            rootBytes = state.meter.used(.retainedBytes) - before
        }
        document = source
        phase = .admitted
    }
    package func retirePath(_ bytes: UInt64) { if ObjectIdentifier(Thread.current) == owner, state != nil { retiredPathBytes += bytes } }
    package func check() throws -> JSONCodingState {
        guard ObjectIdentifier(Thread.current) == owner else { throw JSONFailure(.configuration, code: .invalidOperation) }
        if phase == .preparing {
            let failure = JSONFailure(.configuration, code: .invalidOperation)
            state?.meter.recordFailure(failure)
            throw failure
        }
        guard phase == .admitted, document != nil, let state else { throw JSONFailure(.configuration, code: .invalidOperation) }
        if retiredPathBytes != 0 {
            try state.meter.release(retiredPathBytes); pathBytes -= retiredPathBytes; retiredPathBytes = 0
        }
        try state.check(); return state
    }
    package func invalidate() { phase = .invalidated; document = nil; state = nil }
    /// Transfer the original admitted source alias into a source-attached result.
    /// Only an owned package reducer uses this one-shot completion designation;
    /// ordinary reads/visits retain their original input-refund behavior.
    package func transferDocumentOwnership() throws -> JSONDocument {
        let state = try check()
        try state.meter.work()
        guard !resultOwnsDocument, let document else {
            throw JSONFailure(.configuration, code: .invalidOperation)
        }
        resultOwnsDocument = true
        return document
    }
    package func complete<T>(_ result: T) throws -> JSONOperationReport<T> {
        let state = try check()
        // Paths/root/source cease to be scope-owned. Any escaped path is caller
        // storage and cannot access this invalidated root or ledger.
        try state.meter.release((resultOwnsDocument ? 0 : rootBytes) + pathBytes)
        let statistics = state.meter.statistics()
        invalidate()
        return .init(result: result, statistics: statistics)
    }
    package func run<T>(_ path: [JSONLocationComponent], _ body: (JSONCodingState) throws -> T) throws -> T {
        do { return try body(check()) }
        catch is CancellationError {
            let error = CancellationError(); if state?.failure == nil { state?.failure = error }; throw error
        }
        catch let failure as JSONFailure where failure.category == .resource {
            if state?.failure == nil { state?.failure = failure }; throw failure
        }
        catch let failure as JSONFailure where failure.category == .typeMismatch || failure.category == .missingValue || failure.category == .conversion || failure.code == .invalidIndex {
            guard let state else { throw failure }
            let location = try location(for: path, missing: failure.category == .missingValue, state: state)
            throw JSONAccessFailure(cause: .init(failure.category, code: failure.code, location: location ?? failure.location, resource: failure.resource), path: path)
        }
    }
    private func location(for path: [JSONLocationComponent], missing: Bool, state: JSONCodingState) throws -> JSONSourceLocation? {
        guard let document, let map = document.sourceMap else { return nil }
        var selected: [JSONLocationComponent] = []
        for part in path.prefix(missing ? max(0, path.count - 1) : path.count) {
            try state.meter.work(); try state.meter.retain(JSONLogicalWeights.frame); selected.append(part)
        }
        var span: JSONSourceSpan?
        do {
            span = try map.span(at: selected, meter: &state.meter)
            if span == nil, !missing, !selected.isEmpty {
                // A wrong-container or negative-index hop has no child span.
                // Borrow the already bounded prefix; do not invent a location.
                selected.removeLast(); try state.meter.release(JSONLogicalWeights.frame)
                span = try map.span(at: selected, meter: &state.meter)
            }
        }
        catch { try state.meter.release(UInt64(selected.count) * JSONLogicalWeights.frame); throw error }
        try state.meter.release(UInt64(selected.count) * JSONLogicalWeights.frame)
        guard let span else { return nil }
        guard let bytes = document.sourceBytes else { return .init(byteOffset: span.start) }
        var line: UInt64 = 1, column: UInt64 = 1, offset: UInt64 = 0
        for byte in bytes {
            if offset == span.start { break }
            try state.meter.work(); offset += 1
            if byte == 10 { line += 1; column = 1 } else { column += 1 }
        }
        return .init(byteOffset: span.start, line: line, column: column)
    }
    package func select(_ path: [JSONLocationComponent], state: JSONCodingState) throws -> JSON {
        guard phase == .admitted, let document else {
            let failure = JSONFailure(.configuration, code: .invalidOperation)
            self.state?.meter.recordFailure(failure)
            throw failure
        }
        var value = document.root
        for part in path {
            try state.meter.work()
            switch part {
            case .key(let key):
                guard case .object(let object) = value else { throw JSONFailure(.typeMismatch, code: .wrongKind) }
                guard let child = try object.lookup(key.string, meter: &state.meter) else { throw JSONFailure(.missingValue, code: .missingMember) }
                value = child
            case .index(let index):
                guard case .array(let array) = value else { throw JSONFailure(.typeMismatch, code: .wrongKind) }
                guard index >= 0 else { throw JSONFailure(.configuration, code: .invalidIndex) }
                guard index < array.count else { throw JSONFailure(.missingValue, code: .missingTarget) }
                value = array[index]
            }
        }
        return value
    }
    package func append(_ part: JSONLocationComponent, to path: [JSONLocationComponent], state: JSONCodingState) throws -> JSONReadPath {
        guard phase == .admitted else {
            let failure = JSONFailure(.configuration, code: .invalidOperation)
            self.state?.meter.recordFailure(failure)
            throw failure
        }
        try state.meter.require(.pointerTokens, UInt64(path.count) + 1)
        var pointerBytes: UInt64 = 0, owned: UInt64 = 0
        for position in 0...path.count {
            let component = position == path.count ? part : path[position]
            pointerBytes = try state.meter.adding(.pointerBytes, pointerBytes, 1)
            let text: String
            switch component {
            case .key(let key): text = key.string
            case .index(let index):
                // Preflight the bounded formatting bridge before it allocates.
                try state.meter.retain(21); try state.meter.checkpoint()
                text = String(index)
                try state.meter.work(UInt64(text.utf8.count)); try state.meter.release(21)
            }
            try state.meter.work(); owned = try state.meter.adding(.retainedBytes, owned, JSONLogicalWeights.indexSlot)
            for byte in text.utf8 {
                try state.meter.work()
                pointerBytes = try state.meter.adding(.pointerBytes, pointerBytes, byte == 47 || byte == 126 ? 2 : 1)
                if case .key = component { owned = try state.meter.adding(.retainedBytes, owned, 1) }
            }
        }
        try state.meter.require(.diagnosticBytes, pointerBytes)
        try state.meter.retain(owned)
        var result: [JSONLocationComponent] = []
        do {
            for component in path { try state.meter.work(); result.append(component) }
            try state.meter.work(); result.append(part)
        } catch { try state.meter.release(owned); throw error }
        pathBytes += owned
        return JSONReadPath(scope: self, components: result, bytes: owned)
    }
}
package final class JSONReadPath {
    package let scope: JSONReadScope
    package let components: [JSONLocationComponent]
    private let bytes: UInt64
    package init(scope: JSONReadScope, components: [JSONLocationComponent], bytes: UInt64) {
        self.scope = scope; self.components = components; self.bytes = bytes
    }
    deinit { scope.retirePath(bytes) }
}
