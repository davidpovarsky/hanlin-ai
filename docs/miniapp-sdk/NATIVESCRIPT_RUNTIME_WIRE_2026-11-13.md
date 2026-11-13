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

First native attempt43389506393/2647ee1d failed app compilation before any
selected test executed: the old HanlinNativeServicesHostProvider also conforms
to the expanded protocol. It now explicitly rejects generic execution/cancel
through its mutable singleton; modern provider-bound adapters implement the API.
It owns no generic requests to invalidate. Forwarding a new handle through a
mutable legacy provider would allow caller/ownership changes between admission
and completion. Existing legacy string methods remain unchanged. New regressions
require this explicit rejection and prohibit cancelling a bound handle through
the legacy singleton. Full native execution and failed diagnostics UI still
need a corrected run; no test pass is attributed to the compile-only failure.

The new methods are in a separate source file extending the existing
HanlinUnifiedHostServicesE2ETests serialized suite. A separate top-level
serialized suite would still race that suite's process-wide NativeScript registry
resets/VM lifetime in broader acceptance. Test members in extensions share the
primary suite; no second Suite annotation is added. Official source:
https://github.com/swiftlang/swift-testing/blob/main/Sources/Testing/Test%2BMacro.swift
The in-flight f9c1b62f run retains its original top-level selector; the next
focused run must use the new exact parent-suite method identities.

Second native attempt43391695133/f9c1b62f compiled the production files but
failed test-build before any selected case executed. Swift6.4 rejected the
MainActor AsyncSequence.first predicate transferred inside #require. The reply
now awaits a stream iterator first, then checks the Optional synchronously;
no assertion or cancellation condition is removed. Portable Swift6.3 strict
concurrency typechecking of that iterator boundary passes, without claiming
Swift Testing or Apple native execution. The next corrected app run is needed.
