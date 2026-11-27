# Original Promise continuation ownership repair

## Observed failure

This candidate responds to the actual unfiltered 603-test run at source `778ed7e597a2fe19708e1dde5598350b56b25d6d`, attempt r2. The original HTTP method still failed under its original five-second execution limit. This is source review evidence; the repair has not run natively.

The source-bound raw packet is `handoff/original-http-778ed7e5-callbacks-r2`, manifest SHA256 `7bb6741149899e5cd8de9f6da341ce0679394c99a3794d909df4152eb2849326`. All 15 members were independently checked for exact length and SHA256. Raw JSONL is retained losslessly with encoding/hash metadata in this directory. The separate full native run and earlier failed attempts remain retained by the Mac execution owner.

For actual process 22526, session `CD0B812C-F4D9-4C0A-9229-A099BE8DBE9C`, request 37 returned 2,097,152 bytes at epoch 1795780824.039637. Conversion and the original guarded handoff completed at 24.041562; the original delivery ran at 24.042762. Its existing managed-value reads reported both resolve and reject absent at 24.042797. The original active/current guards passed and the optional call site returned at 24.044686. The timeout occurred about five seconds later, at 29.044822. The prior 33 verb/budget and three response deliveries had both callbacks present.

This identifies missing continuations at the actual failing call site. It does not retroactively prove identical causality for every earlier timeout, or make the DEBUG diagnostic a successful product acceptance.

## Ownership correction

Apple documents [conditional JSManagedValue retention](https://developer.apple.com/documentation/javascriptcore/jsmanagedvalue.md) and the requirement that an [external managed ownership graph be reachable from JavaScript](https://developer.apple.com/documentation/javascriptcore/jsvirtualmachine/addmanagedreference(_:withowner:).md). Native ARC retention of a captured Swift delivery alone does not register that entire graph.

The pending delivery now holds its two actual JSValue continuations until one settlement or execution cancellation. This intentionally creates a temporary VM root, with explicit termination:

- The session tracks deliveries weakly in a separate registry; it does not extend native operation lifetime or consume the existing eight-query cancellation allowance.
- Native `finish` only queues the original callback. Its registry entry survives until actual delivery, so cancellation also releases continuations while delivery is queued.
- `takeCallbacks` extracts and clears the pair under the delivery lock, then unlocks before removing the weak session entry. Callback calls and final releases occur outside both locks.
- Session cancellation snapshots its weak entries, clears all registrations under its original lock, and invokes delivery cancellation after unlocking. Existing URLSession task cancellation and native-query cancellation then retain their original order.
- Settlement, explicit cancellation, timeout, supersession, normal finish, and wrapper-install failure all release the pair. Delivery deinitialization removes any weak registry residue.
- Existing callback queue, at-most-once decision, execution-active check, current-generation check and error text are preserved. No callback is invoked from cancellation.

The runtime's existing widget, Dynamic Island and function entry points all call session finish in defer and cancel on the original timeout. The existing public original session's cancel/finish routes also reach this cancellation path. These callers are unchanged.

## Diagnostic removal and invariant proof

Fetch is restored byte-for-byte to SHA256 `8a7bb65bffe0390ac719e33b0ece71e19b20e9be96841e422a3a4c37f09352b3`. The HTTP test is restored byte-for-byte to prediagnostic SHA256 `433703973e69d764686c6761ad1851c40d76f5e53afa4561d1720d873a5a1ae4`. Thus the temporary DEBUG boundary logger, logger reader bridge and dump are absent from the proposed final gate. Original test stage/live-path evidence remains.

The original 601 assertions and two additional Promise controls remain intact. Those controls still check pending callback delivery, exactly one result, duplicate suppression, cancelled late callbacks and final context disposal; immediate collection is only observed because conservative roots may survive a public GC call. The original full 2 MiB HTTP assertion is the actual regression that reproduced the loss. No extra test method or deadline is added.

All 259 canonical provenance entries match candidate/source bytes. Only three localSHA256 fields change; upstream pins, upstream blobs and the other provenance fields are unchanged. The measured historical SDK input path set contains the three runtime files and provenance manifest; the test file is outside it. A fresh affected producer and native qualification are still required.

## Status

Source candidate only. No repair-native PASS, OS acceptance, full603 success, Host188 refresh or device success is claimed. Root and independent review receipts bind the exact five-file source patch before integration.
