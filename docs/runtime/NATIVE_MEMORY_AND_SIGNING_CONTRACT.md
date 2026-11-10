# Native V8 address space and main-app signing

[נועם | DEV] [דנה | SEC] [MAIN_SESSION]

The current pinned DrumBrake build requires compressed tagged pointers. Its
actual source declares both the cage reservation and alignment as `1 << 32`
(4GiB); the allocator terminates the process if that reservation fails. The
actual pinned configure script enables the shared cage with pointer compression.
This is virtual address space, distinct from committed physical memory.
Sources: [pinned V8 constants](https://github.com/heylogin/nodejs-mobile/blob/4768489cd0cfa3bb0c27786e958c6446c004f1bd/deps/v8/include/v8-internal.h),
[pinned isolate allocation](https://github.com/heylogin/nodejs-mobile/blob/4768489cd0cfa3bb0c27786e958c6446c004f1bd/deps/v8/src/init/isolate-group.cc),
[pinned configure](https://github.com/heylogin/nodejs-mobile/blob/4768489cd0cfa3bb0c27786e958c6446c004f1bd/configure.py).

Hanlin also initializes JavaScriptCore and WebKit. Their reservations share the
main process address space. This delivery therefore requests
`com.apple.developer.kernel.extended-virtual-addressing` in the **main app** and
requires its presence in the authorizing profile and actual exported signature.
Apple documents this capability for applications needing more address space.
It does not establish an unlimited physical-memory budget or successful device
allocation. [Apple entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.kernel.extended-virtual-addressing),
[Apple capability reference](https://developer.apple.com/help/account/reference/supported-capabilities-ios).

Apple DTS distinguishes virtual-address exhaustion from physical footprint and
recommends measurement. Its reported JSC reservation issue was addressed in the
iPadOS26.6 beta5 timeframe; that report is not evidence of an ongoing OS27 bug or
a Hanlin device crash. The project requirement here follows the actual current
V8 allocation plus this application's mixed engines.
[Apple DTS](https://developer.apple.com/forums/thread/826325).

Main Node startup now explicitly passes `--jitless --wasm-jitless`, matching the
native interpreter smoke launch. The shared original JavaScriptCore and Node
coexistence/mode test remains an actual app obligation. Extension entitlements
and physical-memory allowances are unchanged; they do not host this V8 service.
No allocation stress loop or private entitlement-inspection API is shipped.

## Actual previous signature and remaining signing gate

Read-only inspection of the real93401 artifact from run42728397166,
artifact13726597810, found Extended Virtual Addressing absent in the decoded
main profile, embedded profile and signed main entitlements. The actual outer
archive hash matched GitHub:
`875df0b6d7480eabf43350b3945ded1c3f5dfabe65ce9047901effa5246790fc`.
Only safe Boolean/provenance summaries are retained in
`build/runtime-virtual-address-evidence/previous-profile-report.json`.
The existing main profile secret metadata was last updated2026-09-14,
before93401; the currently configured profile therefore needs renewal for this
new requirement. Secret contents were never retrieved or printed.

`verify_runtime_memory_entitlements.py` checks the requested requirement against
the decoded main profile before signing and against the real signed main app
and embedded profile after export. The actual old profile is correctly rejected;
five adversarial/repository contract cases pass. The workflow keeps all existing
cryptographic signature/team/bundle/group checks. The helper's own output always
distinguishes these contract checks from physical allocation acceptance.

Before the next **authorized signed build**, enable the main App ID's Extended
Virtual Addressing capability, regenerate the main profile using the existing
paid-team certificate, and update only its existing profile secret. Confirm the
new profile, exported signature and this gate. No signing identity is replaced,
account mutation or distribution performed by this preparation.

Physical acceptance must cold-launch both engine orders, use real Node workers
with original chat/math/browser and ScriptUI/Expo, and exercise background/lock
return. Record the device/OS, actual signed build and observed outcome. Simulator
execution cannot prove physical address-space admission or jetsam behavior.
