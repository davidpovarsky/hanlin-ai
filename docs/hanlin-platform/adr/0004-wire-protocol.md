# ADR 0004: Script wire protocol

Status: accepted
Date: 2026-07-23

## Decision

JS-to-Swift traffic uses a versioned Codable envelope containing protocol
version, session, sequence, optional request identity, typed message kind, and
`HanlinValue` payload. The protocol supports negotiation, ordering,
request/response, events, cancellation, UI snapshots/patches, logs, progress,
handles, lifecycle, bounded payloads, and stable error codes.

## Consequences

No public bridge accepts `[String: Any]`, raw Swift objects, raw pointers, or
retained unmanaged `JSValue`. Deterministic encoding and malformed/unknown
message tests are Phase 1 and Phase 7 acceptance requirements.
