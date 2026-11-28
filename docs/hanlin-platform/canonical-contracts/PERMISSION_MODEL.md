# Canonical Permission and Policy Model

Status: proposed security contract; no permission or service behavior is changed.

## 1. Security invariant

A capability declaration is a claim by a package/app/tool about intended access.
It is never authorization. An operation is allowed only when all of these are
true at the side-effect boundary:

1. the capability and requested scope were declared by the exact subject;
2. the request is valid for the current origin/context and user-gesture rules;
3. canonical policy allows consideration of the request;
4. a non-expired, non-revoked grant covers the exact subject and scope;
5. required Apple system authorization is currently sufficient;
6. runtime/provider/package identity and integrity still match the grant;
7. current resource and distribution policy allows the operation; and
8. required audit recording succeeds.

Missing or unknown evidence denies by default.

## 2. Actors and records

| Concept | Meaning |
| --- | --- |
| Capability definition | Host-registered meaning, scope schema, risk, OS authorization requirement, contexts, revocation behavior |
| Capability declaration | Descriptor's non-authorizing purpose, desired scope constraints, and optionality |
| Permission subject | Exact app/package/provider instance and version/integrity receiving access |
| Permission request | One correlated request for one or more declared capability scopes |
| Policy evaluation | Immutable evaluation of request/operation against policy and context |
| Permission decision | Immutable user/system/admin outcome and reason |
| Grant | Durable positive authorization with exact scope/conditions/expiry |
| Revocation | Durable invalidation targeting a grant/subject/scope |
| Effective permission | Derived present-tense result of grant + policy + OS state + context |
| Enforcement decision | Immediate allow/deny/obligations at a service gateway |
| Audit event | Append-only safe evidence of every lifecycle step and use |

## 3. Declaration

`HanlinCapabilityDeclaration` contains capability ID, localized purpose,
requested constraint value validated against the capability's scope schema,
optionality, and declaring descriptor location. Package validation rejects an
unknown required capability or malformed scope. An unknown optional capability
may make the relevant feature unavailable but does not grant it.

Declarations are immutable with package content and integrity. Adding or
broadening a capability in an update requires a new permission evaluation; an
old grant is not automatically widened.

## 4. Request

`HanlinPermissionRequest` binds:

- request ID and timestamp/deadline;
- exact subject: app, installed package/provider instance, version, integrity;
- declaration revision;
- capability and normalized requested scope;
- purpose and triggering operation;
- execution origin (`userInterface`, assistant/model, automation, script,
  runtime lifecycle, system);
- app/runtime session and caller IDs;
- user-gesture evidence and presenting context;
- desired duration (`once`, `session`, `untilDate`, `persistent`); and
- current OS authorization observation.

Requests with empty capabilities, undeclared access, broader-than-declared
scope, unavailable context, or fabricated gesture evidence fail before prompt.

## 5. Policy evaluation

The broker evaluates a versioned policy before prompting. The result is
`allowWithoutPrompt`, `requireUserDecision`, `requireSystemAuthorization`,
`deny`, or `deferUnavailable`, with obligations.

Policy considers origin, risk, scope, descriptor trust/integrity, distribution,
execution context, prior decisions, current grants/revocations, OS state,
parental/enterprise/system restrictions, presenting UI, resource limits, and
whether the operation is reversible. Model/script origins never inherit a
user-interface gesture merely because they run in a visible app.

The current `NativeCapabilityRegistry.status(.available)` is not evidence of
grant and cannot map to `allowWithoutPrompt`.

## 6. Decision and system authorization

If Apple system authorization is required, the platform distinguishes:

- not determined;
- restricted/unavailable;
- denied;
- limited/partial; and
- sufficient for the requested scope.

Exact OS enums remain service implementation details; canonical evidence stores
a normalized status and observation time. A platform user prompt cannot override
an OS denial. A system authorization success does not itself create a Hanlin
grant unless policy also allows it.

A `HanlinPermissionDecision` records decision ID, request ID, decider
(user/system/policy), outcome, exact approved/denied scopes, decision time,
policy version, OS evidence, safe explanation, and whether a grant was issued.
Decisions are immutable history.

## 7. Grant

Positive decisions may issue `HanlinPermissionGrant` with:

- grant ID and decision ID;
- exact subject/provider instance and package version/integrity;
- capability and normalized scope;
- conditions: origin/context/gesture/foreground/network/resource constraints;
- issued/not-before/expiry timestamps;
- duration kind and usage count for one-shot grants;
- policy version and OS evidence requirements; and
- supersedes relationship.

Default scope is least privilege. Persistent is never the implicit duration for
script/model/automation origins. A one-shot grant is atomically consumed at
operation authorization, not after the side effect.

Recommended default is local-device storage with complete file protection and
no CloudKit sync. Whether grants sync is a blocking owner decision.

## 8. Effective permission

Effective permission is computed, not stored as authority:

```text
declared AND grant covers exact subject/scope AND not expired/consumed/revoked
AND policy still permits AND OS authorization sufficient AND context conditions
hold
```

The result includes `allowed` or a stable denial reason, contributing grant and
policy IDs, remaining scope/duration, OS evidence, and calculation time. Caches
are invalidated by clock/expiry, package update/integrity change, policy change,
revocation, OS authorization change, session end, and context change.

## 9. Expiry and revocation

Expiry is automatic and emits an audit event. Revocation is an immutable record
with revocation ID, actor/reason/time, and target (grant, subject, provider,
capability, or scope). Revocation immediately invalidates cache and publishes a
change stream.

Active operations are cancelled by default. A capability definition may allow
bounded completion only when stopping would be more harmful and no additional
scope is consumed; that exception is policy-versioned and audited. New operations
always fail after revocation.

Uninstall revokes all grants for the provider instance. Reinstall receives a new
installed/provider-instance ID. Package update preserves a grant only if exact
content binding and policy explicitly allow it; the default is reevaluation.

## 10. Enforcement

Every privileged implementation is behind a gateway. The gateway:

1. constructs an operation-specific effective-permission query;
2. validates the operation scope against the grant;
3. evaluates current policy and OS state;
4. records authorization audit;
5. performs the side effect only on allow;
6. monitors revocation/cancellation for long operations; and
7. records terminal outcome.

Network enforces normalized scheme/host/port/path rules and redirect destinations,
not only the initial URL. Storage enforces owner namespace/quota. Clipboard,
files, contacts, calendar, location, health, notifications, camera, microphone,
and open-URL enforce their specific scopes. Direct `URLSession.shared` or similar
bypasses from app/script/provider code are prohibited after the enforcement
stage.

## 11. Audit lifecycle

Append safe events for declaration validation, request creation/rejection,
policy evaluation, OS prompt/result, user decision, grant issue/use/consume,
expiry, revocation, enforcement allow/deny, cancellation, and terminal outcome.
Events include correlation and subject/scope hashes but never secret values or
unredacted health/contact/file content.

Security audit, user-facing activity, and debug logs are distinct stores with
distinct retention. `AgentRun` and diagnostic JSON are not the authority for a
grant.

## 12. Error semantics

Required stable denial/failure codes include capability not declared, unknown
capability, invalid/out-of-declaration scope, prompt unavailable, user denied,
system denied/restricted, no grant, grant expired/consumed/revoked, subject
mismatch, package changed, policy denied/changed, gesture required, context
unsupported, audit unavailable, and operation cancelled.

User messages do not expose policy internals or secrets. Diagnostics reference
decision/policy/event IDs for local investigation.

## 13. Current-type disposition

- `HanlinCapabilityDeclaration`: evolve and remain canonical declaration.
- `HanlinPermissionDecisionID`: remain canonical, supplemented by request/grant/
  revocation IDs.
- `NativeCapabilityID`: temporary declaration adapter, then replace.
- `NativeCapabilityRequest`: currently declaration-shaped despite its name;
  adapter must map it to declaration, not grant/request automatically.
- `NativeCapabilityStatus`: replace; `.available` must never become allowed.
- `NativeCapabilityRegistry`: runtime-only during cutover, then replace with the
  permission broker/registry implementation.
- `NativeAppNetworkBroker`, pasteboard/open-URL/storage/action brokers: host
  implementations that require enforcement adapters; implementations may stay,
  unguarded entry points may not.
- `LifecycleApprovalRecord/Broker`: runtime-only exact-script approval, not a
  device capability grant.

## 14. Tests and deletion criteria

Tests must cover declaration/request separation, scope normalization/broadening,
every origin/context, grant duration and atomic one-shot use, clock expiry,
revocation races, package update/uninstall/reinstall, OS state changes, redirects,
direct-bypass detection, audit failure, concurrent requests, prompt cancellation,
and app/session termination.

Legacy capability adapters are deleted only after every privileged service path
uses canonical enforcement, all current built-in behavior has declared scopes,
grant storage/recovery/rollback is verified, lifecycle approvals remain isolated,
and an explicitly requested Xcode verification run passes on the exact commit.

