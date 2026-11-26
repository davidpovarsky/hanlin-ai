# MiniApps Shortcuts execution candidate — 26 November 2026

Base: PR19 c34dd6ae752b3ab3ebc001743fc62c72fc48a203. This branch has not replaced any active native acceptance or release workspace.

## Product boundary

`HanlinRunMiniAppShortcutIntent` is compiled only from `HanlinMiniAppsApp/`. It uses the existing saved action entity, App Group queue/receipt, request authorization broker, package store and original NativeScript/Expo runtimes. Hanlin AI receives shared SDK/codec fixes, with no additional runtime-management UI.

The new action supports text, Dictionary/List JSON, and a typed JSON `IntentFile`. AppIntents27 has no generic Swift.Dictionary `_IntentValue` conformance; the file/JSON path is explicit and must still be verified with real Shortcuts variable conversion. Results are actual returned text/JSON/binary files, not invocation IDs. Existing intents retain their identities and behavior.

LongRunningIntent/CancellableIntent use the installed iOS27 public APIs. Extended execution is off by default. The package can report real progress through `miniapps.reportShortcutProgress`; elapsed time is never reported as percentage. The OS controls runtime and may cancel or reject an extension. Queued work is cancelled when admission/preparation fails, never replayed after a failed Shortcut.

Each new invocation owns its platform/session, cannot replace a visible Expo controller, and does not steal the foreground widget drain. The canonical authorization broker routes a request by its originating invocation UUID. NativeScript retains its one-isolate admission; an unrelated occupied NS VM is a real limitation, not a claim of arbitrary concurrent VM isolation. Background Shortcuts does not acquire UI authority. Cancelled native callbacks release their waiter exactly once; malformed JSON now propagates an error instead of producing a successful null.

## Executed checks

- Exact canonical JSON source + codec: Swift6.4.3 Linux, 4 test definitions / 12 cases, zero failures (a28e977d06eb32d81f4fd4025e2ad5d90703a040 evidence).
- Exact callback completion helper: Swift6.4.3 Linux, 3 tests, zero failures. Tests cover cancellation before registration, cancellation during a wait, repeated/late callbacks. This is not a NativeScript VM test.
- Original NativeScript host-services generator: TypeScript5.9.3 strict declarations and JavaScript, original valid/live-activity fixtures plus original negative diagnostics preserved. New typed progress method generated with the existing tool.
- Changed application Swift syntax parsed by Swift6.4.3; parsing is not Apple compilation.

## Native gates still NOT_RUN

Build/typecheck the actual new MiniApps app target with the installed Apple SDK. Exercise NS and Expo saved actions, native input/result chaining, long-running progress/cancel/expiration, no-UI calls, foreground coexistence, same-ID duplicate delivery, crash/recovery and genuine device background behavior. Run affected existing queue/action/UI cases rather than rerunning unrelated passing suites. No simulator, device, signed archive or TestFlight result is attributed to this branch yet.

Installed Apple API evidence is retained at `/mnt/development/projects/evidence/hanlin-two-wave-storage-20261126/installed-ios27-api-receipt.json` (Mac owner). API source hashes and signatures are in that receipt.

## Remaining wave2 scope

Widget Toggle/families/transparency have a separate owner. Last-known-good refresh, developer editor/gallery gaps and full engine/surface acceptance remain separate work; this candidate does not close all13 Scriptable tasks.
