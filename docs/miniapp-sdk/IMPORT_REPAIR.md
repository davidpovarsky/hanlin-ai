# MiniApp authoring diagnostics and repair

## Product scope

Expo/React Native/Expo UI, NativeScript, and ScriptWidget use their original host libraries and the matching packaged declarations. Legacy Scripting-JSC/ScriptUI development is frozen; existing package data and existing execution paths are retained. This change does not introduce a custom home entrypoint or extend the optional full Apple SDK metadata generator.

## Import and diagnostic flow

`HanlinScriptingPlatform.importPackage` keeps an owned copy of the original archive before staging, so an invalid ZIP or manifest can still be sent for repair. A source-bearing archive with `hanlin.authoring.json` is revalidated through `MiniAppAuthoringService` and the installed original Node/TypeScript SDK. The import path does not trust a build report bundled by the sender.

Source files alone do not trigger the original compiler check. The root `hanlin.authoring.json` descriptor identifies the recognized authoring project and its configuration; every successful `build_miniapp` build supplies it automatically. Archives without that descriptor receive package and runtime compatibility inspection, even if they retain `.ts` or `.tsx` files. They are not reported as having passed original-source TypeScript validation.

The native `MiniAppImportDiagnosticsView` presents package findings and compiler diagnostics together, grouped by file. It exposes stable diagnostic codes, severity, one-based line/column, the original message, and available remediation. Errors automatically open an item-based SwiftUI sheet after import completes; the same sheet can be reopened from the importer. A failed source typecheck prevents installation of that candidate.

A bundle-only JavaScript archive cannot reveal erased TypeScript types. Its compatibility findings are displayed honestly; the UI does not label this as a successful original-source typecheck. Invalid archive and validation-execution failures also remain distinct from source diagnostics.

## Repair handoff

The repair button saves the exact original archive and structured diagnostic JSON in the two products' existing shared transport directory. The request is published atomically under a UUID and bound to the archive SHA-256. The receiving app verifies the bytes against that digest. This establishes transfer consistency, not publisher authenticity.

The wake routes are:

- `chavrusachat://miniapp-authoring/v1/repair/<uuid>`
- `hanlinminiapps://miniapp-authoring/v1/install/<uuid>`

Only the identifier crosses the URL boundary; archive and diagnostic contents remain in the existing shared transport. The AI receiving window claims the request, creates or reopens a dedicated conversation through `HanlinConversationCreation`, and prepares an editable project in the original agent runtime workspace. Even if extraction fails, the original archive and the extraction error reach the agent.

The original mounted composer and its first-turn state machine dispatch the request. This preserves the ordinary model selection, original agent pipeline, unsent Home draft, and conversation settings. A durable user-message marker and transfer receipt prevent duplicate sends after reopen. Requests for the same receiving window queue behind its active handoff; a failed/cancelled handoff can be retried. Closing a receiving window releases its in-memory claims.

The agent receives the actual workspace paths and full diagnostic JSON. It reads the installed SDK, edits the original source, validates with the real compiler, builds with the original engine's toolchain, and sends the resulting archive to MiniApps. No new approval prompt is introduced by the authoring or repair tools.

## Installation receipts

Receipt states are `queued`, `received`, `submitted`, `installed`, and `failed`. Repair submission and package installation are different outcomes. Opening a companion URL is never treated as proof of installation.

Imports are serialized in the receiving process and deduplicated by transfer ID. Before installation, the receiver checks that the current preview belongs to the requested archive. It uses the regular importer and installer, then requires an actual stored package with the same source digest before recording `installed`. The agent can query that receipt through `import_miniapp(transfer_id: ...)`.

The transfer store retains the original payload and final receipt across process launches. Retrying an already installed request does not reinstall it. No unrelated package or conversation is removed by this workflow.

## Verification

The exact portable transfer implementation and five behavioral tests were executed with Swift 6.4.3 on Linux. The log, toolchain, source hashes, and result are recorded in `evidence/authoring-repair-20261123/transfer-tests.json` and its adjacent log.

Native acceptance additionally covers the actual original composer, malformed archive diagnostics, the source compiler service, the SwiftUI sheet, and both product targets. Portable tests and syntax parsing are not substitutes for Apple compilation or simulator execution. The native acceptance receipt records those outcomes separately.
