# Original NativeScript acceptance failures — 2026-11-25

Source: authenticated GitHub run 45325776062, artifact 14892950855.
Archive SHA-256: 62d58891f58680d24a206332fcd148593d1c8fd72222b84076e811c6adca01c6.
Size: 310372983 bytes. Original xcresults, screenshots, accessibility trees
and simulator logs remain under the Oracle evidence directory
/mnt/development/projects/miniapp-cross-app-evidence/45325776062/original.

## Two window cases: import validation, before window execution

Both original window tests fail at line 182, Install.isEnabled.
The retained accessibility trees 131FEFB2-8871-4FE8-B513-C341AAB06A2A.txt
and 823F9E76-8549-4F35-8A92-83DA046405AF.txt report:
“NativeScript hanlinNativeScript must declare string runtimeVersion and object plugins fields.”
The disabled Install button is also visible in the original screenshot
A706FB45-B026-409E-8F04-2600BE7E6E03.png.

The fixture generator omitted plugins, which the production validator correctly
requires. Its manifest now declares plugins:{} and uses the current original
engine versions from dependency-lock.json. No production check or UI assertion
was removed. These historical cases provide no native multiwindow pass evidence.

## Production nonce: startup did not reach the original native root

The original runtime logs reach HANLIN_NS_RUN_MAIN_BEGIN at 05:24:42.011,
then [HanlinScriptParity] Bridge resolution at 05:24:42.074. They do not
reach HANLIN_NS_RUN_MAIN_OK before failure. Accessibility file
C09DD926-6641-4D2F-B74B-B5B368F0E6DF.txt still describes the catalog.
The original loose title predicate matched the catalog's package name, not
the NativeScript root. It now requires hanlin-script-parity-title, the actual
root identifier, on first launch and relaunch. All JavaScript/Node/Python,
HTTPS, callback nonce and private-storage assertions remain.

The startup stop is consistent with the synchronous bridge/main-GCD nested
runloop deadlock independently reproduced and fixed in PR19. Integration
contains that CFRunLoopPerformBlock correction. Its focused native bridge
proof is not a substitute for re-executing this complete original app test.

## Validation boundary

This diagnosis comes from original native evidence. Fixes still require the
integrated current producer's real iPad simulator gate. No old native pass is
reused across the changed engine/SDK/toolchain.
