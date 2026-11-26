# Shared original message interactions, 2026-11-26

## Source and scope

Isolated branch: `codex/hanlin-wave1-shared-chat-actions-20261126`.
Base: `bd42deb1b6fd5884f5c0f2aad8ae2e4ab1dadff4`.
Original launcher source: `244dc02e494df8acfa8563c8aa8872cd8c490fff`.

The original message action row, menu labels/order, native long-press preview,
selection sheet, image and document attachments/viewers now have one UI owner
in HanlinChatUI. Canonical Hanlin adapters inject real clipboard, speech,
translation, persistence, source navigation, photo and deletion callbacks.
Unavailable host callbacks create no inert controls. Original Markdown parsing,
streaming, citation projection, embedded/rich cards, session, composer and source
navigation remain their existing implementations. Business/tool-specific cards
remain in the original shared HanlinApplication module.

The launcher production files and policy tests are byte-identical to the
original accepted launcher source. HanlinLauncherLab exercises shared menus,
preview, selection, actions and real local clipboard/deletion callbacks. Its
offline streamed fixture is not evidence of a live model request.

## Ownership and integration

The host remains one canonical app source module. HanlinChatPresentation is an
internal application dependency, not a new direct PBX host link edge.
The original generator produces 48 products, 116 targets and 517 original
application source files. The ownership test now compares exact canonical
library product and target sets rather than obsolete fixed counts; independent
host library preservation remains asserted.

This branch is limited to original chat interaction extraction and launcher
integration. The active POST149101 and PR19 source trees were not modified.
Root owns integration, Asana milestones and final release. The assigned Mac
build owner owns native validation; this branch has not run duplicate builds.

## Recorded checks

- Original manifest generation and `--check`: PASS.
- Original project ownership `--check`: PASS.
- Installer suite: 11 tests PASS.
- Host link suite: five identities passed initially; one obsolete count assertion
  failed after adding the launcher product. Its updated exact-graph expectation
  initially included an executable in library products, then passed a targeted
  rerun after correcting the library filter. All six identities covered; the
  original failures and targeted successful receipt are preserved.
- Linux Swift parser: PASS, syntax only. See receipt for exact source hashes.
- Original launcher policy source: historical evidence reusable because all four
  relevant files remain byte-identical. No new native pass is inferred.
- New host-authority/preview geometry tests: NOT_RUN pending Apple test runner.
- Native UI compile, simulator interaction, physical device and TestFlight:
  NOT_RUN for this candidate.

## Remaining acceptance gates

Compile the original shared UI and launcher against the Apple SDK, run the
focused action-authority and viewport tests, and verify the original native
preview/selection route in the launcher consumer. The integrated application
must incorporate the active POST149101 owner's subsequent fixes and be checked
by the single release owner. Root must reconcile this work with the other
approved wave branches before any whole-wave completion claim.

## Evidence classification

| Classification | Scope | Decision |
|---|---|---|
| REUSE_ACCEPTED | Original native launcher 244 production and policy files | Exact four-file hashes match donor; retain behavior and historical policy evidence. |
| VERIFY_REGRESSION | Canonical host adapters, native actions, preview and selection | Compile the changed shared/host boundary and exercise native route on the Mac. |
| IMPLEMENT_GAP | Host-bound message interactions and launcher consumer | Extracted original implementation with host callbacks; unavailable services omitted. |
| PROBE_UNKNOWN | Exact candidate simulator interaction, physical device and TestFlight | No completion claim; assigned integration/build owner must supply receipts. |
| FIX_REPRODUCED | Host-link graph test's obsolete 47-product count | Replaced fixed counts with exact canonical graph sets and retained independent host ownership check. |


## Native LauncherLab gate — 2026-11-26

[native/acceptance-r6.json](native/acceptance-r6.json) records a fresh
original-source Xcode build and simulator test execution at source
730bbb6d70e8c9f136c5ee21437f78cc5b6e7bfb:
**5 passed, 0 failed, 0 skipped**. The canonical selected product profile includes
six original targets. All 3,318 archived inputs were checked against the source
snapshot and cumulative committed deltas; resolved dependency revisions match
the integrated application lock. Xcode 27.0 (27A266a), Apple Swift 6.4 and an
owned iPad Pro (M5) iOS 27 simulator were used.

The five exact test identities cover invalid and bounded preview geometry,
absent host services, retained host callbacks, and current host translation/save
state. The original launcher policy test file compiled in the same test target,
but unchanged policy methods were not selected again.

Attempts 1–5 and their genuine build failures remain in the native directory;
no zero-test attempt is classified as passing. Fixes retained the original
shared haptic modifier, restored the original typed preview callback boundary,
kept the main-actor action callback explicit, moved an unchanged predicate
outside a Swift Testing macro expansion, and linked the existing pinned
Markdown product in the consumer project. The successful result bundle,
exported test tree, compressed raw logs, transfer hashes and artifact manifest
are retained.

This establishes the focused source-consumer build and interaction contracts.
Full Hanlin UI acceptance, live provider behavior and physical iPad appearance
remain separate parent-owned gates. The earlier receipt describes the earlier
source-only checkpoint and is preserved as historical evidence.
