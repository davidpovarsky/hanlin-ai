# AGENTS.md â€” Shared Development Rules

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

## Living Project Board

`PROJECT_BOARD.md` is this repository's shared living project board. Before starting substantial work, scan it for relevant context. During normal work, agents should proactively add concise, actionable entries when they discover something with genuine future value, including useful technical discoveries, optimization opportunities, implementation tricks, architectural ideas, possible future improvements, experiments worth running, unresolved issues or questions, and follow-up work that should not be lostâ€”even when the discovery is incidental to the current task.

Do not add trivial observations, temporary debugging chatter, information already documented elsewhere, generic suggestions with no project relevance, or every step performed during a task. The board supports memory but is not a source of truth when repository code, documentation, or current state contradicts it. When an item is implemented, mark it complete and optionally record the date and commit/PR, moving it to `Done` when useful; delete or archive obsolete entries when appropriate.

Updating `PROJECT_BOARD.md` as a side effect of another task is allowed and encouraged when a worthwhile discovery is made. Recording an idea is allowed; implementing unrelated ideas is not.

Preserve all existing repository-specific instructions.


## Named Team â€” Antigravity + Codex

This repository is configured for active pair programming and autonomous task coordination using the persistent named AI team across Google Antigravity and Codex:
- **××™×ª×Ÿ (eitan)**: Principal architect (boundaries, contracts, migrations, technical RFCs)
- **× ×•×¢× (noam)**: Engineering (scoped implementation, focused tests, bug fixes)
- **×ž×™×” (maya)**: Native UX (screens, interactions, RTL layouts, accessibility)
- **×¨×•× ×™ (roni)**: Independent QA (acceptance verification, test artifacts, honest status)
- **×ª×•×ž×¨ (tomer)**: Integration (branches, worktrees, PRs, cross-repo dependencies)
- **×™×¢×œ (yael)**: Research (API capabilities, official Apple/upstream documentation, schemas)
- **×“× ×” (dana)**: Security & Privacy (permissions, session isolation, secrets, entitlements)

### Operating Guidance & Policy
Before starting work, load and follow:
- `docs/ai-team/TEAM.md` â€” Shared team contract and platform mapping
- `docs/ai-team/PROJECT_ASSIGNMENTS.md` â€” Repository scope, task assignments, and approval gates
- `docs/ai-team/ASANA_POLICY.md` â€” Authorized evidence-based task coordination and verified completion policy
- `.agents/roles/<role>.md` â€” Role-specific scope and handoff rules

Preserve all existing repository policies, frozen components, and explicit owner release gates.


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
