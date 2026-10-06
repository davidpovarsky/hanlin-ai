# AGENTS.md — Shared Development Rules

Read `PROJECT_AGENT_GUIDANCE.md` if it exists. It contains repository-specific architecture, build, upstream, signing, and workflow guidance and must be followed together with this file. The user's current request has highest priority, then repository-specific guidance, then these shared rules.

## Working style

- Inspect the repository before editing; preserve its architecture and conventions.
- Prefer the smallest safe change. Avoid unrelated refactors, formatting, renames, dependency changes, or generated-file churn.
- Reuse existing extension points and components before creating parallel systems.
- Validate only what changed unless broader validation is genuinely required or explicitly requested.
- Never print, commit, or expose secrets, signing keys, tokens, certificates, or private credentials.

## Independent-fork development policy

Hanlin is an independently maintained derivative of CherryHQ/hanlin-ai. Upstream mergeability is no longer a primary architecture constraint.

- Future upstream changes may be cherry-picked selectively after review; mergeability is not a design constraint.
- Direct edits and deletions in former upstream files are allowed and encouraged when they reduce duplicate implementation, remove obsolete paths, or improve Hanlin's architecture.
- Keep modules clean, avoid giant files, and separate domain responsibilities for Hanlin's own long-term maintainability.
- Prefer one authoritative implementation path over wrappers kept only for historical ownership boundaries.
- Do not duplicate files merely to claim downstream separation.
- Do not preserve dead or legacy code merely because it originated from upstream.
- Report large architectural deletions and migrations with tests and parity evidence, not “upstream touchpoints”.
- Preserve attribution and license history required by the original project license.

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

## Living Project Board

`PROJECT_BOARD.md` is this repository's shared living project board. Before starting substantial work, scan it for relevant context. During normal work, agents should proactively add concise, actionable entries when they discover something with genuine future value, including useful technical discoveries, optimization opportunities, implementation tricks, architectural ideas, possible future improvements, experiments worth running, unresolved issues or questions, and follow-up work that should not be lost—even when the discovery is incidental to the current task.

Do not add trivial observations, temporary debugging chatter, information already documented elsewhere, generic suggestions with no project relevance, or every step performed during a task. The board supports memory but is not a source of truth when repository code, documentation, or current state contradicts it. When an item is implemented, mark it complete and optionally record the date and commit/PR, moving it to `Done` when useful; delete or archive obsolete entries when appropriate.

Updating `PROJECT_BOARD.md` as a side effect of another task is allowed and encouraged when a worthwhile discovery is made. Recording an idea is allowed; implementing unrelated ideas is not.

Preserve all existing repository-specific instructions.
