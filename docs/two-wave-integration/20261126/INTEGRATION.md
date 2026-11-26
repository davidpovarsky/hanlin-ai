# Approved two-wave integration — 2026-11-26

Status: source composition in progress; no new native or release acceptance.

## First composition

- Hanlin base: bd42deb1b6fd5884f5c0f2aad8ae2e4ab1dadff4.
- Original shared MiniApps/Composer source: 86a6dde354947be9329fe1e8f4d45a433fe488c4 (PR18).
- Twenty conflicts resolved semantically in an isolated sparse worktree.
- Preserved current Responses routing on custom hosts, activity task lifetime, original notification callback forwarding, tested disclosure accessibility, calendar tools and current app startup order.
- Included original assistant-tool authoring and Composer contracts; unioned 526 application source members.
- Unioned SwiftPM lock entries by identity with no conflicting common revisions (41 pins).
- Both Xcode UI test references and existing app source references retained; original project parser succeeds, no duplicate object identifiers.
- Source-generated SDK inventories and original Expo receipt retain their original provenance and MUST be refreshed/verified against the final combined SDK before packaging. They grant no acceptance to this composition.

## Remaining integration

Current PR19 SDK, explicit cache integration, original shared Chat action/presentation extraction and new standalone MiniApps capabilities follow in dependency order. Existing POST149101 and PR19 native runs retain their own owners and scopes. Source commits are not build/test/release receipts.

## Product boundary

Standalone MiniApps owns new shortcut/widget/runtime UI. Hanlin and consumers use shared authoring/types/SDK contracts and the original cross-app bridge without duplicated runtime. Legacy Scripting-JSC/ScriptUI/.scripting stays frozen.

## Second composition: current PR19

- Current SDK parent: c34dd6ae752b3ab3ebc001743fc62c72fc48a203.
- Preserved original assistant modules and incorporated ScriptWidget resources, widget-engine metadata and widget Host-action validation in the same authoring/compiler path.
- Both original assistant-export tests and new Host-widget tests are retained. Three changed JavaScript modules passed Node syntax checks; execution remains required on the merged closure.
- Seven original compiled Expo probes and seven test copies use current PR19 bundles. All manifest fields, missing-grant fixture and incompatible-version fixture remain unchanged; only bundle.js differed. This is provenance comparison, not test execution.
- All526 application source members and both native window test references remain. The source-only project parser caught four identical duplicated object blocks introduced by automatic merge; removed the second copies and the parser passed.
- Unified input hashes describe the actual staged package manifests; final canonical generation remains required.

## Cache history reconciliation

Merged original local cache head0d58bf1648788236dafc53c35618ad5dd5c22112. Mechanical comparison proved the merge adds only historical docs/evidence; every non-doc source file is unchanged from e09c596ad. The cache implementation was already present through the shared source composition. Prior native receipts retain their original tested-source scope; no duplicate cache implementation or new native PASS is claimed.
