# Upstream maintenance acceptance contract (2026-11-15)

Renovate is the only update bot. Its exact version, Node toolchain, lockfile, SRI and license graph live in `Scripts/Runtime/DependencyUpdates`. Automation Node is separate from embedded Node. Existing Tuesday scheduling is retained; no new push/PR trigger is introduced. Configuration follows the original [Swift manager](https://docs.renovatebot.com/modules/manager/swift/) and [regex manager](https://docs.renovatebot.com/modules/manager/regex/) contracts.

`upstream-sources.json` records original OpenClaw, tree-sitter-bash, swift-tree-sitter and Yams revisions. These records monitor source provenance; they neither vendor implementations nor claim the future Skills consumers are integrated. Yams 6.2.2 belongs to the Skill Format owner. Xcode shared project pins, private SDKs, NativeScript/Expo compiler sets and ABI updates require their canonical owners. Generated mirrors and fixtures are excluded. SwiftPM manifest proposals still require resolver/build evidence on Apple before acceptance.

The existing Runtime updater supports read-only `--plan`, isolated `--host-package=NAME --target-version=VERSION`, and existing lock synchronization. Native updates require explicit `--include-native`; source-patch drift fails before applying pins. Major, native, binary and source digest changes require manual review. A changed upstream release never updates an installed IPA automatically.

## Candidate lane

A same-repository isolated Host patch/minor candidate must change only the four canonical Host/Runtime manifests. `prepare-upstream-verification.mjs` authenticates actual PR HEAD/base/diff, original npm Git commit, SRI, stable version, embedded engine compatibility and unchanged license. Unscoped transitive graph or native artifact changes fail closed. Existing native identity and authenticated original artifact staging must pass before the full affected Host closure and packed JITless smoke execute on embedded Node 24.5.0. CycloneDX SBOMs, exact source context, actual metadata and artifact hashes are retained. This is Host proof, not an iOS app/UI pass or native binary rebuild.

`failure-demo` deliberately fails the real GitHub acceptance job. It is a negative demonstration, never a product test pass. `candidate` executes the actual affected tests. `check-upstream-merge-gate.mjs` authenticates current-head GitHub checks and a digest-verified workflow receipt. No receipt, failed/stale check, unknown source impact or missing branch protection blocks eligibility. The checker never calls a merge API. Previous passes can only be reused through the existing authenticated native identity closure; Host tests execute for the new graph.

## Activation and rollback

Automerge is disabled in bot configuration and was disabled in repository settings at inspection. The default branch had no protection. Therefore this implementation does not claim server-enforced protection against a human bypass. Enabling repository protections or Actions PR creation must be coordinated with the manager; a blocked bot action remains BLOCKED rather than a fabricated update success. Repository configuration stays unchanged by these tools.

Rollback restores the isolated parent manifest bytes and rebuilds the previous Host archive while retaining the original native artifact pins. It does not mutate sessions, storage, user Skills or permissions. Demo branches/PRs remain unmerged. Broad native mode creates candidate artifacts only (`publish_release=false`, TestFlight off).

## Evidence state before live candidate

EXECUTED_PASS: 23 focused updater/policy tests; strict actual Renovate 44.239.1 configuration validation; real read-only repository extraction/lookup on Node 24.22.1. Canonical runtime dependency hash remained unchanged after the pure-function refactor. Candidate/failure CI and rollback proof are pending; no full acceptance is claimed here.

The updater workflow is not registered on default main (actual dispatch404). Until integration, the already-registered manual `validate-app-split.yml` accepts an explicit upstream operation and calls the same updater workflow with native MiniApps jobs skipped. This adds no automatic trigger. Renovate Host proposals are synchronized through the existing updater using isolated temporary JSON files and a non-force Git ref update; candidate code is never checked out or executed by synchronization.
