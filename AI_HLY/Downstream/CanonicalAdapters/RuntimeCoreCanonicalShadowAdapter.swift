import Foundation
import HanlinPlatformContracts

/// Projects RuntimeCore status values without changing actor ownership,
/// preparation, execution, cancellation, persistence, or lifecycle behavior.
///
/// Legacy source: `RuntimeSnapshot`. Canonical target:
/// `HanlinRuntimeSessionDescriptor`. Storage/cache/package counts and diagnostic
/// strings remain implementation state; the stable failure code is retained.
/// Delete after RuntimeCore emits canonical runtime session snapshots directly.
enum RuntimeCoreCanonicalShadowAdapter {
    static func project(
        _ snapshot: RuntimeSnapshot,
        sessionID: HanlinRuntimeSessionID,
        providerInstanceID: HanlinProviderInstanceID,
        createdAt: Date,
        observedAt: Date
    ) -> HanlinRuntimeSessionDescriptor {
        HanlinRuntimeSessionDescriptor(
            id: sessionID,
            providerInstanceID: providerInstanceID,
            kind: project(snapshot.kind),
            runtimeVersion: snapshot.version,
            state: project(snapshot.state),
            createdAt: createdAt,
            stateChangedAt: observedAt,
            activeExecutionCount: snapshot.activeExecutionCount,
            failureCode: snapshot.lastErrorCode
        )
    }

    static func projectJSONValue(
        _ value: RuntimeJSONValue,
        path: String = ""
    ) throws -> HanlinJSONValue {
        switch value {
        case .null:
            return .null
        case let .boolean(value):
            return .bool(value)
        case let .number(value):
            guard value.isFinite else { throw HanlinContractError.invalidNumber(value) }
            return .number(value)
        case let .string(value):
            return .string(value)
        case let .array(values):
            return try .array(values.enumerated().map { index, child in
                try projectJSONValue(child, path: "\(path)/\(index)")
            })
        case let .object(values):
            return try .object(Dictionary(uniqueKeysWithValues: values.map { key, child in
                (key, try projectJSONValue(child, path: "\(path)/\(key)"))
            }))
        }
    }

    private static func project(_ kind: RuntimeKind) -> HanlinRuntimeKind {
        switch kind {
        case .node: .node
        case .typeScript: .typeScript
        case .localPython: .localPython
        case .javaScriptCore: .javaScriptCore
        case .shell: .shell
        }
    }

    private static func project(_ state: RuntimeOperationalState) -> HanlinRuntimeSessionState {
        switch state {
        case .unavailable, .stopped: .stopped
        case .preparing: .preparing
        case .ready: .ready
        case .executing: .executing
        case .failed: .failed
        case .appRestartRequired: .restartRequired
        }
    }
}
