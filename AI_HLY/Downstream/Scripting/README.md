# Hanlin Scripting Phase 2A

This downstream layer implements the first executable Scripting slice without
changing Native, MCP, or RuntimeCore execution authority.

## Pipeline and pins

Repository and CI fixture preparation uses exactly TypeScript 7.0.2 from
`Scripts/ScriptingCompiler/package-lock.json`. It type-checks a package-local
TypeScript entrypoint and emits the checked JavaScript artifact. The app never
downloads or installs npm packages at runtime.

The app executes only a manifest-declared, integrity-checked JavaScript
artifact in a bare QuickJS-NG 0.16.1 context. The vendored engine is pinned to
commit `954dc53628e36891f93c359aa60895c2ae3dac6b`; its source provenance and
per-file hashes live in `Packages/HanlinQuickJS`.

RuntimeCore intentionally remains on TypeScript 6.0.3. Its general-purpose
Node tool is a separate execution product. Updating it is not required to
compile immutable Scripting package artifacts and would expand this phase's
authority and acceptance scope.

## Supported ABI

The supported ABI is `hanlin.script/1.0`, restricted to one call:

```ts
AssistantTool.registerExecuteTool(async parameters => ({
  success: true,
  message: "result"
}))
```

A Phase 2A package declares exactly one `execute` tool. Input is a canonical
`HanlinValue`; output must have exactly `success: boolean` and
`message: string`. Other baseline APIs, multiple tools, binary values, host
capabilities, and dynamic module loading are intentionally unsupported. This
is a deliberate vertical slice, not a claim of full Scripting compatibility.

## Isolation and authority

Each loaded package owns one actor-isolated QuickJS runtime/context. The C
wrapper enforces memory, stack, deadline, cancellation, and result boundaries.
It does not link QuickJS libc or install filesystem, network, process,
environment, secrets, Keychain, UserDefaults, or permission APIs.

Package identity is derived from the validated manifest and artifact digest.
Descriptors are projected into `HanlinCanonicalToolAuthority`, where Native,
MCP, and Script candidates share collision handling with precedence Native,
then MCP, then Script. Execution uses the resolved Script backend route; aliases
are never used as provider identity or as a fallback lookup.

## Targeted verification

The compiler fixture and vendored QuickJS integrity checks run locally without
Xcode:

```sh
npm ci --prefix Scripts/ScriptingCompiler
npm test --prefix Scripts/ScriptingCompiler
```

On a macOS host with the repository's Xcode 26 toolchain, build the test bundle
once and select only the isolated engine suite:

```sh
xcodebuild test \
  -project AI_HLY.xcodeproj \
  -scheme AI_HLY \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>' \
  -only-testing:AI_HLYTests/HanlinQuickJSEngineTests
```

`ScriptingFixtures.bundle` is an opaque test resource. Tests copy a requested
fixture into a fresh temporary directory; no test locates source through
`#filePath` or reads from the checkout at runtime.
