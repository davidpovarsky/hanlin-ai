# Hanlin multi-runtime Scripting adapters

This downstream layer implements the first executable Scripting slice without
changing Native, MCP, or RuntimeCore execution authority.

## Pipeline and pins

Repository and CI fixture preparation uses exactly TypeScript 7.0.2 from
`Scripts/ScriptingCompiler/package-lock.json`. It type-checks a package-local
TypeScript entrypoint and emits the checked JavaScript artifact. The app never
downloads or installs npm packages at runtime.

Original Scripting JavaScript executes in a persistent package-local Apple
JavaScriptCore VM/context. Hanlin-native constrained JavaScript may execute in
the separate bare QuickJS-NG 0.16.1 runtime. The vendored engine is pinned to
commit `954dc53628e36891f93c359aa60895c2ae3dac6b`; its source provenance and
per-file hashes live in `Packages/HanlinQuickJS`.

TypeScript 7.0.2 is used for authoritative host/CI compatibility typechecking.
RuntimeCore's pinned TypeScript 6.0.3 is the authorized on-device project
emitter. Manifest provenance must report both lanes separately; the app does
not claim to run TypeScript 7 on iOS.

## Assistant tool ABI

The supported ABI is `hanlin.script/1.0`. A checked artifact may register up
to 64 execute functions; their stable manifest order is bound to the canonical
tool IDs and is checked when the program loads:

```ts
AssistantTool.registerExecuteTool(async parameters => ({
  success: true,
  message: "result"
}))
```

Input is a canonical `HanlinValue`. Output contains `success: boolean`,
`message: string`, and may contain a canonical structured `data` value.
Invocation resolves the package, installed-package identity, entrypoint, and
tool ID before execution. A package-scoped authorizer checks approval and every
declared capability; the default policy denies privileged calls. Cancellation
propagates into the owning runtime session. Dynamic module loading and binary
values remain unsupported in this legacy ABI; the versioned runtime v2 lane
owns the broader Scripting service protocol.

## Isolation and authority

Each loaded package owns one actor-isolated runtime context. JSC uses public
API only and makes no hard memory/interrupt claim; it uses isolated lifecycle,
bounded bridge values and cooperative cancellation. The QuickJS C wrapper
enforces memory, stack, deadline, cancellation, and result boundaries. Neither
adapter installs filesystem, network, process,
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
