# Original extension SDK graph integration — 2026-11-23

The aggregate SDK now exposes **43 public products / 107 targets** with no remaining local-package edges in its generated public graph. `AI_Hanlin` continues to own all **502 original application Swift sources**; the executable keeps only its original app entry point. The five added extension products retain their canonical source owners described in [the extraction handoff](HanlinExtensionSourceOwnership.md).

## Actual executable integration

The original app, unit-test target and standalone MiniApps each link the Foundation-only `HanlinExtensionContracts` product directly. Each of the four original extension executables links its specific canonical public SDK product. All declared products are present in the corresponding real framework link phases; no declaration-only integration is counted.

Both widget executable configurations set `PRODUCT_MODULE_NAME = HanlinScriptingWidgetsHost`. The SDK implementation keeps `HanlinScriptingWidgets`, preserving the original AppIntent/AppEntity type names. Product name, bundle identity, widget kind and entitlements are unchanged. The full app implementation similarly remains `AI_Hanlin`, while its thin executable remains `HanlinApp`.

The main and MiniApps Info.plists declare the same original App Group, widget kind and notification category as their original extensions. Only main declares the original Vision route. A parsed property-list comparison verified that every pre-existing value stayed unchanged. `HanlinApplicationSystemIntegrations` adapts the public immutable extension configuration and no longer maintains another copy of the original identity constants. A missing or invalid current-bundle declaration disables those default system hooks; it does not choose another app's container.

The full original app intent marker includes `HanlinWidgetIntentsPackage`, which also registers the existing shared script actions. The lightweight MiniApps entry registers only `HanlinScriptExtensionIntentsPackage`; it does not pull in the full chat application.

## Per-host adoption

Lorvex and Maktabah's complete actual source trees were checked for default extension-store/client construction. Their selected chat closures have no such initialization, so this extraction requires no new host entitlements or App Group changes. Their native gates will use one coherent SDK source pin containing the resource repair and current original presentation code.

## Focused integration evidence

- Foundation-only extension-contract module: actual Swift 6 module typecheck PASS on Oracle.
- Full original runtime configuration importing that built module: actual Swift 6 typecheck PASS.
- Two original app intent entry files: syntax parse PASS; App Intents indexing still requires Apple.
- All selected original executable product declarations match real link phases, with no missing product links.
- Actual aggregate `swift package dump-package`: PASS.
- Project updater idempotency: PASS.
- All 15 existing graph regression tests: PASS on the corrected product manifest. The initial run exposed one stale expected MiniApps product list after adding ExtensionContracts. That exact list was updated; the final full 15 were rerun because negative controls need a valid positive fixture, not merely an assertion from an already-invalid graph.

The original extraction's 49 body-preservation checks, 35 syntax parses and resource hashes are reused from its checked-in receipt. The original preflight helper's 4 methods / 8 cases are reused from its source-identical receipt. No Host runtime tests or Apple tests were rerun here.

Diagnostic logs remain under `build/extension-wiring-20261123` on Oracle. Native compile, App Intents metadata, extension lifecycle, actual UI and saved-widget continuity remain separate acceptance obligations. The next exact native dispatch is the execution gate for this source.
