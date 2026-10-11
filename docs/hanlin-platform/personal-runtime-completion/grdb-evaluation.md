# R34 SQLite / GRDB.swift Evaluation (`grdb-evaluation.md`)

## Decision: **KEEP** (`HanlinSQLiteService` over Apple SDK `SQLite3`)

### 1. Executive Summary
Per MASTER Requirement **R34** and scenarios **DB-01 through DB-07**, we evaluated whether migrating `HanlinSQLiteService` (`Packages/HanlinPlatform/Sources/HanlinMiniAppCore/HanlinSQLiteService.swift`) and `HanlinScriptingSQLite` (`Packages/HanlinPlatform/Sources/HanlinScriptingApplicationRuntime/HanlinScriptingSQLite.swift`) to `groue/GRDB.swift` reduces maintenance burden without breaking scripting SQL semantics or adding unnecessary dependency overhead.

**Decision:** **KEEP** the native Apple `SQLite3` implementation in `HanlinSQLiteService` (no half-migrated dual DB layer).

### 2. Quantitative & Architectural Evidence

| Metric | Current `HanlinSQLiteService` (`SQLite3`) | `GRDB.swift` Prototype Assessment |
|---|---|---|
| **Implementation Size (LOC)** | **386 lines** (`HanlinSQLiteService.swift`) | ~310 lines wrapper + ~45,000+ lines external Swift package |
| **External Dependencies** | **0** (uses system `libsqlite3` via `import SQLite3`) | +1 external SwiftPM dependency (`groue/GRDB.swift`) across `HanlinPlatform` and app targets |
| **Dynamic Scripting SQL Surface (`DB-01..05`)** | Direct positional (`?`) and named (`:name`, `@name`, `$name`) parameter binding over `NULL`, `bool`, `int`, `double`, `text`, and `blob`; arbitrary valid SQL statements; explicit `BEGIN` / `COMMIT` / `ROLLBACK` transactions | Requires dynamic `StatementArguments` conversion and raw SQL adapters to avoid leaking `FetchableRecord` / `PersistableRecord` into the JavaScript/Scripting bridge |
| **Security & Sandbox Controls (`DB-01`)** | Built-in per-app root path containment, `maximumOpenDatabases = 16`, `maximumFetchRows = 10_000`, `maximumBindParameters = 1_024`, `maximumStatementBytes = 1_048_576`, WAL + `SQLITE_OPEN_FULLMUTEX` | Still requires custom Hanlin wrapper enforcement for path traversal, handle quotas, and row/byte bounds |
| **Performance (`DB-06`)** | Direct C API prepared statements (`sqlite3_prepare_v2` / `sqlite3_step`) with zero ORM boxing overhead for 1k inserts + 1k-row fetch | Comparable WAL throughput, slightly higher allocation overhead when boxing dynamic scripting rows into `[String: HanlinScriptingValue]` |

### 3. Rationale
1. **Dynamic Bridge Fit:** Hanlin's scripting runtime executes arbitrary user/skill SQL queries with dynamic parameter lists and returns untyped JSON/scripting dictionaries. GRDB's primary value proposition (compile-time Swift record mapping, `ValueObservation`, schema migrators for app models) is not used by the dynamic scripting bridge.
2. **Zero Maintenance Reduction:** Because handle quotas, root directory traversal checks, row limits, and `[String: Any]` column extraction must remain in Hanlin's bridge regardless, wrapping GRDB saves fewer than 80 lines of code while adding a large third-party dependency.
3. **Single Authoritative Layer:** In accordance with `DB-07`, Hanlin retains a single authoritative SQLite implementation (`HanlinSQLiteService`) with zero dual-database layers.
