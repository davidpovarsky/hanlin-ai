# Paired original consent fixture repair

The original paired run45283243206/1 at4cfa52348e80cf635caf04c541fd84ee1ddb50bd failed while its review-toggle was not hittable. This patch does not claim a wrong approval button was tapped in that run. The later allow-once selector is a separate source-proven mismatch that would remain after the product viewport repair.

## Original consent contract

The HTTP fixture emits open_mini_app with exactly target hanlin.demo.swift-parity, action share.value and payload null. HanlinAppHostIntegration116–138 requires its original scoped Host grant before cross-app dispatch. HanlinAppToolConsent derives remembersDecision from the non-nil scope and persists only an explicit allowed answer. Provider-only requests use a separate nil-scope, one-use path. The old sheet used the accessibility ID allow-once even when its visible label was Allow and remember; the shared inline component exposes the correct allow-remember ID.

AX22/24/26 show the persistent permission explanation, collapsed details and disabled allow-remember. AX28 shows the same call Not approved and PAIRED_RESULT_NOT_VERIFIED; the application log166830 reports only mode=open reason=unexpected_tool_output. This is not proof of MiniApps dispatch or successful return.

## Narrow fixture change

Only AI_HLYUITests/HanlinPairedProductUITests.swift changes. Before each paired request, the test uses the original Settings→Tool permissions UI and revokes only the exact open_mini_app grant if present; multiple indistinguishable matching grants fail setup. No broad revoke, defaults mutation, permission injection or production change is introduced. This is necessary because phase2StoreID isolates SwiftData while remembered permissions intentionally span conversations in the same Hanlin account/workspace.

The original request must expose allow-remember disabled before review. The test opens the real original details, preserves the nonempty-request check, decodes that displayed JSON and requires the exact target/action/null-payload fields. Its pre-review existence allowance uses the original45-second readiness bound. It then taps the exact persistent approval control through the existing hittability gate. It does not choose whichever approval control happens to exist.

Both original return/cancel cases additionally require neither approval ID to remain after the original result. Their real companion foregrounding, value/state, original-conversation identity, error absence, timing, and result assertions are preserved. The transfer case and native typing/result-wait helpers are byte-identical. Pending-consent diagnostics recognize both legitimate IDs.

No transcript scrolling, bottom-button tap, coordinate tap, timeout increase or autofollow fallback was added. The permission-settings list is navigated using its existing shipping scroll/revoke/back flow; this occurs before the request. Profile is a native sheet, so its original Done control must dismiss before the Home tab can be selected. Root separately owns the observed viewport/backdrop defect. Autofollow acceptance remains open.

## Verification boundary

Local Swift frontend parsing passed on the initial candidate and on the final reviewed source after the readiness/navigation corrections. This proves syntax only; no XCTest API typecheck, Apple build, simulator case or integration acceptance was executed. The original three case bodies were compared mechanically: return/cancel differ only by the added post-result pending-permission absence assertion; transfer is identical. Native execution of the two affected paired cases remains NOT_RUN.
