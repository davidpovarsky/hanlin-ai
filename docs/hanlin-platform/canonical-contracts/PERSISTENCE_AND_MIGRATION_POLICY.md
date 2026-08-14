# Persistence and Migration Policy

Status: proposed classification and cutover policy; no store is changed.

## 1. Categories and default treatment

| Category | Meaning | Default treatment |
| --- | --- | --- |
| User data | User-created/curated content or history whose loss changes the product | Preserve; migrate transactionally; rollback required |
| Secret | Credentials, tokens, or secret environment values | Preserve in protected credential store; never log/export inline; verified migration and rollback required |
| Installed state | Locally installed packages/models/runtimes and identity needed to use or uninstall them | Preserve/reconcile when costly/non-reconstructible; rebuild only with proof and consent where redownload is material |
| Configuration | User choices, enablement, provider setup, retention, environment and security decisions | Preserve when meaningful; migrate keys/IDs; reset only obsolete development-only settings |
| Cache/reconstructible | Derived data that can be recreated without user loss | Rebuild/reset; no format compatibility |
| Diagnostic/recovery | Logs, audit/debug evidence, migration checkpoints, backups | Bounded retention; preserve only through the recovery/support window |

Security approvals are configuration/security decisions, not ordinary cache.
Effective permission snapshots are cache; grants/revocations are durable security
records.

## 2. Store inventory and disposition

### 2.1 SwiftData/CloudKit model container

Current store: `ModelContainer` with CloudKit automatic in `AI_HLY.swift`,
containing `ChatMessages`, `ChatRecords`, `KnowledgeRecords/KnowledgeChunk`,
`MemoryArchive`, `PromptRepo`, `TranslationDic`, `UserInfo`, `AllModels`,
`APIKeys`, `SearchKeys`, and `ToolKeys`.

| Records | Classification | Decision | Migration/recovery |
| --- | --- | --- | --- |
| Chats/messages, canvas, attachments, agent run JSON, native UI JSON | User data | Preserve. Do not eagerly rewrite historical embedded JSON. | Add versioned readers/adapters first. Any SwiftData schema change requires an explicit migration plan, fixture copy, count/hash verification, CloudKit consideration, and rollback/export checkpoint. |
| Knowledge records/chunks/vectors | User data; vectors partly reconstructible | Preserve text/metadata; vector bytes may rebuild only from preserved source with approved model/version policy. | Migrate metadata transactionally; quarantine corrupt vectors and re-embed rather than dropping the record. |
| Memory, prompts, translation dictionary, user profile/preferences | User data/configuration | Preserve. | SwiftData migration plus semantic fixture verification. |
| Model/provider catalog choices | Configuration | Preserve meaningful user choices; system-provisioned defaults may rebuild. | Map IDs explicitly; never guess a provider on collision. |
| `APIKeys`, `SearchKeys`, `ToolKeys` key fields | Secret mixed into SwiftData records | Preserve, but future canonical ownership is a Keychain credential store with non-secret metadata in SwiftData. | Copy to Keychain, read-back verify, atomically switch references, retain encrypted/rollback checkpoint for the approved window, then clear old secret field only after success. CloudKit exposure/history must be assessed before implementation. |

`AgentRun.currentSchemaVersion = 4` and `NativeUIBlock` JSON are
`PERSISTED_LEGACY_BOUNDARY`. Keep readers until supported chat history has been
migrated or owner-approved retention makes old history irrelevant. Do not infer
deletability from lexical use.

### 2.2 Native app UserDefaults

| Keys/store | Classification | Decision | Migration/recovery |
| --- | --- | --- | --- |
| `nativeapp.sefaria.saved` | User data | Preserve/migrate. | Decode fixture and record count/content hash; leave old key until new write verified. |
| Sefaria recent queries | User data/history (small) | Preserve unless owner explicitly classifies as disposable. | Direct key migration; rollback by retaining old key. |
| Sefaria language | Configuration | Preserve. | Map enum explicitly. |
| `nativeapp.wikipedia.saved` | User data | Preserve/migrate. | Same transactional key policy. |
| Wikipedia recent queries | User data/history (small) | Preserve by default. | Same. |
| Wikipedia language | Configuration | Preserve. | Explicit value mapping. |
| `nativeapp.<id>.persistent.draft/history` for TextStudio | User data | Preserve/migrate. | Validate decoded draft/history before switching namespace. |
| `nativeapp.<id>.persistent.*` generic broker | Unknown-by-key; owner-declared user data/configuration | Preserve until each app publishes a storage manifest/classification. | No bulk reset. Inventory keys per app; migrate owner namespace and quota. |
| `nativeapp.<id>.cache.*` | Cache/reconstructible | Rebuild/reset. | Clear only validated namespace; no data migration. |

The current direct Sefaria/Wikipedia stores and generic broker use overlapping
namespace conventions. Canonical ownership requires one app storage namespace
per stable installed/app identity; adapters read both during cutover.

### 2.3 Native tool settings

Current keys: `toolEnabled.<name>`, `toolGroupEnabled.<app-id>`, and
`assistantTools.canonicalNameMigration.v1`.

Classification: configuration. Preserve enabled/disabled choices and group
choices. Migrate to provider-qualified logical tool identity keys. The existing
legacy name migration marker is diagnostic/configuration evidence and may be
removed after every supported installation has passed the new migration and no
old keys remain. Rollback retains a mapping snapshot and old values for one
release/support window.

### 2.4 MCP stores

| Store | Classification | Decision | Migration/recovery |
| --- | --- | --- | --- |
| `MCPServerRegistry.json` + backup | Mixed installed state, configuration, local path, compatibility/cache | Preserve and split. | Preflight both copies, select verified highest generation, checkpoint bytes/hash, migrate each descriptor into installed package + provider configuration. Verify package identity/path/integrity and counts. Roll back from checkpoint. Keep schema-0/1 reader until no supported old registry remains. |
| MCP package directories | Installed state, excluded from backup | Preserve/reconcile; do not assume redownload is harmless. | Verify directory containment, package/version/integrity/entry point. Quarantine orphan/corrupt directories; never delete during registry migration. |
| Absolute `packageRoot`/`entryPoint` | Runtime resolution data embedded in legacy store | Migrate to relative logical entry plus installed-instance identity; rebuild absolute paths. | Existing path resolver remains legacy adapter. Fail/quarantine on escape/missing path. |
| Compatibility report and cached tool count | Cache/reconstructible | Rebuild after migration. | No compatibility preservation; keep only as diagnostic of old install if useful. |
| Global/new-chat/autostart flags, arguments, non-secret env | Configuration | Preserve. | Field-by-field mapping; unknown fields retained in legacy checkpoint, not silently discarded. |
| `MCPChatSelections.json` | Configuration/user-to-provider association | Preserve. | Version new document, map chat/server UUIDs to canonical instance IDs, keep unknown/missing references as disabled tombstones until user resolves. Atomic write + backup. |
| `MCPFeatureConfiguration.json` | Configuration | Preserve enabled/debug flags. | Simple versioned migration; corrupt file may reset to safe disabled default with recovery report. |
| MCP Keychain service | Secret | Preserve/migrate references, not values in JSON. | Read/write verification per reference; do not delete source item before every referencing record commits. Rollback mapping required. |
| MCP runtime log/current previous log | Diagnostic | Rotate/reset; no migration. | Retain only per approved diagnostic policy; redaction verification. |
| `MCPInstalledPackageManifest` declaration | No verified current persisted producer | DELETE_CANDIDATE, not a store. | Delete only after compiler/static call-site verification confirms no format or installer contract uses it and canonical installed record covers the intended role. |

### 2.5 RuntimeCore stores

| Store/path | Classification | Decision | Migration/recovery |
| --- | --- | --- | --- |
| `HanlinRuntime/v1/registry/RuntimeEnvironment.json` | Configuration with secret references | Preserve/migrate. | Version record; map scopes/IDs; Keychain read-back; atomic verified write; rollback bytes. |
| Runtime Keychain service | Secret | Preserve. | Same reference-safe migration as MCP; eventual unified credential store may import both service namespaces. |
| `LifecycleApprovals.json` | Configuration/security decision bound to exact package/version/integrity/script hash | Preserve for current lifecycle behavior only; do not convert to capability grants. | Version and import as lifecycle policy approvals only. Reset an entry on any bound-value or compiler/execution-policy change. Backup/rollback required. |
| Node global/Python/MCP package directories and Python registry | Installed state | Preserve/reconcile; rebuild registries only from verified installed metadata. | Transactional staging/candidate/backup already informs the future migration design. Verify package counts/hashes; quarantine ambiguity. |
| Runtime bundled Node/Python/host resources | Installed/reproducible app state | Rebuild from signed/bundled resources. | No user migration; versioned host destination may reset after bundle verification. |
| `clients/**` workspaces | Potential non-reconstructible user/execution state | Preserve until each client publishes ownership/retention. | Never blanket-clear. Inventory by client/identifier; migrate/quarantine with containment checks. |
| npm/PyPI/TypeScript caches | Cache/reconstructible | Rebuild/reset. | Safe validated descendant deletion only. |
| staging/tmp/ready markers | Cache/recovery transient | Reset after recovery inspection. | Clean only validated paths; incomplete install/migration checkpoints handled first. |
| runtime/shell logs and smoke/acceptance artifacts | Diagnostic/recovery | Reset/retain bounded evidence as policy requires. | No schema migration. |
| `RuntimeDependencies.lock.json` | Repository build/install manifest, not user store | Keep repository-owned; version changes require runtime verification. | No device migration contract beyond installed bundle reconciliation. |

### 2.6 Agent diagnostics and native tool traces

`Documents/Diagnostics/Hanlin-Chat-*.jsonl`, agent-session JSON/text, MCP logs,
and shell/runtime logs are diagnostic/recovery state. They are not canonical
audit authority and may contain sensitive derived data even after redaction.

Decision: no format migration. Apply bounded retention, explicit user export,
redaction tests, file protection, and reset on incompatible format. Preserve only
active migration/recovery evidence and user-requested exported files. Diagnostics
level/retention UserDefaults are configuration and should be preserved.

### 2.7 Local models and temporary exports

- `Application Support/LocalModels/*.gguf`: installed state with material
  download cost; preserve, reconcile by file identity/hash, never clear during
  contract cutover.
- temporary chat exports, audio files, download locations, smoke files: cache/
  transient; clean using existing scoped ownership. User-exported destinations
  are user data outside platform migration ownership.

## 3. Canonical ownership rules

Every future durable record declares owner namespace, category, schema version,
record ID, timestamps, backup/sync class, sensitivity, quota, and migration
strategy. Portable descriptors do not persist themselves. Store implementations
remain subsystem-owned; the package defines only record/envelope semantics.

Secrets are stored only in a credential service and referenced by opaque IDs.
Absolute paths are derived locally and never canonical. Runtime snapshots,
effective permissions, tool counts, compatibility probes, and provider discovery
are caches. Grants, decisions, revocations, lifecycle approvals, installed
identity, and user configuration are durable.

## 4. Migration transaction

Every nontrivial migration follows:

1. **Preflight:** supported source schema, readable store, available space,
   contained paths, credential accessibility, record inventory.
2. **Checkpoint:** immutable source bytes/store export, hashes, counts, schema,
   app/build version, and migration ID.
3. **Transform:** deterministic field mapping into a separate destination; no
   in-place destructive rewrite.
4. **Verify:** decode destination, referential integrity, counts, semantic
   fixtures, hashes where meaningful, package/path/integrity checks, and secret
   read-back without logging values.
5. **Commit:** atomic pointer/schema switch; record report and audit event.
6. **Observe:** keep old reader/checkpoint for approved rollback window and
   measure legacy reads.
7. **Retire:** delete old writer first, then reader/checkpoint only after adapter
   deletion criteria and owner approval.

If transformation or verification fails, leave source authoritative and
quarantine the candidate. If commit partially fails, restore the checkpoint.
Migration cancellation is allowed only before commit or at an explicitly safe
checkpoint.

## 5. Recovery behavior

- Corrupt user data is quarantined and surfaced; never replaced with empty
  success silently.
- Cache corruption resets/rebuilds with a diagnostic report.
- Mixed primary/backup stores select only a fully decoded, supported document;
  generation plus verified content decides freshness.
- Unknown future schema is not downgraded. Preserve bytes and stop.
- Orphaned installed payload is quarantined/reconciled, not immediately deleted.
- Missing secrets leave configuration disabled/actionable; they do not fabricate
  empty credentials.
- Rollback does not resurrect revoked grants or stale security state without an
  explicit security reconciliation step.

## 6. Required tests

Golden fixtures for every current store/version, corrupt/truncated/unknown
versions, primary/backup permutations, key/ID collisions, missing packages and
secrets, CloudKit/SwiftData migration fixtures, count/hash verification, low
disk, cancellation safe points, crash at every stage, rollback, repeated
idempotent migration, path/symlink escape, and legacy-reader telemetry.

No migration ships on the basis of static documentation alone. Xcode/SDK tests
and device/simulator storage behavior require a separately requested verification
task.

