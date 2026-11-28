# Dependency map

## Current application graph

```text
AI_Hanlin app target
├── SwiftUI / SwiftData / Apple frameworks
├── JavaScriptCore.framework
├── NodeMobile.xcframework
├── Python.xcframework
├── IOSSystemLite (local Swift package)
│   ├── IOSSystemStreamBridge
│   └── pinned ios_system binary products
├── MCP 0.12.1
├── SWCompression 4.9.0
├── Logging 1.6.2
├── CoreXLSX 0.14.2
├── RichTextKit 1.2.0
├── LaTeXSwiftUI 1.5.0
├── ZIPFoundation 0.9.19
├── MarkdownUI 2.4.1
├── SwiftSoup 2.8.7
└── LLM 1.8.0
```

The committed SwiftPM resolution contains additional transitive products,
including EventSource, MathJaxSwift, NetworkImage, Swift Atomics,
Swift Collections, SwiftNIO, Swift System, XMLCoder, and documentation
tooling. No duplicate package was added in Phase 0.

## Current source responsibilities

```text
App entry / scenes
├── RuntimeLifecycleBridge -> AppRuntimeCore
├── NativeAppsHubView -> NativeAppRegistry / sessions
└── Mini App WindowGroup -> NativeAppLaunchRequest

RuntimeCore
├── NodeRuntimeService
│   ├── authenticated loopback host
│   ├── TypeScript compiler 6.0.3
│   └── package/runtime mechanics
├── TypeScriptRuntimeService -> NodeRuntimeService
├── JavaScriptCoreRuntimeService -> Apple JavaScriptCore
├── PythonRuntimeService -> Python XCFramework
├── ShellRuntimeService -> IOSSystemLite
└── lifecycle / policy / workspaces / diagnostics

NativeAppPlatform
├── NativeAppRegistry -> built-in modules
├── NativeAppSession / router / launch request
├── NativeCapabilityRegistry
└── storage / network / URL / pasteboard brokers

NativeAgentExtensions
├── NativeToolCatalog -> native and app tool adapters
└── NativeUIBlock -> compact chat result renderer

MCP
├── installer / compatibility / persistence / runtime
└── tool provider integration

AgentActivity
└── provider-neutral activity / evidence / transcript presentation
```

## Target dependency direction

The new platform package begins only after Phase 0:

```text
HanlinPlatformContracts
    <- HanlinPlatformServices
    <- HanlinNativeSDK
    <- HanlinScriptContracts
    <- HanlinScriptRuntime
    <- HanlinScriptUI
    <- HanlinAppCatalog
    <- HanlinTooling

AI_HLY/Downstream/HanlinIntegration
    -> platform targets
    -> existing RuntimeCore
    -> existing NativeAppPlatform
    -> existing NativeAgentExtensions
    -> existing MCP
    -> existing AgentActivity/chat/persistence
```

Actual target edges will be narrower than the linear drawing:

- Contracts depends on Foundation only where required.
- Services depends on Contracts and public Apple frameworks.
- NativeSDK depends on Contracts and service protocols.
- ScriptContracts depends on Contracts.
- ScriptRuntime depends on ScriptContracts and abstract engine/compiler
  protocols, never AI_HLY types.
- ScriptUI depends on ScriptContracts and SwiftUI; it never invokes JS from a
  SwiftUI body.
- AppCatalog depends on Contracts, NativeSDK, and ScriptContracts.
- Tooling depends on Contracts; concrete providers remain downstream.

## Compatibility resources

```text
Authorized local source (import-time only)
    -> Scripts/ScriptingReference importer
    -> Reference/ScriptingCompatibility/Original (single immutable source)
    -> deterministic Generated indexes
    -> Phase 6 HanlinScriptResources packaging
    -> in-app compiler/language service
```

There is no symlink and no production runtime edge back to the Windows source
path. Phase 6 must package resources deterministically from the one repository
source rather than introduce a second manually maintained copy.

## Prohibited dependency inversions

- Platform package targets must not import app models.
- RuntimeCore must not become a universal platform service locator.
- Ordinary script packages must not depend on unrestricted Node.
- ScriptUI must not depend on `NativeUIBlock`.
- MCP must not own a separate permission system.
- Scripts must not receive raw URLSession, FileManager, ModelContext,
  JSContext, Swift objects, or native pointers.
- Extension runtime must not link NodeMobile, Python, shell, or app-only
  services.
