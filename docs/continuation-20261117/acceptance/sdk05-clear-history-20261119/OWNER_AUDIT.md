# SDK05 original storage and lifecycle owner audit

Task: https://app.asana.com/1/1219597879016953/task/1220542199999956
Inspected source: 1480b347f519073b384cd86f7efc506e9c2d1aab.

## Existing owners

| Concern | Actual owner | Observed boundary |
| --- | --- | --- |
| SwiftData / CloudKit | AppDataManager in AI_HLY/AI_HLY.swift | One original ModelContainer. Production configuration uses CloudKit .automatic. Tests and acceptance fixtures disable it. |
| User identity | UserInfo model / UserInfoView | Personalization fields; no authentication or account identity. No login/logout/account switch service or CKAccountChanged observer was found in app Swift source. |
| SDK namespace | HanlinAppAgentSessionOwner.namespace and cold origin reconstruction | Fixed app=hanlin, account=local-personal-library, workspace=swiftdata/temporary, space=conversation UUID. This is not verified iCloud account isolation. |
| Canonical transcript | HanlinAppConversationStore | Adapter of the same original ChatRecords row. CAS applies to agentSDKRecordData; no second application database is introduced. |
| Visible messages | ChatView, ListView and ChatRecords.messages | Clear history previously removed only ChatMessages. Whole-chat delete removes ChatRecords; the relationship cascades to messages. Saved excerpts intentionally have independent scalar references. |
| Memory | APIManager / MemoryArchive / UserInfo flags | Legacy rows contain no account or Space provenance. Typed global read requires existing opt-in; namespace replacement is explicitly unsupported. |
| AI/search/tool credentials | APIKeys, SearchKeys, ToolKeys, APIManager and original feature-specific callers | Plain String key fields remain in SwiftData. All three models belong to the original CloudKit-enabled schema. The typed resolver does not move or encrypt these fields. |
| Runtime credentials | RuntimeEnvironmentSecretStore | Host-owned Keychain service com.itorah.chavrusachat.runtime, opaque reference as account. No package-supplied access group. The new durability fix preserves referenced secrets across failed registry saves. |
| MCP credentials | MCPSecretStore / MCPRuntimeProvider / MCPServerRegistryStore | Host-owned Keychain service com.itorah.chavrusachat.mcp, opaque reference as account. Conservative reference retention is distinct from complete account erasure. |
| Backup / rollback | Original context save behavior; Runtime/MCP registry recovery; package private-store checkpoints | Private SDK file-store checkpoint helpers do not establish backup/rollback of the app's SwiftData/CloudKit container. Existing chat exports are presentation/interchange exports, not a full canonical/account backup. |

## Bounded repair supplied

sdk05-clear-history-fix.diff corrects the existing clear-history action through its current owner and original row. It adds an empty canonical revision barrier, preserving CAS against late initial or later writes, and actual SwiftData rollback/reopen regressions. See PROPOSAL.md. No account schema or migration is invented.

## Remaining concrete acceptance gates

1. Actual account lifecycle. The app has no defined account/logout/switch source event. One must not label its local-personal-library namespace as per-iCloud-account isolation or wire a fabricated identity into it.
2. CloudKit owner and account changes. AppDataManager does not fence or reopen the container on authenticated iCloud identity changes. Resolving account status alone would not prove that old local rows, requests or caches are isolated after a switch.
3. Automatic App Group location. Apple documents that ModelConfiguration's default groupContainer is .automatic and that automatic uses the primary app group. Hanlin and the MiniApps companion both declare the same two group identifiers. Therefore the production store's actual resolved location and exposure need a signed observation. Changing groupContainer to .none without an explicit migration would risk silently presenting a new empty database and is not proposed.
4. Host credential migration. Existing APIKeys/SearchKeys/ToolKeys string fields are part of the SwiftData schema. A reversible migration has to cover their actual writers/readers, including Vision/TTS/model discovery, durable references, restore behavior, and CloudKit replicas. The typed port alone does not satisfy host-owned Keychain persistence.
5. Full deletion and concurrent views. The bounded clear patch does not claim to clear every mounted window's retained presentation/input cache, all histories, saved excerpts, models, Skills, runtime files, backups or credentials. It also does not claim physical SQLite/WAL sanitization. A full erase action needs its own explicit ownership and recovery contract.
6. Protection and signed operation. Source entitlements and .completeFileProtection on some registries are not evidence that every SwiftData sidecar, export, attachment or shared container has the intended physical protection. Actual signed entitlements, locked-device access, CloudKit behavior and App Group isolation remain native/device checks.
7. Backup/restore. Package-local checkpoints and registry backup files are narrower than app-wide canonical-history/account recovery. The original export route must not be reported as a complete SDK/CloudKit backup without matching canonical record and attachment provenance.

## Primary API evidence

The five exact official DocC documents and SHA256 hashes are retained in official-api/receipt.json. In particular:

- https://developer.apple.com/documentation/swiftdata/modelconfiguration/init(_:schema:isstoredinmemoryonly:allowssave:groupcontainer:cloudkitdatabase:)
- https://developer.apple.com/documentation/swiftdata/modelconfiguration/groupcontainer-swift.struct/automatic
- https://developer.apple.com/documentation/swiftdata/modelconfiguration/init(_:schema:url:allowssave:cloudkitdatabase:)
- https://developer.apple.com/documentation/swiftdata/modelcontext/rollback()

All source observations are tied to the hashed files in audit-source-manifest.json. No account service, destructive migration, external sign-out, key deletion or production data operation was performed.
