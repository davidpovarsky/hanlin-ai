# Repository Guidelines

## Project Structure & Module Organization
App sources sit in `AI_HLY/`, with `AI_HLY.swift` wiring the SwiftUI scene and model container. Domain models live in `AI_HLY/Model/`, while service logic stays under `AI_HLY/Services/` (for example, `Services/APIServices` and `Services/VisionServices`). UI flows belong in `AI_HLY/Views/` and its `Views/Components` subfolder, with localized variants alongside them in `Base.lproj` and `mul.lproj`. Version configuration JSON (such as `Resource/memoryConfig.json`) in Git, and keep secrets out of source by copying `Config.xcconfig.template` to `Config.xcconfig` locally.

## Build, Test, and Development Commands
Kick off development with `open AI_HLY.xcodeproj` to resolve packages and run previews. Scriptable builds use `xcodebuild -project AI_HLY.xcodeproj -scheme AI_HLY -destination 'platform=iOS Simulator,name=iPhone 15' build`. When tests exist, execute `xcodebuild -project AI_HLY.xcodeproj -scheme AI_HLY -destination 'platform=iOS Simulator,name=iPhone 15' test` before submitting. Re-sync Swift Package Manager dependencies with `xcodebuild -resolvePackageDependencies` after edits.

## Coding Style & Naming Conventions
Follow Swift defaults: four-space indentation, `PascalCase` for types and file names, and `lowerCamelCase` for properties, bindings, and async tasks. Collect SwiftUI state wrappers at the top of each struct and lean on small computed properties instead of sprawling view builders. Preserve the existing bilingual comments, keep localized copy in `.xcstrings`, and mirror the `Services/<Domain>Services` folder split when adding new integrations.

## Testing Guidelines
The project currently ships without automated tests; add `AI_HLYTests` or `AI_HLYUITests` targets when contributing features. Co-locate fixtures under a `Tests/Resources` folder and name XCTest cases after the component under test (e.g. `ChatViewTests`). Document manual verification steps for SwiftUI previews or simulator flows, and share simulator logs when diagnosing CloudKit or SwiftData behaviour.

## Commit & Pull Request Guidelines
Follow the Conventional Commits pattern in history (`feat:`, `fix:`, `chore:`) and scope messages to a single concern. Before opening a pull request, run the build command above and note the result in the description. Reference affected views or services, link the tracking issue, and include screenshots or recordings for UI changes. Call out any new API keys or entitlement adjustments in the PR body.

## Security & Configuration Tips
Never commit personal API keys or signing profiles; store them in your local `Config.xcconfig` and enter them through the in-app Settings screen. When adding new providers, document the required key names in `Model/APIKeys.swift` and update onboarding copy if needed. Review `AI_HLY.entitlements` and `AI-HLY-Info.plist` whenever capabilities change, and flag reviewers if a migration step or data reset is required.

## Living Project Board

`PROJECT_BOARD.md` is this repository's shared living project board. Before starting substantial work, scan it for relevant context. During normal work, agents should proactively add concise, actionable entries when they discover something with genuine future value, including:

- useful technical discoveries
- optimization opportunities
- implementation tricks
- architectural ideas
- possible future improvements
- experiments worth running
- unresolved issues or questions
- follow-up work that should not be lost

Do this proactively even when the discovery is incidental to the current task. Do not add trivial observations, temporary debugging chatter, information already documented elsewhere, generic suggestions with no project relevance, or every step performed during a task. The board supports memory but is not a source of truth when repository code, documentation, or current state contradicts it.

When an item is implemented, mark it complete and optionally record the date and commit/PR, moving it to `Done` when useful. Delete or archive obsolete entries when appropriate.

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
