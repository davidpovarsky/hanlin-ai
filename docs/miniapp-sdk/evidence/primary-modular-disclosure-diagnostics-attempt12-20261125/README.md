# Actual Modular disclosure diagnostic, attempt12

The original Modular case on source 1a611764779b0a57cc57d71b26d2cd6449895d8d **executed and failed**: 0 PASS / 1 FAIL / 0 SKIP, 172.791446 seconds, final driver exit65 at 03:42:11.337019 UTC on 25 November 2026. Failure is the original source-version disclosure assertion at UI1220. The complete original 52 and the three scoped NativeScript ownership/lifetime cases remain NOT_RUN. No task is closed by this record.

The native disclosure itself responded correctly. Before/after screenshots and accessibility trees establish the actual state transition; the test observed the wrong child identifier. Full-text API retrieval and body acceptance were not reached and are not claimed as passing.

## Observed route

| Boundary | Actual evidence |
| --- | --- |
| MiniApps build-for-testing | Exit 0; 158.248764 s; exact lossless build log retained |
| AI build-for-testing | Exit 0; 114.468036 s; exact lossless build log retained |
| Original Modular authoring | Exit 0; 13.811592 s; current SDK10; zero diagnostics |
| Original import validation | Job 30f75bb6-e894-48ed-97cf-ee567f9e4619 completed 44.917 s, exit 0, zero diagnostics; strict=true, skipLibCheck=false, dependency declarations checked |
| Search and detail | Real results and native source/version detail appear in actual PNG+AX |
| Disclosure | The selected first group changed expanded to collapsed; its Full text row disappeared |
| Full-text request/new-version/body | NOT_REACHED; the locator assertion stopped the case |
| Final complete acceptance | Original 25 + 27 NOT_RUN |

Actual import output binds SDK manifest19726b5eecc1459e30dae9e7ec4ca6761001de92b22055ac41b9a96aabdd7a88 and the existing original TypeScript package6.0.2/compiler6.0.3 alias relationship. The actual Modular archive is 2,203,330 B / SHA 3f4dc26706ded3590674eceaa4314554e1564e4bf4ab7a46d57bb1bf2e50b33e. Its retained source/App.tsx exactly matches the source commit, 25,786 B / SHA 4e8389eb6a232e6ed5db8273dd2686e45ab04edabd2e86bfea74cbdf862e5b7c.

## Actual visual and accessibility finding

The search PNG252e0634 was viewed directly. English and Hebrew glyphs are normally oriented and real native results are visible; the earlier mirrored glyphs are absent in this captured route after the original Host was keyed by locale. This does not claim exhaustive locale testing.

The detail PNG5577e8e8 shows the first JPS1917 version expanded, with its Full text button. The failure PNG7b9de14e shows the same version collapsed, with that button removed. The native image identifier changes from expanded to collapsed at line176 of the corresponding accessibility trees.

Before the tap, AX173 identifies the original source-version header. AX183 gives its Full text button **the same inherited source-version identifier**, rather than the intended modular-full-text-load identifier. The same pattern appears on the other groups. There are zero intended load-button ID occurrences in both before and after trees. Therefore UI1218 starts with loadText.exists=false and UI1220 still sees false after a real native collapse.

This is an observed identifier-inheritance and test-oracle mismatch. It is not evidence of a broken disclosure tap or of collapsed content retained in the accessibility tree. The original upstream DisclosureGroup local state/default and supported Label slot are retained as two small exact source files for review. Any locator correction must retain the actual native state transition and all live source, API-returned version, language and nonempty full-text assertions.

## Integrity and limits

All 55 producer packet members, 5,725,010 B, are retained unchanged under raw/, plus the exact producer receipt. The first 14 members were already verified; all 41 added members were verified separately. Three gzip files roundtrip to the original 7,581,366 B own-app stream, 979,669 B MiniApps build log and 949,110 B AI build log, with exact declared SHA256. Both the initial storage rejection and authorized continuation/retirement receipts remain unchanged.

The original attachment manifest names 31 exports. This bounded packet retains eight selected import/search/detail/failure PNG+AX files; three PNGs were visually inspected. Retaining all 55 packet members is not a claim of retaining all 31 attachments or every file mentioned in producer observations.

The current Host archive identity matches already verified SDK10, and actual import output matches its manifest. No full Host ZIP was copied, repacked or audited again. A nonexistent producer source-binding path is explicitly omitted; no identity was invented for it. Actual installed metadata bindings and current test-binary binding are retained as producer evidence, separate from the earlier SDK10 archive reconciliation.

The original generic collector error is 'Original runtime acceptance did not execute every selected case: ModularFocusedDiagnostic'; its real nodes prove one executed failing case. That raw error is preserved with this correction. Original UI source was used and the test rebuild passed; final retained cleanup shows the owned simulator shut down and no remaining owned runners. This evidence inspection performed no Mac query, compiler, generator, native run or application edit.
