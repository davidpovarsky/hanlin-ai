# Canonical Contract Cutover Sequence

Status: ordered implementation plan only. No stage is authorized by this document.

The sequence deliberately keeps app linkage and behavior changes after the
portable model and persistence evidence exist. A stage may proceed only when its
stop/go criteria pass and owner approval names that stage.

## Stage 0 — Approve and record architecture

- **Prerequisites:** review this complete design set; resolve or explicitly
  defer blocking decisions CCD-018 through CCD-021.
- **Expected changes:** `docs/hanlin-platform/adr/**` and decision docs only.
- **Persisted-data risk:** none.
- **Behavior risk:** none.
- **Required tests:** documentation cross-links and source-evidence review.
- **Adapter introduced:** none.
- **Adapter deletion condition:** not applicable.
- **Stop/go:** stop on disagreement over canonical home, value losslessness,
  provider-qualified tools, or permission non-authority. Go only with owner
  acceptance and explicit Stage 1 authorization.

## Stage 1 — Evolve package primitives (recommended first slice)

- **Prerequisites:** Stage 0; approve numeric encoding, limits, schema split,
  and identity grammar.
- **Expected changes:**
  `Packages/HanlinPlatform/Sources/HanlinPlatformContracts` value/schema,
  identity, version, error, and wire files; package tests/fixtures; manifest
  schema only as required. No app/project linkage.
- **Persisted-data risk:** none currently known; package is unlinked and no
  product store uses its encoding. Recheck before changing format.
- **Behavior risk:** none to app; contract API/fixture churn inside package.
- **Required tests:** deterministic golden/randomized value tests, duplicate-key
  decoder, schema unknown-keyword preservation/projection, limits, identifiers,
  error round-trip, wire negotiation/order/cancellation. On explicit verification
  request, Swift package and iOS/macOS Xcode compilation.
- **Adapter introduced:** optional package-local v1 fixture decoder only if a
  real consumer is discovered.
- **Adapter deletion condition:** no external/persisted v1 consumers and all
  fixtures regenerated/approved.
- **Stop/go:** stop on any silent loss or ambiguous canonical bytes. Go when the
  package specification and tests are internally complete.

## Stage 2 — Add missing canonical domain contracts

- **Prerequisites:** Stage 1.
- **Expected changes:** new package files for package/catalog/instances,
  launch/session/runtime, route/action requests, permissions/policy/services,
  tool invocation, script execution, persistence/migration, audit, and lifecycle.
  Package tests only.
- **Persisted-data risk:** none.
- **Behavior risk:** none to app; risk of premature abstraction.
- **Required tests:** state machines, Codable/Sendable/static API tests, invalid
  transitions, error/version compatibility, permission truth tables, provider
  identity/collision fixtures.
- **Adapter introduced:** none.
- **Adapter deletion condition:** not applicable.
- **Stop/go:** stop if a contract requires UI/framework/SDK/path/secret values or
  leaves ownership ambiguous. Go with a coherent package-only graph.

## Stage 3 — Freeze persistence fixtures and build migration readers

- **Prerequisites:** Stages 1-2; approved persistence classifications and grant
  storage policy.
- **Expected changes:** subsystem test fixtures and downstream migration/readers
  in new separated adapter/migration directories; no authoritative writer switch.
  Likely MCP registry/chat selection, runtime environment/approvals, native
  UserDefaults, tool settings, and app-persistence test support.
- **Persisted-data risk:** low while read-only; fixture capture may expose
  secrets, so all samples must be synthetic/redacted.
- **Behavior risk:** none if readers remain shadow-only.
- **Required tests:** every current schema/corruption/backup case, deterministic
  migration, counts/hashes, missing secrets/packages, rollback generation,
  SwiftData model-store fixture planning.
- **Adapter introduced:** legacy persisted-record readers and field mappers.
- **Adapter deletion condition:** all supported records migrated or approved for
  reset, zero legacy reads for support window, rollback window closed.
- **Stop/go:** stop if a store cannot be classified or rollback cannot restore
  authority. Go when migrations can be proven without writing live data.

## Stage 4 — Link contracts and publish read-only shadow snapshots

- **Prerequisites:** Stages 1-3; explicit app-link authorization.
- **Expected changes:** `AI_HLY.xcodeproj`/package reference and minimal imports;
  new downstream adapters for NativeAppRegistry, NativeToolCatalog, MCP catalog/
  runtime, RuntimeCore snapshots, and activity/audit projection. No provider
  execution or persistence writer changes.
- **Persisted-data risk:** none; shadow reads only.
- **Behavior risk:** app startup/performance/concurrency and upstream merge
  integration risk.
- **Required tests:** snapshot parity, no extra runtime starts, no catalog order/
  alias changes, actor/main-actor boundaries, launch-time performance. Explicitly
  requested Xcode verification required before merge.
- **Adapter introduced:** native/MCP/runtime shadow snapshot adapters.
- **Adapter deletion condition:** canonical snapshots become sole cross-subsystem
  consumer inputs; implementation registries remain provider-local.
- **Stop/go:** stop on behavior, ordering, startup, or actor-isolation difference.
  Go only when shadow output matches live sources.

## Stage 5 — Canonical tool routing with native provider

- **Prerequisites:** Stage 4; tool model approved; settings migration reader.
- **Expected changes:** new canonical routing table/catalog composition and native
  provider adapter, narrow APIManager/AssistantToolBridge connection, settings
  key migration in separated downstream files.
- **Persisted-data risk:** native tool enablement/group configuration.
- **Behavior risk:** high: model schemas, alias resolution, results, UI/activity,
  recursive model loop.
- **Required tests:** all native aliases/schemas/results, native-first behavior,
  disabled tools/groups, persisted settings, presentation/activity parity,
  cancellation/limits. Xcode app verification only if explicitly requested.
- **Adapter introduced:** canonical-to-`NativeTool` invocation/result adapter.
- **Adapter deletion condition:** native tools directly use canonical request/
  result and no model/request path consumes legacy schema/results.
- **Stop/go:** stop on any observable tool/schema/result difference. Go after
  parity plus rollback of settings writer is proven.

## Stage 6 — MCP provider routing and installed-instance split

- **Prerequisites:** Stage 5; Stage 3 MCP fixtures; exact MCP SDK value behavior
  verified; migration/rollback approved.
- **Expected changes:** MCP provider adapter, canonical tool descriptor/value
  mapping, installed package/provider configuration split, registry migration
  writer, current MCP runtime implementation retained.
- **Persisted-data risk:** high: server registry, chat selections, env/Keychain
  references, installed package paths.
- **Behavior risk:** high: install/start/stop/restart, lazy discovery, naming,
  selection, content rendering, error mapping.
- **Required tests:** current schema-0/1 and backup repair, install commit/
  rollback, paths, secrets, selections, exact alias collisions, all MCP content,
  server lifecycle/cancellation/tool-list changes, full rollback. Explicit Xcode
  and runtime/MCP verification only on user request.
- **Adapter introduced:** canonical MCP provider plus legacy registry/path reader.
- **Adapter deletion condition:** migrated store authoritative, support window
  passes with zero old reads, rollback closed, MCP runtime consumes split records.
- **Stop/go:** stop on data mismatch, missing secret/package, alias change, or
  provider lifecycle regression. Go only per-server after verified commit.

## Stage 7 — Canonical permission broker and enforcement

- **Prerequisites:** Stages 2-6; owner decisions on prompt UX, local/sync grants,
  audit retention; complete privileged-service inventory.
- **Expected changes:** new downstream permission/policy/audit services; minimal
  integration into native service brokers and provider execution gateways;
  protected grant/revocation store and migrations if needed.
- **Persisted-data risk:** high security state. Existing lifecycle approvals must
  remain isolated.
- **Behavior risk:** high: prompts/denials and previously unguarded operations.
- **Required tests:** permission lifecycle truth table, every service bypass,
  redirects/scopes, OS authorization, revocation/expiry/update/uninstall,
  audit failure, concurrent prompts, rollback.
- **Adapter introduced:** NativeCapability declaration adapter and current broker
  facade over canonical enforcement.
- **Adapter deletion condition:** no privileged bypass; all declarations/scopes
  canonical; legacy statuses unused; grant store stable and verified.
- **Stop/go:** stop on any false allow, lost grant/revocation, prompt loop, or
  unclassified service. Go capability-by-capability, fail closed.

## Stage 8 — Canonical app/route/action/session boundary

- **Prerequisites:** Stages 4 and 7; descriptor/catalog/session contracts stable;
  NativeUI persisted action migration plan.
- **Expected changes:** downstream native manifest/module binding, canonical
  launch/route/action adapters, host session controller, minimal WindowGroup/
  Apps Hub integration; native SwiftUI modules remain.
- **Persisted-data risk:** native app data namespaces and persisted NativeUI
  actions/routes.
- **Behavior risk:** high: navigation, multiple windows, dismissal/task cleanup,
  built-in tools/apps.
- **Required tests:** all built-ins, searches/settings/routes/actions, window and
  sheet presentation, session close/cancel, app storage migration, historical
  NativeUI decoding, accessibility/UI checks plus requested Xcode verification.
- **Adapter introduced:** NativeAppManifest/module binding and legacy route/action
  decoders.
- **Adapter deletion condition:** validated canonical descriptors drive catalog/
  launch; all live requests canonical; persisted legacy readers meet retirement
  criteria; NativeAppSession responsibilities transferred.
- **Stop/go:** stop on any data/navigation/presentation/task-cleanup difference.

## Stage 9 — Canonical activity/audit and persistence writer transition

- **Prerequisites:** Stages 5-8; audit retention/export approved; historical
  activity reader plan.
- **Expected changes:** canonical audit sink and AgentActivity projection;
  optional new versioned activity persistence writer; diagnostics remain
  separate.
- **Persisted-data risk:** chat history, agent runs, rich UI blocks, audit data.
- **Behavior risk:** high: transcript/evidence/presentation and privacy.
- **Required tests:** schema-4 history, all event/result types, redaction,
  retention, projection parity, corrupt/unknown records, rollback and export.
- **Adapter introduced:** canonical-audit-to-AgentActivity/UI projection and old
  history reader.
- **Adapter deletion condition:** product no longer writes old schema; supported
  history reads/migrates; UI parity; retention horizon/owner approval reached.
- **Stop/go:** stop on lost history, leaked sensitive data, or changed transcript.

## Stage 10 — Scripting implementation (separate authorization)

- **Prerequisites:** SG-0 through the applicable gates in
  `SCRIPTING_INTEGRATION_GATES.md`, including compiler decision.
- **Expected changes:** new downstream/provider/runtime/package targets and
  minimal approved registration bridges; reference originals stay immutable.
- **Persisted-data risk:** new script source/settings/secrets/packages; no legacy
  script store currently exists in Hanlin.
- **Behavior risk:** very high: untrusted code, system services, resource use,
  platform extensions.
- **Required tests:** every Scripting gate and explicit Xcode/runtime verification.
- **Adapter introduced:** Scripting declaration/host/provider bindings.
- **Adapter deletion condition:** generated bindings may replace temporary
  mappings only after exact compatibility matrix proof; canonical provider
  boundary remains permanent, not an adapter.
- **Stop/go:** stop until explicitly authorized. Never infer permission from the
  authorized reference snapshot.

## Stage 11 — Legacy writer/adapter retirement

- **Prerequisites:** all relevant prior stages; telemetry/support window; owner
  removal approval; rollback window closed.
- **Expected changes:** delete old writers, then readers/adapters/types; narrow
  cleanup only, with no unrelated refactor.
- **Persisted-data risk:** highest if premature.
- **Behavior risk:** merge and missed-consumer risk.
- **Required tests:** full parity/regression/migration suite, static call-site
  proof, clean old-store fixture launch, and explicitly requested Xcode build/
  tests on exact commit.
- **Adapter introduced:** none.
- **Adapter deletion condition:** global eight-point rule in
  `CANONICAL_CONTRACT_MODEL.md` plus each type-specific condition.
- **Stop/go:** stop on any legacy read, unsupported store, rollback need, direct
  bypass, or test gap. Go one adapter family at a time.

## Upstream merge posture

New canonical contracts stay in the downstream package; adapters/migrations stay
under clearly named downstream directories. NativeAppPlatform,
NativeAgentExtensions, MCP, and RuntimeCore are downstream-owned implementation
areas. Unavoidable upstream-derived edits should be limited to package linkage,
composition-root registration, APIManager routing hook, WindowGroup/Apps Hub
launch hook, and persistence model/schema connections, each documented at its
stage. No stage authorizes broad reformatting or refactoring of upstream files.

