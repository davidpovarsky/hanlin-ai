# Notification delegate code generation correction

The actual MiniApps build on integrated source 9ef80a6d reached the application
compiler after cache and ABI repair, then Swift 6.4 crashed while lowering the
optional Objective-C async foreground delegate call to SIL. No native app case
executed in that failed build.

The original 450-argument frontend command was replayed with the complete
actual app source/import/C++ interoperability context. Only primary-file and
output locations were reduced to one delegate source. The unchanged original
source reproduced SIGABRT (exit -6) in 1.665 seconds. The corrected source emitted
a real arm64 Mach-O object in 1.242 seconds with zero diagnostics. The final
receipt hashes the exact committed source, compiler command and object. Complete
original inputs/logs/objects are in the separate archive described by its receipt.

The async entrypoints and Host event delivery order remain. Forwarding now uses
Apple's original optional completion-handler methods and checked continuations.
The original delegate supplies the exact imported Int presentation bits; no
conversion or fabricated completion is inserted. Missing methods retain the
current Host's zero/void fallback. Dismiss filtering and settings forwarding
are unchanged. The code waits for an implemented original delegate's completion.

Apple documents both the completion and asynchronous forms:
https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate/usernotificationcenter%28_%3Awillpresent%3Awithcompletionhandler%3A%29
https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate/usernotificationcenter%28_%3Adidreceive%3Awithcompletionhandler%3A%29
The implementation was also checked against the installed iOSSimulator27.0
UNUserNotificationCenter.h, not a replacement protocol.

This proves compiler code generation for the correction. It is not application,
notification OS-ingress, 23-case MiniApps acceptance, signing or TestFlight proof.
