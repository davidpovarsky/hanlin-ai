# Canonical Contract Model

Status: proposed architecture; implementation is not authorized by this document.

Audited repository snapshot: `codex/fix-mcp-reachable-compatibility` at
`a5cea34dc60038c860b4148ee934111f3fac59bd` after a fresh fetch of `origin` on
2026-08-14. That commit adds only the contract-audit documentation and generator
to its parent `da0929110903c83e9314ccd29d14d6d8be987d1a`; the audited Swift,
package, project, runtime, persistence, and Scripting inputs are unchanged.

## 1. Decision

`HanlinPlatformContracts` is the physical home of the future canonical,
portable domain contracts. Its current public API is input to this design, not
an API freeze. Types that already have the right responsibility may remain;
ambiguous or lossy types must evolve before app linkage.

The permanent architecture has four roles:

1. **Canonical contracts** in `Packages/HanlinPlatform/Sources/HanlinPlatformContracts`:
   immutable, UI-free, runtime-neutral, `Sendable` value types and versioned
   wire/persistence payload definitions.
2. **Native host** in `AI_HLY/NativeAppPlatform`: executable SwiftUI modules,
   navigation, presentation, app-session ownership, and concrete system-service
   implementations.
3. **Provider/runtime implementations**: native tools in
   `AI_HLY/NativeAgentExtensions`, MCP under `AI_HLY/Downstream/MCP`, and
   execution engines under `AI_HLY/Downstream/RuntimeCore`.
4. **Adapters** at package/app boundaries: narrow, one-way translations whose
   removal criteria are recorded in this document and
   `CURRENT_TYPE_DISPOSITION.md`.

Scripting remains reference-only. It may become another provider and runtime
implementation only after every gate in `SCRIPTING_INTEGRATION_GATES.md` passes.

### 1.1 Source basis

This design was cross-checked against the current declarations and behavior
boundaries at the audited HEAD, specifically:

- package IDs, versions, descriptors, tagged values/schema, errors, manifest
  validation, and script envelope under
  `Packages/HanlinPlatform/Sources/HanlinPlatformContracts/**`;
- native manifest/module/registry/launch/session/context, routes/actions,
  capabilities, and service brokers under `AI_HLY/NativeAppPlatform/**`;
- executable native tools, untyped OpenAI schemas, catalogs/settings, results,
  persisted rich UI, and bridges under `AI_HLY/NativeAgentExtensions/**`;
- MCP registry/backup repair, installed descriptors/configuration/path resolver,
  Keychain secrets, runtime lifecycle, SDK session/content, tool naming/catalog,
  request selection, and bridges under `AI_HLY/Downstream/MCP/**`;
- RuntimeCore values/requests/results/errors, actors, environments/secrets,
  file layout, package state, lifecycle approvals, cancellation endpoints, and
  TypeScript services under `AI_HLY/Downstream/RuntimeCore/**`;
- AgentActivity schema 4, NativeUI persistence in `ChatMessages`, diagnostics,
  and the upstream-derived `APIManager`/`ChatView` integration path;
- SwiftData/CloudKit composition and all file/UserDefaults/Keychain stores
  inventoried in `PERSISTENCE_AND_MIGRATION_POLICY.md`; and
- the immutable Scripting baseline/compiler profile and declarations under
  `Reference/ScriptingCompatibility/**`, plus `RuntimeDependencies.lock.json`.

The existing audit reports were used as an index and then checked against these
sources. Apple web documentation was not needed or consulted. No Xcode SDK,
compiler, package build, app build, runtime test, or GitHub Actions run was used
for this design-only task; all proposed declarations and Apple/platform behavior
remain uncompiled architecture until explicitly verified.

## 2. Invariants

- A descriptor declares what exists; it never executes code.
- A capability declaration explains intended access; it never grants access.
- A permission decision is historical evidence; only a currently effective
  grant authorizes an operation.
- Every executable tool has a provider-qualified logical identity. A model-facing
  function name is a scoped routing alias, not identity.
- App sessions, runtime sessions, requests, invocations, grants, and installed
  instances have different ID types. The current generic `HanlinSessionID` must
  not remain the identity for all of them.
- Portable contracts contain no `AnyView`, closures, `ModelContext`, actor
  references, absolute paths, Keychain handles that reveal secrets, SDK types,
  or `[String: Any]`.
- Canonical data conversion is total only where it is lossless. Otherwise it
  fails with a stable error and a value path; it never coerces silently.
- Runtime state is ephemeral unless a persistence policy explicitly classifies
  a record as durable.
- Cancellation is cooperative, idempotent, correlated by a typed ID, and ends
  each accepted operation in exactly one terminal state.
- Unknown wire kinds, unsupported major versions, malformed IDs, invalid state
  transitions, and exceeded limits fail closed.
- Existing persisted data is preserved only when classified as user data,
  secrets, configuration/security decisions, installed state, or genuinely
  non-reconstructible state. Cache and obsolete development-only formats may be
  reset or rebuilt.

## 3. Common contract vocabulary

The following are proposed names. Final Swift spelling is an implementation
detail, but the distinctions are normative.

### 3.1 Identities

Keep the current validated string IDs where their responsibility is already
unambiguous: `HanlinAppID`, `HanlinPackageID`, `HanlinModuleID`,
`HanlinRouteID`, `HanlinActionID`, `HanlinToolID`, `HanlinCapabilityID`,
`HanlinRequestID`, `HanlinPublisherID`, and `HanlinMCPServerID`.

Add distinct IDs for `HanlinProviderID`, `HanlinProviderInstanceID`,
`HanlinInstalledPackageID`, `HanlinCatalogRegistrationID`,
`HanlinLaunchID`, `HanlinAppSessionID`, `HanlinRuntimeSessionID`,
`HanlinToolInvocationID`, `HanlinScriptExecutionID`,
`HanlinPermissionRequestID`, `HanlinPermissionDecisionID`, `HanlinGrantID`,
`HanlinRevocationID`, `HanlinPolicyEvaluationID`, `HanlinAuditEventID`,
`HanlinMigrationID`, and `HanlinCancellationID`.

Canonical string IDs use the existing lowercase ASCII grammar unless a type
has an externally assigned opaque value. External IDs are carried as a separate
`externalReference`, never made valid by weakening canonical validation.
Instance IDs generated from UUIDs use lowercase hyphenated UUID text behind a
typed wrapper. IDs are never reused after deletion.

### 3.2 Versions

- `HanlinPackageVersion` remains semantic package/content version.
- `HanlinManifestVersion` versions descriptor shape and meaning.
- `HanlinAPIVersion` versions the host contract surface.
- `HanlinWireProtocolVersion` versions envelope negotiation and framing.
- Add per-record `schemaVersion` for persisted documents and event payloads.
- Add monotonically increasing `descriptorRevision` and `catalogRevision` for
  discovery snapshots; these are not semantic versions.

Major-version mismatch is incompatible. A higher minor version is accepted
only when the negotiated feature set and unknown-field rules make the payload
safe. Package prerelease ordering follows the canonical package-version type.
Build metadata does not select API compatibility.

### 3.3 Values and schemas

The canonical model is split deliberately:

- `HanlinValue`: rich portable domain value, including `Int64`, finite IEEE-754
  binary64, and binary data. Its next wire form must preserve the exact integer,
  floating-point bit pattern (including signed zero), and bytes.
- `HanlinJSONValue`: strict JSON-domain value used for Foundation/MCP/script
  JSON boundaries. It distinguishes integer from binary64 when the producer
  can prove that distinction, contains no binary case, and rejects non-finite
  values.
- `HanlinValueSchema`: the closed, typed schema for `HanlinValue`, including
  binary data.
- `HanlinJSONSchemaDocument`: a lossless JSON Schema document backed by
  `HanlinJSONValue`, with an explicit dialect URI and preservation of unknown
  keywords.

The current `HanlinJSONSchema` mixes a closed Hanlin schema vocabulary with a
name that implies arbitrary JSON Schema. It is replaced after manifest and
adapter migration; see `VALUE_SCHEMA_ROUNDTRIP.md`.

### 3.4 Errors

Evolve `HanlinPlatformError` into a stable error payload containing:
`code`, safe localized/user message key plus arguments, redacted diagnostic,
structured details, optional retry classification, causal subsystem code,
and correlation IDs. Errors are values returned by results/envelopes, not
untyped localized strings. Provider errors are mapped without exposing secrets;
the original provider code may be retained in redacted diagnostic details.

Cancellation and timeout are distinct terminal outcomes. A provider's
`isError` response is a completed invocation with a failed outcome, not a
transport exception. Validation, policy denial, unavailable provider,
transport failure, execution failure, timeout, cancellation, and result-size
failure remain distinguishable.

## 4. Domain specifications

Each domain below makes an explicit ownership, identity, data, lifecycle,
concurrency, wire, persistence, error, compatibility, and disposition decision.
Specialized details in the companion documents are normative where referenced.

### 4.1 Identity and versions

- **Responsibility and types:** define non-interchangeable typed IDs, semantic
  package versions, contract versions, record schema versions, and catalog
  revisions as listed in section 3.
- **Owner:** `HanlinPlatformContracts`.
- **Representation:** canonical strings on wire/persistence; typed wrappers in
  Swift. No raw UUID or path is a portable identity.
- **Lifecycle/concurrency:** immutable, `Codable`, `Hashable`, `Sendable` values;
  identity outlives runtime objects and is never recycled.
- **Wire/persistence:** required wherever correlation or durable references
  exist. Envelope and record versions are explicit fields.
- **Errors/compatibility:** malformed IDs are rejected; major mismatch fails;
  minor negotiation is feature-gated. The current generic `HanlinSessionID`
  requires adapters and is replaced after all call sites use specific session
  IDs. Current subsystem `String`/`UUID` IDs remain runtime-only until then.

### 4.2 Values and schemas

- **Responsibility and types:** `HanlinValue`, `HanlinJSONValue`,
  `HanlinValueSchema`, `HanlinJSONSchemaDocument`, `HanlinSchemaDialect`.
- **Owner:** `HanlinPlatformContracts`.
- **Identity/representation:** values have structural equality; schema
  documents may carry a content hash when catalog revisioning needs identity.
  Rich values use tagged encoding; JSON values use canonical JSON.
- **Lifecycle/concurrency:** immutable `Sendable` trees validated at ingress.
- **Wire/persistence:** size/depth/member limits are checked before allocation
  and after encoding. Raw JSON Schema keywords survive decode/encode.
- **Errors/compatibility:** failure includes JSON Pointer/value path and source/
  destination domains. No lossy fallback. Current `RuntimeJSONValue` remains
  runtime-only; MCP `Value` remains SDK-only; `[String: Any]` remains adapter
  input. Current `HanlinJSONSchema` is replaced only after every descriptor,
  manifest fixture, and provider adapter uses the split schema types and old
  encoded manifests either migrate or are explicitly reset.

### 4.3 App and package descriptors

- **Responsibility and types:** evolve `HanlinAppDescriptor`; add
  `HanlinPackageDescriptor` so package/distribution/integrity/dependencies are
  not conflated with one app; keep entry, route, action, tool, capability,
  author, localization, appearance, and implementation descriptors as portable
  declaration values.
- **Owner:** `HanlinPlatformContracts`.
- **Identity/representation:** package ID + package version identify immutable
  package content; app ID identifies an app declared by that content. Integrity
  identifies exact bytes. Descriptors use canonical values/schema documents.
- **Lifecycle/concurrency:** draft -> validated -> accepted/rejected ->
  superseded/withdrawn; immutable and `Sendable` after validation.
- **Wire/persistence:** manifest is versioned canonical JSON. The catalog owns
  accepted copies; the descriptor does not write itself.
- **Errors/compatibility:** structural, semantic, integrity, host-range, and
  unsupported-feature errors are separate. `NativeAppManifest` remains live
  host metadata behind an adapter and is replaced only when all built-ins are
  represented by validated canonical descriptors with search, settings,
  localization, and launch parity. `NativeAppModule` remains runtime-only.

### 4.4 Catalog and registration

- **Responsibility and types:** `HanlinCatalogSnapshot`,
  `HanlinCatalogRegistration`, `HanlinRegistrationSource`,
  `HanlinCatalogChange`, and query/filter contracts.
- **Owner:** values in `HanlinPlatformContracts`; the host owns the authoritative
  actor/service implementation.
- **Identity/representation:** registration ID is distinct from app/package ID;
  source priority and descriptor revision are explicit. Duplicate canonical
  app/package identities are rejected unless a defined replacement operation
  names the prior registration.
- **Lifecycle/concurrency:** discovered -> validating -> registered -> enabled/
  disabled -> superseded -> removed. One actor serializes mutations and emits
  ordered snapshots/changes as `AsyncSequence`.
- **Wire/persistence:** catalog changes are wire-capable; durable registration
  is host-owned installed/configuration state, while snapshots are rebuildable.
- **Errors/compatibility:** collisions, invalid descriptors, unavailable source,
  and stale revision are stable errors. `NativeAppRegistry` remains the native
  executable registry behind an adapter and is deleted/replaced only after the
  canonical catalog plus native module binding owns all lookup and registration
  consumers with parity tests.

### 4.5 Installed package and provider instances

- **Responsibility and types:** `HanlinInstalledPackage`,
  `HanlinProviderDescriptor`, `HanlinProviderInstance`,
  `HanlinProviderConfiguration`, and `HanlinInstallationState`.
- **Owner:** portable records in `HanlinPlatformContracts`; install stores and
  resolved paths in the host/provider package.
- **Identity/representation:** installed-instance ID is stable across launches;
  package ID/version/integrity identify content; provider-instance ID qualifies
  runtime/tool identity. Portable records contain relative logical entries and
  secret references, never absolute paths or secret values.
- **Lifecycle/concurrency:** staging -> verified -> committed -> enabled/
  disabled -> updating -> uninstalling -> removed/failed. Actor-owned mutation;
  commit and rollback are explicit.
- **Wire/persistence:** installed state is durable; resolved configuration and
  paths are derived runtime-only values.
- **Errors/compatibility:** integrity, compatibility, missing payload,
  configuration, commit, and rollback failures differ. `MCPServerDescriptor`
  is a temporary persisted adapter boundary because it mixes installed state,
  configuration, paths, compatibility, and cache. Delete it only after a
  verified migration splits every field, rollback can restore the old registry,
  and MCP install/start/settings/tool behavior is equivalent.

### 4.6 Launch requests and results

- **Responsibility and types:** `HanlinLaunchRequest`, `HanlinLaunchTarget`,
  `HanlinPresentationIntent`, and `HanlinLaunchResult`.
- **Owner:** `HanlinPlatformContracts`; native host performs launch.
- **Identity/representation:** launch ID/request ID, target app plus optional
  installed package, route request, caller identity, execution origin, and
  permission context. Presentation is a host intent, not a SwiftUI type.
- **Lifecycle/concurrency:** submitted -> validating -> authorized -> launching
  -> launched/denied/failed/cancelled. Values are `Sendable`; host UI work is
  `@MainActor`.
- **Wire/persistence:** wire-capable for script/actions; normally ephemeral.
  Only audit outcome is durable.
- **Errors/compatibility:** unknown target, invalid route, unavailable context,
  denied policy, and presentation failure differ. `NativeAppLaunchRequest`
  requires an adapter and is replaced when both WindowGroup and in-app launch
  paths consume canonical requests/results without changing presentation.

### 4.7 App sessions

- **Responsibility and types:** `HanlinAppSessionDescriptor`,
  `HanlinAppSessionState`, `HanlinAppSessionEvent`, and specific
  `HanlinAppSessionID`.
- **Owner:** value contracts in package; `NativeAppPlatform` owns live session
  objects and presentation/task tracking.
- **Identity/representation:** session ID + app/installed-instance ID + launch
  ID; route and result use canonical values.
- **Lifecycle/concurrency:** created -> activating -> active <-> suspended ->
  closing -> closed, with failed as terminal. Close is idempotent and cascades
  cancellation to child operations. State mutations are actor or main-actor
  owned; snapshots/events are `Sendable`.
- **Wire/persistence:** events are wire-capable. Sessions are ephemeral unless a
  future restoration record is explicitly versioned; current UI sessions are
  not restored.
- **Errors/compatibility:** invalid transitions and stale session IDs fail.
  `NativeAppSession` remains runtime-only and is deleted/replaced only when its
  task tracking, close semantics, environment injection, and UI observation are
  provided by the host session controller using canonical snapshots.

### 4.8 Runtime sessions

- **Responsibility and types:** `HanlinRuntimeKind`,
  `HanlinRuntimeSessionDescriptor`, `HanlinRuntimeSessionState`,
  `HanlinRuntimeFeatureSet`, and `HanlinRuntimeSessionID`.
- **Owner:** contracts in package; `RuntimeCore` and MCP own implementations.
- **Identity/representation:** runtime session is separate from app session and
  provider instance; it records negotiated runtime/compiler/protocol features,
  not service actor references or paths.
- **Lifecycle/concurrency:** allocating -> preparing -> ready -> executing <->
  ready -> suspending/suspended -> stopping -> stopped/failed. Actor-owned,
  structured child tasks only.
- **Wire/persistence:** snapshots/events are wire-capable; live session is
  ephemeral. Runtime installation manifest remains implementation installed
  state.
- **Errors/compatibility:** runtime unavailable, version/feature mismatch,
  restart required, and protocol loss differ. `RuntimeSnapshot`,
  `MCPServerStatus`, runtime slots, clients, transports, and service actors stay
  runtime-only. Adapters may publish canonical snapshots and disappear when all
  cross-subsystem consumers use them; implementation actors are never deleted
  merely because an adapter disappears.

### 4.9 Routes and actions

- **Responsibility and types:** retain descriptors; add `HanlinRouteRequest`,
  `HanlinActionRequest`, `HanlinActionResult`, and typed origin/risk/user-gesture
  requirements.
- **Owner:** package contracts; native host routes/performs.
- **Identity/representation:** route/action descriptor ID plus app identity;
  each invocation has a request ID. Parameters are validated canonical values,
  not `[String: String]`.
- **Lifecycle/concurrency:** requested -> validated -> authorized -> executing ->
  completed/failed/denied/cancelled. Values are `Sendable`; UI effects occur on
  the main actor.
- **Wire/persistence:** requests/results wire-capable; descriptors persist with
  manifests; invocations persist only as audit/activity.
- **Errors/compatibility:** unknown descriptor, schema mismatch, missing gesture,
  denied policy, and host failure differ. `NativeAppRoute`,
  `NativeAppAction`, and `NativeAppActionResult` require adapters, then are
  replaced after built-in deep links and persisted `NativeUIBlock` actions have
  migrated or retain a versioned legacy reader.

### 4.10 Capabilities

- **Responsibility and types:** evolve `HanlinCapabilityDeclaration`; add
  `HanlinCapabilityScopeSchema` and registry metadata describing whether a
  capability also requires an OS authorization.
- **Owner:** package contracts; host capability registry owns definitions.
- **Identity/representation:** extensible capability ID plus constrained scope
  value (for example normalized network hosts), purpose, optionality, and risk.
- **Lifecycle/concurrency:** definitions are registered/versioned; declarations
  belong to immutable descriptors. They have no authorization state.
- **Wire/persistence:** declarations persist with descriptors and cross wire;
  registry definitions are host configuration.
- **Errors/compatibility:** unknown capability, invalid scope, and unsupported
  context differ. `NativeCapabilityID` and declaration-shaped
  `NativeCapabilityRequest` need adapters; the closed native enum is replaced
  when every built-in declaration maps to registered canonical IDs and no
  service checks the enum directly.

### 4.11 Permission requests

- **Responsibility and types:** `HanlinPermissionRequest`,
  `HanlinPermissionSubject`, `HanlinPermissionScope`, and
  `HanlinPermissionRequestContext`.
- **Owner:** package contracts; host permission broker orchestrates.
- **Identity/representation:** request ID; subject is exact app/package/provider
  instance and version/integrity; requested capabilities/scopes, purpose,
  origin, user-gesture evidence, and desired duration are explicit.
- **Lifecycle/concurrency:** created -> validated -> policyEvaluating ->
  awaitingSystem/awaitingUser -> decided/cancelled/expired. Broker actor owns
  state; prompt UI is main-actor isolated.
- **Wire/persistence:** request/result wire-capable. Pending requests may be
  crash-recovery state with short expiry; audit persists.
- **Errors/compatibility:** undeclared capability, invalid scope, non-presenting
  context, unavailable OS service, and cancellation differ. Current
  `NativeCapabilityRequest` is not promoted unchanged and is removed only after
  all callers create canonical requests or declarations appropriately.

### 4.12 Permission grants and decisions

- **Responsibility and types:** `HanlinPermissionDecision`,
  `HanlinPermissionDecisionOutcome`, `HanlinPermissionGrant`,
  `HanlinGrantCondition`, and `HanlinGrantSource`.
- **Owner:** package contracts; host permission store/broker persists them.
- **Identity/representation:** immutable decision ID and optional grant ID link
  request, subject, capability, exact normalized scope, decider, policy version,
  timestamps, expiry, and OS authorization evidence.
- **Lifecycle/concurrency:** a decision is immutable; a grant is issued -> active
  -> expired/revoked/superseded. Actor-owned store; values `Sendable`.
- **Wire/persistence:** decisions/grants are versioned durable security data and
  auditable. Secret values never appear.
- **Errors/compatibility:** ambiguous scope or stale subject content invalidates
  effectiveness. `NativeCapabilityStatus` and `LifecycleApprovalRecord` are not
  canonical grants. The former is replaced; the latter remains runtime policy
  state until its exact lifecycle-script semantics have a separate canonical
  policy approval type.

### 4.13 Revocation and effective permissions

- **Responsibility and types:** `HanlinPermissionRevocation`,
  `HanlinEffectivePermission`, `HanlinEffectivePermissionQuery`, and reason
  codes.
- **Owner:** package contracts; host broker calculates effective state.
- **Identity/representation:** revocation has its own ID and targets a grant,
  subject, or capability scope. Effective permission is a derived snapshot with
  grant, policy, OS status, expiry, and context evidence.
- **Lifecycle/concurrency:** revocation is immutable and immediately invalidates
  matching grants; effective state is recomputed on decision, policy, clock,
  package, OS authorization, or context change. Actor serialized.
- **Wire/persistence:** revocations are durable; effective snapshots are cache
  only. Streams notify active operations; whether an operation can finish is a
  capability-specific policy, otherwise it is cancelled.
- **Errors/compatibility:** revoked, expired, OS-denied, policy-denied, scope
  mismatch, and stale subject differ. No current type implements this domain;
  temporary adapters must not synthesize `allowed` from `.available`.

### 4.14 Policy enforcement

- **Responsibility and types:** `HanlinPolicyEvaluationRequest`,
  `HanlinPolicyDecision`, `HanlinPolicyRuleID`, `HanlinPolicyVersion`, and
  obligation/denial reason values.
- **Owner:** contracts in package; host policy engine and service gateways
  enforce.
- **Identity/representation:** evaluation binds subject, operation, capability,
  scope, origin, gesture, effective grants, OS state, descriptor/integrity, and
  resource limits.
- **Lifecycle/concurrency:** evaluate immediately before the side effect and
  again for long-lived scope changes. Actor/service gateway owns enforcement;
  decisions are immutable snapshots.
- **Wire/persistence:** decisions are wire-capable and audit inputs; policy
  configuration is durable and versioned, evaluation cache is reconstructible.
- **Errors/compatibility:** deny by default on missing/unknown evidence. Current
  `NativeCapabilityRegistry` and `RuntimePolicy` remain runtime-only inputs;
  `NativeAppNetworkBroker` and other gateways require adapters/enforcement. An
  adapter is deleted only when every privileged service entry point requires a
  canonical evaluation and bypass tests prove no direct route remains.

### 4.15 Platform and system services

- **Responsibility and types:** request/result contracts for storage, network,
  clipboard, open URL, file access, contacts, calendar, location, notifications,
  health, and future services; each names required capability and scope.
- **Owner:** value contracts in package; concrete implementations in native
  host; script bindings and native app facades are adapters.
- **Identity/representation:** calls carry request/session/subject IDs and
  canonical values or typed blob handles. No service locator or framework type
  crosses the package boundary.
- **Lifecycle/concurrency:** validate -> authorize -> execute -> terminal result;
  long operations expose progress/cancellation. Service implementations declare
  isolation; payloads are `Sendable`.
- **Wire/persistence:** script-callable services use envelopes. Storage service
  persists only within an explicit owner namespace and quota; others persist
  only audit unless their domain says otherwise.
- **Errors/compatibility:** unavailable, OS-denied, platform-denied, invalid
  scope, quota, timeout, cancellation, and provider failure differ.
  `NativeAppPlatformServices`, brokers, `NativeAppContext`, and `ModelContext`
  remain host/runtime-only. They are not deleted merely because canonical
  service contracts exist; only redundant unguarded facades are replaced after
  all calls route through enforced implementations.

### 4.16 Tool descriptors and catalog

- **Responsibility and types:** evolve `HanlinToolDescriptor`; add
  `HanlinLogicalToolID` (provider instance + local tool ID),
  `HanlinToolCatalogSnapshot`, `HanlinToolAvailability`, and catalog changes.
- **Owner:** package contracts; host catalog actor composes provider catalogs.
- **Identity/representation:** logical identity is always provider-qualified;
  model alias is separate and request-scope-specific. Input/output use lossless
  schema documents, capability declarations, risk, and presentation hints.
- **Lifecycle/concurrency:** discovered -> validated -> available/unavailable ->
  superseded/removed. Catalog actor publishes immutable revisions.
- **Wire/persistence:** descriptors cross wire; live catalog is cache. Enabled
  preferences are configuration keyed by logical identity.
- **Errors/compatibility:** invalid schema, alias collision, unavailable provider,
  stale descriptor, and disabled policy differ. `NativeToolCatalog` and
  `MCPToolCatalog` remain executable/provider registries behind adapters;
  current `MCPToolDescriptor` and `NativeToolCatalogEntry` are replaced after
  canonical catalog parity and settings migration. See
  `TOOL_INVOCATION_MODEL.md`.

### 4.17 Tool invocation, result, progress, and cancellation

- **Responsibility and types:** `HanlinToolInvocationRequest`,
  `HanlinToolInvocationResult`, `HanlinToolOutcome`,
  `HanlinToolProgressEvent`, and `HanlinCancellationRequest/Acknowledgement`.
- **Owner:** package contracts; provider executors implement.
- **Identity/representation:** invocation ID, logical tool identity,
  descriptor revision, caller/session IDs, validated arguments, deadline,
  limits, permission context, and idempotency key. Results contain canonical
  model value/content, optional presentation attachment handles, provider
  metadata, and typed error.
- **Lifecycle/concurrency:** accepted -> authorizing -> executing -> terminal
  completed/failed/denied/cancelled/timedOut. Progress sequence is monotonic;
  one terminal event; structured task owns provider work.
- **Wire/persistence:** request/progress/result/cancel are wire-capable. Audit
  and user-visible activity may persist; executor objects do not.
- **Errors/compatibility:** provider `isError` maps to failed outcome; thrown
  transport errors remain transport failures. `AgentToolCall`,
  `NativeToolResult`, `MCPToolCallOutput`, and tool presentation/activity types
  remain adapters/runtime UI. They are replaced at the execution boundary only
  after native and MCP parity covers text, images, audio, resources, errors,
  progress, timeout, cancellation, and size limits.

### 4.18 Script execution request, result, and stream

- **Responsibility and types:** `HanlinScriptExecutionRequest`,
  `HanlinScriptExecutionResult`, `HanlinScriptStreamEvent`, compiler profile,
  entry-context, and diagnostic contracts.
- **Owner:** package contracts; a future Scripting provider/runtime implements.
- **Identity/representation:** execution ID, installed package/app, entry point,
  exact compiler lane/version/config hash, runtime session, canonical parameters,
  granted permissions, limits, and source/integrity identity.
- **Lifecycle/concurrency:** queued -> compiling -> ready/executing -> suspended/
  resumed -> terminal. Compile-only is a successful terminal mode. Stream events
  are ordered and cancellation-aware.
- **Wire/persistence:** request/result/stream use the negotiated wire envelope;
  source and outputs persist only per explicit app/user policy. Compiler cache is
  rebuildable.
- **Errors/compatibility:** compile diagnostics, unsupported declaration/API,
  permission denial, script exception, protocol failure, timeout, cancellation,
  and result conversion differ. `RuntimeExecutionRequest/Result`, TypeScript
  compilation types, and `HanlinScriptEnvelope` require adapters/evolution; no
  Scripting type becomes live until the gates pass.

### 4.19 Persistence ownership

- **Responsibility and types:** `HanlinPersistedRecordEnvelope`, owner/category
  metadata, schema version, integrity, creation/update times, and store
  capability descriptors. Contracts do not prescribe SwiftData versus files.
- **Owner:** envelope/classification in package; each subsystem owns its store;
  the app owns SwiftData/CloudKit composition.
- **Identity/representation:** every durable record has a stable owner namespace,
  record ID, schema version, and category. Secrets are references to a credential
  store, never inline canonical values.
- **Lifecycle/concurrency:** create/read/update/delete plus migrate/quarantine;
  one writer or transactional store per record family.
- **Wire/persistence:** envelopes are persistence-only unless export is defined.
  Backup/sync policy follows category, not directory convenience.
- **Errors/compatibility:** unavailable, corrupt, unsupported schema, integrity,
  quota, and permission failures differ. Current stores remain authoritative
  until individually migrated. Exact classifications are in
  `PERSISTENCE_AND_MIGRATION_POLICY.md`.

### 4.20 Migrations and recovery

- **Responsibility and types:** `HanlinMigrationPlan`, `HanlinMigrationStep`,
  `HanlinMigrationCheckpoint`, `HanlinRecoveryAction`, and migration report.
- **Owner:** contracts in package; store-owning subsystem implements migrations.
- **Identity/representation:** migration ID plus source/target schema, store,
  affected record counts/hashes, checkpoint, and rollback policy.
- **Lifecycle/concurrency:** planned -> preflight -> backedUp/checkpointed ->
  migrating -> verifying -> committed, or rollingBack -> rolledBack/failed/
  quarantined. Exclusive per store and cancellation only at declared safe points.
- **Wire/persistence:** checkpoints/reports are diagnostic/recovery state; backup
  retention is bounded and explicit.
- **Errors/compatibility:** insufficient space, corrupt source, unsupported
  source, conversion, verification, and rollback failure differ. Existing MCP
  primary/backup repair and path migration remain runtime mechanisms until a
  canonical migration runner replaces their coordination; readers may remain as
  legacy boundaries until supported installations have crossed the gate.

### 4.21 Audit and activity events

- **Responsibility and types:** `HanlinAuditEvent`, `HanlinAuditSubject`,
  `HanlinAuditOperation`, outcome, redaction class, correlation, and versioned
  payload. User-facing activity is a projection, not the security log itself.
- **Owner:** package event contracts; host audit sink; AgentActivity owns UI
  projection and transcript persistence.
- **Identity/representation:** event ID, timestamp, monotonic sequence within a
  session, correlation IDs, subject/provider/tool/capability, safe outcome, and
  redacted details.
- **Lifecycle/concurrency:** append-only immutable events; actor-owned ordering;
  sink failure must not silently authorize a privileged operation when policy
  requires durable audit.
- **Wire/persistence:** events can cross wire but are redacted before crossing.
  Security audit retention differs from user activity and debug diagnostics.
- **Errors/compatibility:** unknown event versions are preserved or quarantined,
  never projected as success. `AgentEvent`, `AgentRun`, transcript/evidence,
  diagnostics sessions, and trace records remain runtime/UI/diagnostic types;
  adapters emit canonical audit events. They are not deleted until product
  history migration and UI parity are separately approved.

### 4.22 Wire envelopes, negotiation, and errors

- **Responsibility and types:** generalize the current script-only envelope into
  `HanlinWireEnvelope`, `HanlinWireHello`, `HanlinWireNegotiation`, feature IDs,
  ordered event metadata, payload kind registry, and canonical error payload.
- **Owner:** `HanlinPlatformContracts`.
- **Identity/representation:** protocol version, connection/runtime session,
  sequence, optional request/invocation/cancellation correlation, kind, feature
  set, and canonical payload. Session-specific replay rules are explicit.
- **Lifecycle/concurrency:** hello -> negotiated/failed -> active -> draining ->
  closed. Per-direction sequence strictly increases; duplicate/replay handling is
  negotiated; heartbeats do not advance operation state.
- **Wire/persistence:** maximum encoded envelope, payload, depth, collection, and
  stream limits are negotiated up to host hard caps. Envelopes are not persisted
  except bounded diagnostics/audit.
- **Errors/compatibility:** unsupported major/kind/feature, invalid sequence,
  malformed payload, limit, and correlation errors fail closed. Current
  `HanlinScriptEnvelope` is a temporary adapter boundary and is replaced after
  every script/runtime message kind has a typed payload and negotiation tests
  prove version, ordering, cancellation, and error behavior.

### 4.23 Lifecycle and cancellation

- **Responsibility and types:** common operation state, deadline, cancellation
  token identity, cancel request/acknowledgement, terminal reason, and parent/
  child relationship contracts.
- **Owner:** package contracts; each host/provider actor owns its task tree.
- **Identity/representation:** every cancellable operation has a typed operation
  ID and optional cancellation ID; parent session and child operations are
  explicit. `Task` handles never cross the contract boundary.
- **Lifecycle/concurrency:** only declared state transitions are legal; cancel is
  idempotent; cancellation propagates parent-to-child; completion races resolve
  to the first actor-serialized terminal transition; cleanup is awaited.
- **Wire/persistence:** cancellation is wire-capable. Live state is ephemeral;
  terminal outcome and incomplete-operation recovery marker may persist.
- **Errors/compatibility:** cancellation is not generic failure; non-cancellable
  phase and already-terminal acknowledgements are explicit. Current
  `NativeAppSession` task map, MCP lifecycle slots/tasks, install polling task,
  `MCPClientSession.disconnectTask`, and RuntimeCore cancel endpoints remain
  implementation mechanisms. Adapters disappear only when every accepted
  canonical operation has propagation, bounded cleanup, and one-terminal-event
  tests.

## 5. Ownership boundary summary

| Concern | Canonical owner | Live implementation owner |
| --- | --- | --- |
| Portable IDs, versions, values, schemas, descriptors, requests, results, errors, events | `HanlinPlatformContracts` | none |
| Catalog and registration authority | contract values in package | native host actor/service |
| Native app construction, SwiftUI presentation, app sessions | snapshots/contracts in package | `NativeAppPlatform` |
| Native tools and rich chat presentation | descriptor/invocation contracts in package | `NativeAgentExtensions` |
| MCP installation, transport, SDK session, provider discovery | provider contracts in package | `Downstream/MCP` |
| Node/Python/TypeScript/shell execution | runtime/session/execution contracts in package | `Downstream/RuntimeCore` |
| Permission/policy authority and system services | contracts in package | native host brokers/gateways |
| User activity/transcript | audit/activity contracts in package | AgentActivity and app persistence |
| Debug diagnostics | optional diagnostic event contracts | AgentDiagnostics/provider loggers |
| Scripting declarations and compiler reference | compatibility metadata only | `Reference/ScriptingCompatibility` until gates pass |

## 6. Global adapter deletion rule

No adapter is permanent architecture. It may be deleted only when all of the
following are true for its boundary:

1. every producer and consumer uses the canonical contract;
2. persisted records are migrated, rebuildable, or covered by a tested
   read-only legacy decoder with an explicit removal horizon;
3. observable behavior, error mapping, ordering, cancellation, limits,
   settings, and presentation pass parity tests;
4. no direct bypass remains at a privileged service or provider entry point;
5. rollback no longer needs the old writer;
6. telemetry/audit shows no old-format reads for the approved support window;
7. owner approval authorizes removal; and
8. an explicitly requested Xcode/package verification gate validates the exact
   removal commit.

These criteria do not authorize implementation, linkage, migration, or deletion.
