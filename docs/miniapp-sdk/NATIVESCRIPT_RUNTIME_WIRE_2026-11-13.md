# NativeScript canonical runtime wire

[נועם | DEV] [MAIN_SESSION]. INT-03 / SDK-03 remain open.

The existing NativeScript metadata bridge now exposes asynchronous
executeRuntime(payloadJSON, completion), returning a host-issued cancellation
handle. Its callback contains the entire canonical RuntimeExecutionResult JSON:
stdout/stderr/value/exit code/timing/cancellation/truncation/artifact receipts.
Node, TypeScript, localPython, JavaScriptCore and linked Shell all route through
the existing HanlinRuntimeBroker; Expo runtime.execute uses the same typed
JSON boundary. Unknown kinds/malformed options fail before execution. Shell source is a
complete approved command; separate argv is rejected rather than ignored.
This does not add arbitrary shell commands or another runtime.

The generated @hanlin/host-services facade captures the actual bound Objective-C
session bridge. Its typed createHostServices().executeRuntime returns a Promise;
startRuntime returns a result Promise and session-owned cancel handle. Another
package cannot cancel that handle; invalidation cooperatively cancels in-flight
work and suppresses callbacks into the invalidated NativeScript session.
No synchronous run-loop pumping or implicit20s deadline is added. Existing
legacy callbacks retain their historical signatures and string results.

Source: Scripts/NativeScript/host-services.ts. The existing pinned TypeScript5.9.3
compiler strictly emits both index.mjs and index.d.ts; no any/ts-ignore/skipLibCheck
is used. build-host-services.mjs --check verifies byte-identical generated output.
The existing dependency preparation runs this check and stages those exact
modules into its atomic replacement, preserving the module during preparation.
No npm dependency or native engine version changes.

Six new native methods require actual execution: bound ObjC five-engine receipts
plus exit23; arguments/env/full-output-artifact SHA; unknown/malformed/revoked
requests; cancellation ownership after actual Node source starts; shared Expo
structured invoke; and a real NativeScript VM importing the generated module
and asynchronously invoking all five engines through actual metadata.
Local parse and pinned strict TS generation/drift checks passed. These are not
Apple-framework compilation or native VM execution evidence.

Single-active-NativeScript-session guard remains; safe queued cross-package
action scheduling, full system-ingress readback and physical iPad acceptance
are still required. OS availability/permission and all prompt context gates
remain separate. No new Hanlin permission gate is introduced.
