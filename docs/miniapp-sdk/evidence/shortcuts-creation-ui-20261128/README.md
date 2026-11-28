# Observed Shortcuts creation UI

The original saved-action helper failed before creating a system shortcut in both NativeScript cases from run 46095649694. The background case's own Shortcuts accessibility tree and screenshot show the What's New in Shortcuts sheet and its Continue button. The foreground case's own tree shows the New Shortcut creation button. The original helper searched only Create Shortcut and Add.

This change is confined to the creation segment of the existing runMiniAppShortcut helper. Within the original single 12-second wait, it may tap Continue once only when the exact observed heading and the owned app's enabled, hittable button are present. It waits for that heading to disappear and then requires an actual enabled, hittable creation button. New Shortcut joins the two existing labels. All later saved-action, parameter, mode, invocation and typed-result assertions remain unchanged.

All 37 original test methods and their bodies are preserved; the exact inverse recovers the full original source file. Existing case deadlines, workflow commands, observer guards and product code are unchanged. The root independent review is retained verbatim.

SOURCE_PROOF.json binds the exact source, inverse and review. CAUSAL_EVIDENCE.json identifies the retained own-case accessibility trees, screenshots and full failed log by original artifact member and SHA-256. Those raw native artifacts remain in the authorized handoff; this compact packet does not repackage screenshots or private project notes. source.patch.gz is a lossless copy of the reviewed patch.

Native acceptance of this change: NOT_RUN. No new portable or native test was executed for this source-only UI repair. The required next gate is the original whole miniapp_shortcuts_os four-case route on the integrated source. These observations do not imply that onboarding was dismissed, a shortcut was created, or any action executed successfully. The two Expo cases in the historical route failed earlier at catalog readiness.
