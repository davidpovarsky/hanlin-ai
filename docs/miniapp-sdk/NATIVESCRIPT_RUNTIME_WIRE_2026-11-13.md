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

Atf9d264af, run43394275453 compiled both production app and test host and
executed21 unit methods:19 passed,2 failed (68.824s total). Actual passes include
11 existing NS lifetime/registry/real launch cases,4 new wire methods (Expo five
engines, full output SHA/argv/env, invalidation, cross-session cancellation),
3 Expo entry constructor methods and1 real npm generation method. This is not
overall run success. Missing type:module in the new VM fixture was an initial
suspect; adding it did not fix the entry failure in the next native run.
The bound bridge test incorrectly used
String.contains("") to assert the JSC case's empty stdout; it now requires empty
stdout explicitly and retains the exact structured Unicode value assertion.
Both failed cases must execute again. The shared minimum-version session change
at65415324 also requires4 new constructor methods and affected real launch cases;
unaffected passing cases are retained with their own evidence SHA, not rerun
solely because the workflow had other failures.

Run43402191132/86ef18ed executed10 unit methods:9 PASS,1 FAIL in29.673s,
plus the actual diagnostics UI PASS109.431s. Bound ObjC five-engine/full-value/
exit23 receipts now PASS29.005s. All4 version constructors PASS0.069s,
3 Expo entry methods PASS0.040s, existing real NS launch/teardown PASS0.463s.
The facade VM still fails before executing its module: the SDK requests
bundle.js.js even though this package declares bundle.mjs.
Authenticated artifact14026324215 (70694376B), downloaded SHA256
6ab6c165db2ef4964c73cd171e69a868b9cc8e2ebfdb3da09cace7e9d85e6575.
This remains an overall FAILED run; no facade VM pass is inferred.

NativeScript9.1.0 upstream source Runtime.mm retains process-global
AppPackageJson/AppConfigCache after runtime destruction; ModuleInternal.mm's
ResolveMainEntryFromPackageJson uses the cached main. The earlier lifecycle
fixture declared bundle.js, poisoning subsequent bundle.mjs selection.
Sources at the pinned SDK release:
https://github.com/NativeScript/ios/blob/v9.1.0/NativeScript/runtime/Runtime.mm
and https://github.com/NativeScript/ios/blob/v9.1.0/NativeScript/runtime/ModuleInternal.mm .
No private cache hook or unsupported native symbol is used. Hanlin already
requires a prepared bundle.mjs file; all8 prepared source packages declare it.
Import and direct launch now explicitly require that exact main/runtime pair.
Alternate main names are rejected with remediation before VM creation. The
lifecycle fixture keeps its original two-session/data-isolation assertions but
uses the canonical ESM entry, without a duplicate bundle.js fallback. New import
and constructor negatives cover other/malformed/escaping/missing entries.
The unchanged native SDK still has its general config-cache limitation; arbitrary
cross-package app config/main support is not claimed. Corrected real VM and
two-session tests must execute again under this explicit prepared contract.

Environment ownership correction: shutdown previously unset every declared key,
even for a session that never started, and discarded pre-existing Host values.
Start now validates POSIX key/value representation before mutation, snapshots
the exact previous C bytes and records only successfully installed keys. Teardown
restores them after the VM shuts down; failed start rolls back, and dormant or
repeated shutdown cannot alter another owner. Two new actual-VM methods in the
existing serialized suite cover active/dormant/rejected second session, Unicode
previous values, new-key removal, idempotent shutdown, bootstrap failure and
invalid environment. Native execution is pending. Process environment is still
shared with other engines; this does not claim process or concurrent-env isolation.
