# Main13 shipping identity reuse

Status: **PASS for current SDK05 shipping identity reuse.** Main13 application acceptance remains **BUILD_FAILED / UI NOT_RUN**.

This is a read-only comparison of the already authenticated artifact from run `45389020875`, source `2cb851067c4339125ab6fb515522796bceb80c35`, with the sealed [main12 SDK05 proof](../sdk05-current-shipping-20261124/receipt.json). No compiler, test, SDK build, application build, new download, CI operation, or independent authoring experiment ran in this lane.

## Result

The actual nested `MiniAppSDK/miniapp-sdk.json` is byte-identical to main12: SHA-256 `1b66e9111586a764617a47fafe8f71ac677c14743fc1d0df79290e3ac994cebc`, input `ace5ee5e40a1c4c8c17c2a3744b24ac2793b237e5a2cc9d5dfd3c31959c82d6b`. All 222 ordered source inputs and 25,661 declared file rows match, including 25 documentation files, 28 example source files plus their index, and 5,210 declaration rows. Both transitions, main12 source to main13 source and main13 source to this evidence base, have no Git changes among the exact 222 input paths.

The actual main13 snippet report again records four successful original validator projects, zero diagnostics, 14 source blocks and 7 JSON/config blocks, plus 8 explicit nonauthoring exclusions. Its only differences from the prior report are four temporary source-root paths. Compiler versions and type policies are unchanged: Expo and ScriptWidget use actual TypeScript 6.0.3; NativeScript uses 5.9.3 with its retained dependency declaration-body policy. This is evidence from the real prior CI command, not a local reexecution.

The nested ZIP container hash differs, so this receipt claims SDK manifest/content identity rather than identical ZIP bytes. Only the nested manifest was opened; the previous 112 selected-member byte checks were not repeated, and all SDK file bodies were not independently rehashed. Raw manifest, new report, container metadata, phase statuses, exact differences, and the inspection command are retained here.

## Publication fix audit impact

The pending native value-construction fix is owned separately. `audit-miniapp-sdk.mjs` reads `HanlinExpoWidgetPublication.swift`, stores its exact hash in both the publication producer and the source list, and rejects drift. `audit_miniapp_reachability.py` verifies that authority and embeds the same source hashes. Therefore run the existing inventory write/check and then the existing reachability write/check after integrating that fix; exact argv and inspected source excerpts are in [publication-audit-input-impact.json](publication-audit-input-impact.json). Neither generator was executed here.

The private native file itself is absent from the 222 shipping input paths. Its generated inventory and reachability documentation are present, so the next normal SDK preparation will receive a new input/manifest identity when those records change. This current equality statement must not be copied unchanged onto that later SDK. No additional ad hoc SDK rebuild or broad test suite is required by this receipt.

## Boundaries and preservation

Actual main13 paired acceptance records `build=EXECUTED_FAIL`, first application build exit 65, and `ai_build=NOT_RUN`, `ui=NOT_RUN`. No application test, native rendering, device operation, or successful publication is claimed here. Earlier example package-build receipts retain their original SDK attribution.

Only this evidence directory was changed. The owned approximately 81.8 MB nested-ZIP stage was removed after comparison; the parent artifacts, shared caches, and frozen SDK-only kit remain untouched. [receipt.json](receipt.json) is the concise machine-readable receipt, and [SHA256SUMS](SHA256SUMS) records every other file here.
