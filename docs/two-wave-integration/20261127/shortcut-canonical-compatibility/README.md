# Canonical native-action observer compatibility

The compiler records declared native App Intent actions with partial compatibility. The existing publisher accepts their exact native runtime, policy, exported action and handler. The shared surface observer previously admitted only supported compatibility and therefore rejected this canonical representation before observing the native operation.

The source change accepts exactly supported or partial. It preserves the remaining enabled/current-generation, identity, cardinality, kind, execution-context, runtime-profile, policy, action and handler guards. Tuple membership also safely rejects malformed JSON values.

## Validation

The new positive control consumes the unchanged recorded semantic registry embedded in HanlinCanonicalEntrypointProjectionTests.swift and checks that its bytes are not rewritten. That fixture retains the original whole-registry fingerprint. One control failed against the original reader. The two new controls plus the existing supported-action control then passed against the candidate. Twelve invalid contract mutations remain rejected. All 20 original test-method ASTs and the entire original test file are preserved.

The retained receipts and lossless logs describe those actual executions. Independent review reused them without another run. These two changed paths intersect none of the 396 accepted SDK inputs.

## Native scope

The previous long-running run had two catalog-readiness failures and two failures at a compound entrypoint identity guard. Its exact failing catalog row was not retained. This change fixes a demonstrated canonical schema mismatch; it does not establish the sole native failure cause or a native pass. Original native tests, selectors, assertions and deadlines remain unchanged.

Source base: e86e779d5d4bf85db3c9802e569c032283515ad6.
Source commit: 57cca4ea0a6b9d795c6de1f6d75584fc5360a44f.
