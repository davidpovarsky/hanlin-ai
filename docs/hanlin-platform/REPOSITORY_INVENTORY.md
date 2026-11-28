# Repository inventory

Inventory date: 2026-07-23
Repository root: `C:\Users\DAVID\Code\hanlin-ai`
Origin: `https://github.com/davidpovarsky/hanlin-ai.git`
Branch: `codex/fix-mcp-reachable-compatibility`
Pre-Phase-0 HEAD: `6209369`

## Git and ownership

- The requested branch matched the checkout and its origin tracking branch.
- Before Phase 0, the repository had 713 tracked files.
- The branch was 115 commits ahead of `origin/main` and 0 behind.
- The branch changed 365 paths relative to `origin/main`.
- `recovery-state-before.txt` was an existing untracked user file and remains
  untouched.
- No `upstream` remote is configured.
- The README identifies `https://github.com/CherryHQ/hanlin-ai` and instructs
  cloning it; the root commit is the original Chinese AI Hanlin release.
  Therefore this checkout is treated as a downstream derivative. The exact
  current divergence from CherryHQ cannot be proven from configured local
  remotes.

Ownership policy:

- Existing app sources and project files are upstream-derived.
- Existing `AI_HLY/Downstream` systems are established downstream layers.
- Phase 0 additions under `Reference/ScriptingCompatibility`,
  `Scripts/ScriptingReference`, and `docs/hanlin-platform` are new downstream
  files.
- Phase 0 modifies no existing app, project, workflow, entitlement, signing,
  bundle identifier, or runtime file. It adds two narrow `.gitignore`
  negations so the authorized compiler and example `tsconfig.json` inputs are
  versioned despite the existing broad `*config.json` rule.

## Apple project

| Item | Verified value |
| --- | --- |
| Project | `AI_HLY.xcodeproj` |
| App target | `AI_Hanlin` |
| Shared scheme | `AI_HLY` |
| Products | one iOS application |
| Platforms | iPhone and iPad |
| Deployment target | iOS 26.0 |
| Swift language setting | 6.0 |
| Approachable concurrency | enabled |
| Extension targets | none |
| Extension embedding | empty ExtensionKit phase |
| Build configurations | Debug, Release |

The scheme builds the application for testing, running, profiling, archiving,
and analysis. No test target is currently attached to its test action.

The app target links these direct Swift package products:

- MCP;
- SWCompression;
- Logging;
- CoreXLSX;
- RichTextKit;
- LaTeXSwiftUI;
- ZIPFoundation;
- MarkdownUI;
- SwiftSoup;
- LLM;
- local IOSSystemLite.

It also links Apple JavaScriptCore and embeds NodeMobile and Python
XCFrameworks. `IOSSystemLite` uses Swift tools 6.2, targets iOS 26, and wraps
eight pinned binary targets plus its Objective-C stream bridge.

## CI and build workflows

Existing workflows:

- `build-ios26-unsigned-ipa.yml`: manual dispatch and existing `push` trigger
  on `main`; `macos-26`; scheme `AI_HLY`; Release; deployment target 26.0;
  pinned Node 24.5.0; selects the newest installed Xcode 26, preferring 26.6.
- `build-runtime-bundle.yml`: manual/reusable split runtime build; Ubuntu and
  macOS 26 jobs; selects newest installed Xcode 26 where required.
- `check-runtime-dependency-updates.yml`: manual and scheduled dependency
  update workflow.

Phase 0 did not run or alter any workflow. Phase 1 validation later adds one
default-false manual-only mode to the already registered iOS workflow because
GitHub cannot dispatch a brand-new workflow that exists only on a feature
branch. Existing automatic triggers and existing build commands remain
unchanged.

## Runtime dependency pins

`RuntimeDependencies.lock.json` records:

| Runtime | Version |
| --- | --- |
| NodeMobile | 24.5.0 |
| Python | 3.14.6 / support release 3.14-b10 |
| TypeScript embedded in Hanlin host | 6.0.3 |
| ios_system | 3.0.5 |

The runtime host also pins Arborist 8.0.5, pacote 20.0.1, semver 7.8.5,
and ssri 12.0.0. Runtime bundle and Node XCFramework checksums are recorded as
verified in the existing lock file; Phase 0 did not independently rebuild
those artifacts.

## Foundational source systems

Pre-Phase-0 tracked source inventory:

| Area | Tracked files | Swift files | JS/JSON files |
| --- | ---: | ---: | ---: |
| `AI_HLY` | 657 | 286 | 133 |
| `AI_HLY/Downstream` | 254 | 129 | 40 |
| `AI_HLY/Downstream/RuntimeCore` | 87 | 33 | 40 |
| `AI_HLY/Downstream/MCP` | 47 | 45 | 0 |
| `AI_HLY/NativeAppPlatform` | 78 | 78 | 0 |
| `AI_HLY/NativeAgentExtensions` | 19 | 19 | 0 |
| `Scripts` | 27 | 0 | 9 |
| `Packages` | 6 | 2 | 0 |

RuntimeCore is a centralized actor-backed engine layer. Current TypeScript
execution compiles through Node and optionally executes emitted JavaScript as a
one-shot request. Current JavaScriptCore execution is a bounded one-shot
evaluator. Neither is the future persistent sandboxed application runtime.

The native app platform currently uses `AnyView` at its module boundary,
singleton-centric registration and capabilities, basic UserDefaults-oriented
storage, and an explicitly unfinished network policy boundary. These are
migration inputs, not Phase 0 changes.

## Authorized Scripting source inventory

Source root was read with literal-path-safe APIs and was not modified.

| Item | Count/size |
| --- | ---: |
| Directories | 507 |
| Files | 2,076 |
| Bytes | 79,544,906 |
| Reparse points | 0 |
| `docs` files | 942 |
| English Markdown | 402 |
| Chinese Markdown | 402 |
| Documentation TS/TSX examples | 136 |
| `dts` files | 5 |
| Declaration lines | about 32,368 |
| Canonical `scripts` files | 50 before archive exclusion |

The source contains two `node_modules` roots, Windows TypeScript launchers and
executables, a byte-identical backup subtree with Unicode/RTL name, and ZIP
archives. The explicit root-level mapping resolves all eight duplicated
required names. One project ZIP under canonical `scripts` was excluded. No
strong secret pattern or secret-bearing filename was found in approved files.

Imported result:

- 999 source files;
- 5,918,732 bytes;
- 5 declarations, 3 compiler files, 942 documentation files, 49 project
  example files;
- TypeScript package 7.0.2;
- declaration header `scripting v1.1.1`;
- aggregate SHA-256
  `8d7d33d9369ee555d15adf10c867abbfb85834eced7e7596a627b70ff627ff36`.

Generated diagnostics record 2,419 Phase 0 lexical symbols, 177 TS/TSX
fixtures, no unresolved documentation links, 20 links resolved using the
documentation-root convention, 158 duplicate normalized symbol names, and the
TypeScript 7.0.2 versus 6.0.3 compiler difference.
