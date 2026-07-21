# Hanlin RuntimeCore

RuntimeCore is the downstream, app-owned execution layer shared by assistant tools, MCP, package screens, and future automation clients. MCP remains responsible for MCP descriptors, sessions, per-chat selection, protocol traffic, and server-facing UI; it consumes the single Node process owned here.

## Ownership boundaries

- `Core` owns versioned storage, execution policy, runtime state, diagnostics, and the process-wide coordinator.
- `Node` owns the single Node.js Mobile process, authenticated loopback host, generic script workers, TypeScript, and package mechanics.
- `Python` owns the single embedded CPython interpreter and pure-Python package installation.
- `JavaScriptCore` owns isolated lightweight JavaScript contexts.
- `Shell` owns the serialized, allow-listed ios_system environment.
- `Environment` owns scoped variables and Keychain-backed secret references.
- `Tools` adapts typed runtime APIs to the existing `NativeToolCatalog` and `AgentActivity` presentation system.
- `UI` presents shared runtime state and global packages. MCP-specific settings remain under `Downstream/MCP`.

All downloaded packages, generated code, caches, logs, and workspaces live below `Library/Application Support/HanlinRuntime/v1`. Runtime code never treats the app-container root as `HOME`, and every execution receives a validated client workspace.

`RuntimeDependencies.lock.json` is the source of truth for immutable runtime inputs. `Scripts/Runtime/generate-runtime-manifest.mjs` creates the bundled diagnostics manifest from it. A null binary hash means that source pins have been inspected but the required Xcode build and embedded smoke test have not yet verified the binary; normal IPA preparation must reject that state.

The original `PistonExecutor` and `execute_python_code` path are outside RuntimeCore and remain unchanged. Embedded Python is exposed separately as `execute_local_python_code`.
