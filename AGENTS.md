# AGENTS.md — Shared Development Rules

Read `PROJECT_AGENT_GUIDANCE.md` if it exists. It contains repository-specific architecture, build, upstream, signing, and workflow guidance and must be followed together with this file. The user's current request has highest priority, then repository-specific guidance, then these shared rules.

## Working style

- Inspect the repository before editing; preserve its architecture and conventions.
- Prefer the smallest safe change. Avoid unrelated refactors, formatting, renames, dependency changes, or generated-file churn.
- Reuse existing extension points and components before creating parallel systems.
- Validate only what changed unless broader validation is genuinely required or explicitly requested.
- Never print, commit, or expose secrets, signing keys, tokens, certificates, or private credentials.

## Forks and upstream-friendly changes

When a repository is a fork, mirror, vendor copy, or derivative of an upstream project, optimize custom work for easy future upstream syncs.

- Identify upstream-owned code and keep it as untouched as practical.
- Put custom features and integrations in separate modules, packages, directories, services, adapters, extensions, wrappers, configuration, or other clearly downstream-owned layers.
- Modify upstream files only for the narrow connection points that are actually necessary: imports, registration, dependency injection, routing/navigation, lifecycle hooks, manifests/entitlements, or a small extension hook.
- Keep unavoidable upstream edits minimal, localized, obvious, and free of unrelated formatting or refactoring.
- Do not move, rename, duplicate, broadly rewrite, or mix custom business logic into upstream-owned files when a bridge or additive layer is sufficient.
- When syncing upstream, inspect upstream changes before resolving conflicts; do not blindly choose ours/theirs.
- For substantial work, report which upstream files were touched, which downstream files were added, and any remaining merge risk.

## Apple native-first development

For iOS, iPadOS, macOS, watchOS, tvOS, and visionOS work:

- Prefer current stable, public Apple APIs and native Swift/SwiftUI solutions.
- Prefer semantic system components and platform behavior over hand-built replicas: native navigation, lists, forms, tables, grids, toolbars, menus, sheets, inspectors, search, controls, materials, and system presentation patterns where appropriate.
- Do not assemble a custom control or complex layout from `HStack`, `VStack`, `ZStack`, `GeometryReader`, or manual geometry when a suitable native component expresses the intent. Stacks remain appropriate for simple composition or when a custom layout is clearly better or explicitly requested.
- Use UIKit/AppKit wrappers only when current stable SwiftUI genuinely lacks the required capability or the existing architecture requires them.
- Preserve accessibility, Dynamic Type, localization, RTL, keyboard/pointer behavior, multitasking, and platform conventions where relevant.
- Avoid deprecated, private, undocumented, legacy, or beta-only APIs unless explicitly requested.

## Apple SDK and API verification

Use the shared `apple-devtools` toolkit whenever exact Apple API/SDK facts, compiler behavior, signing, or platform validation matter.

- Toolkit repository: `davidpovarsky/apple-devtools`.
- On the configured Windows workstation it is installed at `C:\Users\DAVID\Code\apple-devtools` and its `apple-*` commands are on PATH.
- Prefer the cheapest authoritative check that answers the question: portable local Swift checks first; `apple-api` / `apple-symbol` for SDK lookup; `apple-typecheck` for Apple-framework compilation; focused `apple-build` / `apple-test-focused` when compilation or tests are actually needed; signing/entitlement/archive tools for distribution work.
- Windows Swift is authoritative only for portable Swift. It cannot validate SwiftUI, UIKit, AppKit, WidgetKit, AppIntents, ActivityKit, CloudKit, or other Apple-only frameworks.
- For exact declarations, availability, overloads, or compiler acceptance, the installed Xcode SDK/compiler through the macOS authority layer is the final technical authority.
- Use official Apple documentation, release notes, samples, and WWDC material for semantics and recommended behavior.
- Do not guess an Apple API signature, availability, deprecation state, entitlement, or capability when it can be verified quickly.
- If `apple-devtools` is unavailable in the current environment, consult its repository/instructions rather than recreating duplicate tooling.
- Read-only SDK/API verification through `apple-devtools` may be used when needed. Do not trigger project CI, full builds/tests, archives, TestFlight/App Store actions, or change project workflows merely for routine editing unless the user explicitly requests those operations.

## GitHub Actions

- Project CI, builds, tests, audits, archives, IPA generation, and distribution run only on explicit user request.
- Do not add or broaden automatic `push`, `pull_request`, scheduled, or other workflow triggers without explicit permission.
- Prefer focused manual workflows when available.
- After an authorized workflow is dispatched, prefer one long-lived watcher instead of repeated polling:

```bash
gh run watch <run-id> --exit-status --compact --interval 30
```

After it exits, inspect final metadata once and fetch detailed logs/artifacts only if needed.
