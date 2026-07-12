# AGENTS.md — Modern Apple Development Rules

## 1. First action in every task

Before changing code:

1. Inspect this repository and read every applicable `AGENTS.md`.
2. If this file or another instruction file already exists, preserve valid repository-specific rules and update or merge them rather than replacing them blindly.
3. Identify:
   - project type and Apple platforms;
   - deployment targets;
   - Swift language mode;
   - Xcode and SDK versions used by CI;
   - schemes, targets, packages, dependencies, and build workflows;
   - whether this repository is an original project or a fork/mirror/derivative of an upstream repository.
4. Do not invent project structure, file names, targets, schemes, entitlements, or commands.

## 2. Platform policy

This project prefers the newest stable Apple development stack.

- Use the latest stable Xcode release available in the repository's GitHub Actions environment.
- Use the latest stable Swift language mode supported by that Xcode release.
- Target the newest stable iOS/iPadOS/macOS/watchOS/visionOS version appropriate to the project.
- The user does not want backward compatibility with older Apple operating-system versions.
- Do not add legacy implementations, compatibility wrappers, fallbacks, or old-platform branches.
- Do not add `if #available` merely to support older systems.
- Do not silently lower or preserve an old deployment target.
- If the repository currently targets an older system, report it and propose the minimal required project-setting change.
- Do not use beta SDKs or beta-only APIs unless explicitly requested.

## 3. Modern API policy

- Use current stable, public, officially supported Apple APIs.
- Prefer the currently recommended Swift, SwiftUI, Observation, navigation, presentation, layout, data-flow, persistence, and concurrency approaches.
- Never introduce deprecated APIs.
- Avoid APIs and patterns that Apple has superseded even when they still compile.
- Do not use private APIs, undocumented APIs, implementation details, or unreliable runtime tricks.
- Do not copy obsolete patterns from old tutorials or old answers.
- When modifying code that uses a legacy pattern, modernize the directly related implementation when safe and in scope.
- Do not rewrite unrelated working areas merely for novelty.

Examples that must trigger review in new or modified code include, but are not limited to:

- `NavigationView`;
- new `ObservableObject` / `@Published` models where Observation is appropriate;
- completion-handler APIs where a stable native async API exists;
- unnecessary `DispatchQueue.main.async`;
- UIKit wrappers for functionality now properly available in SwiftUI;
- obsolete `onChange` overloads;
- `UIApplication.shared.windows`;
- unnecessary `AnyView`;
- avoidable force unwraps and force casts;
- unstructured or detached tasks without a concrete reason.

Their presence is not automatically an error; inspect context and use the newest correct stable alternative.

## 4. Apple documentation and verification

Apple Developer Documentation pages may depend on JavaScript and may expose only an incomplete shell.

When documentation content is not readable:

1. Do not claim the page was read.
2. Do not guess an exact declaration, availability, deprecation state, or replacement.
3. Do not repeatedly say that JavaScript is still loading.
4. Search other official primary sources:
   - Apple framework update pages;
   - Apple release notes;
   - Apple sample projects;
   - Apple Technotes;
   - WWDC session pages and transcripts;
   - Swift Evolution proposals;
   - official Swift documentation;
   - source interfaces and availability metadata from the installed Xcode SDK when CI is explicitly run.
5. Treat the installed Xcode SDK and compiler diagnostics as the final technical authority.

Always distinguish between:

- verified from readable official documentation;
- verified from the installed SDK or a successful Xcode build;
- inferred but not compiled;
- uncertain and requiring SDK verification.

Never state that an API is current, available, non-deprecated, or accepted by Xcode without a concrete basis.

## 5. Swift requirements

- Use modern stable Swift syntax.
- Prefer structured concurrency, async/await, actors, `Sendable`, task groups, async sequences, and actor isolation where appropriate.
- Keep UI-bound state correctly isolated, normally with `@MainActor`.
- Avoid unnecessary detached tasks, unstructured concurrency, callbacks, and GCD-based designs.
- Do not silence concurrency diagnostics with unsafe annotations merely to compile.
- Prefer value semantics unless identity is required.
- Use clear error propagation and typed errors where useful.
- Avoid unnecessary type erasure, protocols, managers, service locators, dependency containers, and abstraction layers.

## 6. SwiftUI requirements

- Prefer SwiftUI for new user interfaces.
- Use UIKit/AppKit only when the latest stable SwiftUI genuinely lacks the capability or the existing architecture requires it.
- Prefer the Observation framework for new observable state where appropriate.
- Keep state ownership explicit and predictable.
- Avoid side effects in view bodies and oversized views.
- Preserve native behavior, accessibility, Dynamic Type, localization, right-to-left layout, keyboard navigation, pointer interaction, multitasking, and window resizing where relevant.
- Do not create wrappers around old UIKit APIs when a modern native SwiftUI solution exists.

## 7. Fork and upstream-friendly architecture

When this repository is a fork, mirror, clone, vendor copy, or derivative of an upstream project, optimize every customization for easy future upstream merges.

### Required approach

- First identify the upstream repository, upstream branch, and existing divergence when that information is available.
- Keep custom features, integrations, branding, platform adaptations, and behavior changes in clearly separated layers, modules, targets, directories, extensions, adapters, configuration files, or packages.
- Prefer additive changes over invasive edits.
- Prefer composition, dependency injection, protocols, extension points, adapters, wrappers, subclasses where appropriate, build settings, feature flags, and configuration over copying or rewriting upstream implementations.
- Reuse existing official extension points before adding new ones.
- Keep custom assets, localization, scripts, workflows, and documentation outside upstream-owned directories whenever practical.
- Use clear naming for downstream code, such as `Downstream`, `Custom`, `AppOverrides`, `Integrations`, or a project-specific namespace.
- Document each unavoidable upstream-file modification and why it is required.

### Changes to upstream-owned files

Modify original upstream files only when required for:

- an entry point;
- dependency registration;
- routing or navigation connection;
- lifecycle integration;
- exposing a narrow extension hook;
- build configuration;
- entitlement or manifest connection;
- importing or invoking the separate downstream layer.

Such edits must be:

- minimal;
- localized;
- easy to identify;
- free of unrelated formatting changes;
- free of broad refactoring;
- documented with the downstream component they connect.

Do not:

- duplicate large upstream files merely to customize small behavior;
- move or rename upstream files without necessity;
- reformat untouched upstream code;
- mix custom business logic deeply into upstream classes or views;
- replace upstream architecture when a small bridge or adapter is sufficient;
- delete upstream behavior unless explicitly requested.

### Upstream merge review

For substantial changes, report:

- which files are upstream-owned;
- which files are newly added downstream files;
- every unavoidable modification to an upstream file;
- how the design reduces future merge conflicts;
- any remaining merge risk.

When an upstream update is being merged:

- compare upstream changes before resolving conflicts;
- preserve downstream behavior through its separated layer;
- do not automatically choose “ours” or “theirs” for substantive conflicts;
- rerun modernization and verification checks only when explicitly requested.

## 8. Normal editing mode

Normal editing mode is the default.

In this mode:

- inspect, reason about, and edit the repository;
- use static checks available in the current environment;
- do not trigger GitHub Actions;
- do not create commits merely to trigger CI;
- do not start remote builds;
- do not wait for CI;
- do not claim Xcode compilation succeeded;
- briefly state that Xcode verification remains pending when relevant.

A request to write, fix, update, refactor, or add a feature is not permission to run CI.

## 9. Explicit verification mode

Enter verification mode only when the user explicitly asks to:

- build;
- compile;
- test;
- run GitHub Actions;
- verify with Xcode;
- run a modernization audit;
- analyze warnings;
- archive;
- generate an IPA;
- inspect CI failures.

In verification mode:

- use the repository's existing manually triggered workflow where possible;
- prefer `workflow_dispatch`;
- use the latest stable Xcode configured by the workflow;
- build the relevant scheme and configuration;
- run tests when present and relevant;
- run static analysis when configured or requested;
- collect complete errors and warnings;
- resolve relevant deprecation, availability, and concurrency diagnostics;
- do not rerun CI repeatedly without a concrete reason;
- report the workflow, scheme, configuration, SDK, deployment target, Swift mode, and Xcode version when available.

## 10. Modernization audit

When the user explicitly requests a modernization, legacy, or code-health audit, inspect existing code rather than only newly changed code.

Use the checks available to the repository, preferably including:

1. Xcode build diagnostics;
2. deprecation and availability warnings;
3. complete Swift concurrency checking;
4. Swift 6 language-mode diagnostics when supported;
5. `xcodebuild analyze`;
6. tests;
7. SwiftLint when already configured or explicitly approved;
8. Periphery when already configured or explicitly approved;
9. dependency update and obsolescence review;
10. a targeted search for legacy Apple and Swift patterns.

Classify findings as:

- definite compiler or SDK issue;
- officially deprecated;
- supported but superseded;
- concurrency or safety issue;
- code quality issue;
- dead-code candidate;
- dependency issue;
- manual review only.

Do not automatically rewrite every flagged occurrence. Explain false positives and context-sensitive cases.

Do not add third-party audit tools or alter CI without explicit permission. When requested to create an audit workflow, make it manually triggered and report-only by default.

## 11. GitHub Actions policy

- CI, builds, audits, and IPA generation run only on explicit user request.
- Do not add or expand `push`, `pull_request`, scheduled, or automatic triggers without explicit permission.
- Prefer manual `workflow_dispatch`.
- Do not hide warnings solely to obtain a green build.
- Do not change signing, certificates, provisioning, bundle identifiers, entitlements, or deployment settings without explaining the need.
- A successful build does not prove runtime correctness, UI correctness, memory safety, or behavior on a physical device.

## 12. Existing instruction and workflow files

Before creating any of the following, check whether an equivalent already exists:

- `AGENTS.md`;
- nested `AGENTS.md` files;
- ChatGPT instruction files;
- lint configuration;
- modernization audit workflows;
- build, test, archive, or IPA workflows.

If one exists:

- inspect it;
- preserve valid project-specific settings;
- update and merge missing rules;
- avoid duplicate files and duplicate workflows;
- do not overwrite secrets, signing configuration, scheme names, paths, or custom commands;
- summarize what was retained, added, changed, or removed.

## 13. Completion and honesty

After substantial work, report briefly:

- what changed;
- which modern APIs and architecture were used;
- whether the repository is upstream-derived;
- how downstream customizations were isolated;
- which upstream files, if any, were minimally modified;
- whether official documentation was readable;
- whether an Xcode SDK or compiler actually verified the work;
- whether GitHub Actions ran;
- which checks remain pending.

Never claim:

- the project builds;
- there are no warnings;
- an API is definitely current;
- the code works on a real device;
- an upstream merge will be conflict-free;

unless that exact claim was verified.

## 14. User preference

The user wants modern, advanced, clean Swift and SwiftUI code, targets current stable Apple platforms only, does not want backward compatibility, works from Windows, and uses manually requested GitHub Actions for Apple-platform compilation and verification.
