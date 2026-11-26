# Developer Studio independent-review follow-up

Base: 679ee14d858627d0b91417828b579fdc143ccd93.
Independent reviewer: built-in agent /root/wave1_chat_sdk, read-only source review.
All Apple lifecycle tests below are NEW / NOT_RUN until the native owner executes them.

## Corrected findings

1. Open-file rename previously called select() after the move, causing select's second save to read the missing old path. moveSelectedFile(to:) now saves once, moves, immediately rebinds the open Document, increments the editor revision and refreshes files. Subsequent edits target the new path.
2. Validation/build completion is actor-reentrant. Each original authoring request now captures its source revision and discards a result if the revision changed while awaiting the service; a stale archive is not returned to the import handoff. The source editor and file-mutation UI are disabled while busy, including UITextView.isEditable. The revision guard remains necessary for pending events and programmatic edits.
3. Recovery files are decoded independently. A damaged/unreadable/misidentified journal is retained for export and displayed as a recovery issue; valid drafts continue to appear. No damaged file is deleted or silently substituted.
4. SourceRoot projects may have an absent or partial inner authoring descriptor. The editor merges its UI fields over the outer descriptor and retains the outer authoringRoot when needed by the canonical resolver. A complete retained original source project remains directly buildable. Draft recovery persists the actual authoring root.

## Exact native tests added

Suite: HanlinMiniAppsTests/MiniAppsStudioProjectTests (4 definitions, 6 executed cases expected)

- renamingTheOpenFileRebindsLaterEditsAndSaves — 1 case; rename the selected source, edit, save and verify new path bytes plus absent former path.
- outerDescriptorRemainsAvailableWhenSourceRootHasNoCompleteDescriptor — 2 cases (inner descriptor absent / partial); verify editable source and canonical authoring root.
- malformedRecoveryDoesNotHideOrAlterAnotherWindowsDraft — 1 case; preserve a valid journal and damaged original bytes while reporting the damaged file.
- changedRevisionCannotPublishAnOriginalAuthoringResult — 2 cases (validate / build). Calls the real MiniAppAuthoringService and embedded Node compiler, edits during its awaited request, and requires stale result suppression. A compiler/SDK infrastructure failure does not count as a pass.

The original workspace source and the original Node editor operation are unchanged from the 4 + 4 executed tests at 679ee14d. Their narrow portable evidence can be reused only for those unchanged mechanisms. No portable result certifies these newly added Apple application-model scenarios.

## Verification performed here

Swift frontend syntax parse of the three changed Studio app files and the new test file passed on Oracle Swift 6.4.3. This is syntax only, not Apple typecheck or test execution. Root/mac_build_ops own exact integrated HanlinMiniApps compilation and the native test selection.

Run alongside the existing 4 MiniAppsDeveloperWorkspaceTests cases. The complete Studio affected native selection is therefore 10 cases, including the two original authoring integration scenarios.

## Independent follow-up review

The same built-in reviewer spot-checked e641105fdc7ac5b418c49b9a146c96cfccf0f078 and confirmed the three reported fixes plus sourceRoot correction in source, with no further blocker in that bounded review. It independently confirmed 4 method definitions / 6 invocations. This is source-review evidence, not native execution.
