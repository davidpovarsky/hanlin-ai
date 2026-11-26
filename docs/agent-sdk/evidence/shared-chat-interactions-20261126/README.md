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
