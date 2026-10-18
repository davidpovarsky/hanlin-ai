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
- Read-only SDK/API verification through `apple-devtools` may be used when needed. Project CI, builds/tests, archives, and IPA generation may be dispatched when necessary for validation and verification, without requiring advance per-run authorization, while avoiding wasteful or routine-only reruns.

## GitHub Actions

- Project CI, builds, tests, audits, archives, and IPA generation may be dispatched whenever necessary for verification, validation, or completing tasks, without requiring advance explicit authorization for each run. Distribution and external release publication continue to run only on explicit user request.
- Do not add or broaden automatic `push`, `pull_request`, scheduled, or other workflow triggers without explicit permission.
- Prefer focused manual workflows when available.
- After a workflow is dispatched, prefer one long-lived watcher instead of repeated polling:

```bash
gh run watch <run-id> --exit-status --compact --interval 30
```

After it exits, inspect final metadata once and fetch detailed logs/artifacts only if needed.

## Impact-aware validation and authentic evidence reuse

- **Impact-aware validation; no redundant test reruns.** Before each build/test/CI operation, identify changed files and their complete dependency/consumer impact, then consult authenticated prior test evidence. Never rerun an already-passing test solely because of a newer commit, an unrelated failure, or final acceptance. Reuse a prior pass **only** if exact test identity, test/assertion semantics, fixtures, runtime inputs, relevant source/transitive dependencies, toolchain, environment, platform, and required evidence freshness are demonstrably unchanged and its original run/test really passed. Check the full commit range from each test's **own** evidence SHA to target HEAD, not merely HEAD's immediate parent. Reexecute failed, missing, affected, stale, invalidated, and uncertain tests. Unknown dependency impact means **rerun**, not assumed reuse. Do not substitute unit passes for failed UI/integration/performance obligations. Final acceptance may aggregate authentic unchanged passes and freshly executed affected tests **only when the versioned acceptance contract explicitly permits it**; do not falsely report that reused tests executed in the final run. Keep `EXECUTED_PASS`, `REUSED_VERIFIED_PASS`, `FAILED`, `NOT_RUN`, and `BLOCKED` separate, and never report full-CI success when a required gate fails or is skipped. Preserve required coverage. Prefer exact filtered `-only-testing` runs and one event-driven watcher. Measure CI duration and diagnose expensive test/setup/log phases before widening scope.

## Living Project Board

`PROJECT_BOARD.md` is this repository's shared living project board. Before starting substantial work, scan it for relevant context. During normal work, agents should proactively add concise, actionable entries when they discover something with genuine future value, including useful technical discoveries, optimization opportunities, implementation tricks, architectural ideas, possible future improvements, experiments worth running, unresolved issues or questions, and follow-up work that should not be lost—even when the discovery is incidental to the current task.

Do not add trivial observations, temporary debugging chatter, information already documented elsewhere, generic suggestions with no project relevance, or every step performed during a task. The board supports memory but is not a source of truth when repository code, documentation, or current state contradicts it. When an item is implemented, mark it complete and optionally record the date and commit/PR, moving it to `Done` when useful; delete or archive obsolete entries when appropriate.

Updating `PROJECT_BOARD.md` as a side effect of another task is allowed and encouraged when a worthwhile discovery is made. Recording an idea is allowed; implementing unrelated ideas is not.

Preserve all existing repository-specific instructions.


## Named Team — Antigravity + Codex

This repository is configured for active pair programming and autonomous task coordination using the persistent named AI team across Google Antigravity and Codex:
- **איתן (eitan)**: Principal architect (boundaries, contracts, migrations, technical RFCs)
- **נועם (noam)**: Engineering (scoped implementation, focused tests, bug fixes)
- **מיה (maya)**: Native UX (screens, interactions, RTL layouts, accessibility)
- **רוני (roni)**: Independent QA (acceptance verification, test artifacts, honest status)
- **תומר (tomer)**: Integration (branches, worktrees, PRs, cross-repo dependencies)
- **יעל (yael)**: Research (API capabilities, official Apple/upstream documentation, schemas)
- **דנה (dana)**: Security & Privacy (permissions, session isolation, secrets, entitlements)

### Mandatory Subagent Delegation
In any substantive coding, research, QA, or integration task, the primary session agent acts as an **orchestrator and coordinator**. It MUST NOT perform substantive implementation or QA directly to bypass delegation; instead, it MUST delegate the work to the appropriate specialist agent(s) using `invoke_subagent` (defining them via `define_subagent` if needed).
- All substantive code changes must be independently verified by **רוני (roni)** before task completion.
- Release tasks must involve **תומר (tomer)** and **רוני (roni)** (and **דנה (dana)** for security matters).
- NEVER attribute actions or comments to a role without an actual logged subagent invocation.

### Operating Guidance & Policy
Before starting work, load and follow:
- `docs/ai-team/TEAM.md` — Shared team contract and mandatory delegation rules
- `docs/ai-team/PROJECT_ASSIGNMENTS.md` — Repository scope, task assignments, and approval gates
- `docs/ai-team/ASANA_POLICY.md` — Authorized evidence-based task coordination, execution provenance, and verified completion policy
- `.agents/roles/<role>.md` — Role-specific scope and handoff rules

Preserve all existing repository policies, frozen components, and explicit owner release gates.
