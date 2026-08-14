# Canonical Contract Decision Register

Status: proposed design decisions for owner approval. No entry authorizes Phase 2.

Snapshot: `a5cea34dc60038c860b4148ee934111f3fac59bd` after fresh remote fetch.

## Status vocabulary

- **Selected**: fixed by the user's architectural direction or an accepted
  repository ADR.
- **Proposed**: resolved by this specification, awaiting owner approval.
- **Blocking**: an explicit product/security choice or SDK/compiler proof is
  still required before the affected implementation stage.

## Decisions

| ID | Status | Decision | Consequence |
| --- | --- | --- | --- |
| CCD-001 | Selected | `HanlinPlatformContracts` is the physical home of canonical portable contracts; current API is not frozen. | Evolve lossy/ambiguous package types before app linkage. |
| CCD-002 | Selected | `NativeAppPlatform` remains native host/runtime; NativeAgentExtensions remains native tool/UI; MCP and RuntimeCore remain implementations; Scripting remains reference-only. | Canonical package never imports UI, SDK, runtime, or persistence implementations. |
| CCD-003 | Proposed | Use one canonical model with narrow cutover adapters, not a permanent parallel model. | Every adapter has explicit deletion criteria and no new feature may depend solely on a legacy adapter. |
| CCD-004 | Proposed | Use distinct typed IDs for installed instances, providers, app sessions, runtime sessions, invocations, grants, revocations, migrations, and cancellations. | Replace ambiguous generic session identity and raw cross-boundary UUID/String use. |
| CCD-005 | Proposed | Keep rich `HanlinValue`, add strict `HanlinJSONValue`, split Hanlin value schema from lossless JSON Schema documents, and fail every lossy conversion. | Current `HanlinJSONSchema` is replaced after descriptor/fixture migration; RuntimeJSONValue and MCP SDK values stay implementation types. |
| CCD-006 | Proposed | Exact finite binary64 bit patterns and Int64 values are preserved in rich tagged encoding; standard JSON conversion succeeds only when the destination can represent the value without loss. | Int64-to-JavaScript outside the safe-integer range, binary-to-JSON, and unrepresentable Foundation/MCP numbers fail. |
| CCD-007 | Proposed | Logical tool identity is `(providerInstanceID, localToolID)`; exposed model names are scoped aliases. | Native bare names and current `mcp__...` aliases remain observable cutover behavior, while routing no longer treats names as identity. |
| CCD-008 | Proposed | Preserve native-first observable resolution during cutover; reject duplicate native registrations; retain deterministic MCP collision suffixing; reserve `script__...` for future script aliases. | A future priority change requires a versioned routing-policy decision and behavior migration. |
| CCD-009 | Proposed | Capability declaration is non-authorizing. Only an effective grant plus current policy and OS state permits an operation. | Privileged service gateways fail closed and emit decisions/audit. |
| CCD-010 | Proposed | Grants bind exact subject/provider instance, package version/integrity, capability, and normalized scope; broadening any component requires a new decision. | Package updates and scope expansion cannot inherit grants silently. |
| CCD-011 | Proposed | Revocation is durable and immediately invalidates effective grants; active operations are cancelled unless a capability-specific policy explicitly permits bounded completion. | Effective permissions are derived cache, never persisted authority. |
| CCD-012 | Proposed | `MCPServerDescriptor` is split into installed package, provider configuration, resolved runtime configuration, runtime status, and discovery cache. | Preserve the current registry as a legacy boundary until verified migration/rollback. |
| CCD-013 | Proposed | Existing SwiftData/CloudKit conversations, knowledge, prompts, saved native-app content, drafts, credentials, settings, installed packages, workspaces, and exact approvals are concrete state worth preserving. | Migrate or retain readers; do not reset them merely because the project is under development. |
| CCD-014 | Proposed | Reproducible caches, staging/tmp, runtime discovery snapshots, tool counts, compatibility caches, and bounded debug logs may be rebuilt/reset. | No migration is required beyond safe cleanup and regeneration tests. |
| CCD-015 | Proposed | Existing lifecycle approvals are not capability grants and never authorize Scripting/device APIs. | Preserve them only for their exact package-script hash behavior until a separate policy-approval contract replaces them. |
| CCD-016 | Proposed | Generalize `HanlinScriptEnvelope` into a negotiated, typed envelope; enforce ordered sequences, hard resource caps, explicit feature negotiation, and typed errors. | Script/runtime implementation waits until every message kind has a typed payload. |
| CCD-017 | Selected | Authorized Scripting baseline remains immutable and exact; declaration presence is not implementation. | Overlays and compatibility records remain separate. |
| CCD-018 | Blocking | Select the product compiler lane: upgrade embedded RuntimeCore from TypeScript 6.0.3 to the authorized 7.0.2 lane, or explicitly support a non-conformant embedded lane with documented fixture failures. | No claim of Scripting compiler/API compatibility before exact project typecheck and runtime fixtures pass on the shipped compiler. |
| CCD-019 | Blocking | Approve first Scripting contexts and APIs, permission UX, storage quota, process/resource limits, and extension availability. | Scripting provider registration and execution remain prohibited. |
| CCD-020 | Blocking | Approve whether user-visible permission decisions sync across devices or remain local-device security state. | Permission-store implementation and CloudKit relationship cannot begin. Recommended default: local-device only. |
| CCD-021 | Blocking | Approve retention/export policy for security audit events separately from user activity and debug diagnostics. | Audit sink persistence cannot be finalized. |
| CCD-022 | Proposed | First implementation slice is package-only: evolve IDs/value/schema/error/wire primitives and add exhaustive fixtures, without linking the app. | Lowest behavior/persistence/upstream risk; prerequisite to every adapter. |

## Resolved corrections to the prior audit

The prior audit left provider qualification, schema representation, permission
lifecycle, persistence disposition, and compiler policy open. This design
resolves the architectural direction for all five. It also sharpens two points:

1. `HanlinJSONSchema` should not remain the canonical name/type for both a
   closed Hanlin schema vocabulary and arbitrary JSON Schema. Lossless JSON
   Schema requires a distinct document type that preserves unknown keywords.
2. `HanlinSessionID` is too broad for the selected model. App sessions and
   runtime sessions require separate identities even if an adapter temporarily
   maps both to the old type.

No source finding in the audit was invalidated by commit `a5cea34`; that commit
contains the audit outputs themselves and no product-source changes relative to
the audited parent.

## Owner approvals still required

The design can be approved as a set while leaving CCD-018 through CCD-021 as
explicit product gates. Before implementation, record accepted decisions in
ADRs and identify the exact stage from `CUTOVER_SEQUENCE.md` being authorized.
