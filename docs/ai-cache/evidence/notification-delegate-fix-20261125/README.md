# App08 notification delegate compiler repair

One production file changes, from frozen App08 source1ae93941. Existing async delegate entrypoints and Host ingress remain. Calls to the optional Objective-C async imports are replaced with checked continuations around the original, installed-SDK completion-handler selectors. Registration executes in current isolation; only the continuation crosses the completion queue. The optional Void return detects an absent selector, never a callback that has merely not fired yet.

The previous delegate keeps its foreground presentation decision and response completion. Default/custom notification ingress, dismissal forwarding, enqueue-before-forwarding and settings forwarding remain unchanged. No unsafe Sendable annotation, new Task, suppression, alternative route, package or graph change is introduced.

The original Apple header was read from retained repository SDK evidence. The prior compiler errors are parent-reported actual App08 diagnostics; this agent did not run a native build or test. Exact source semantics were independently reviewed by native_bridge. `git diff --check` passed. The parent remains the native validation owner.

The delegate is included in the original stage-sdk native fingerprint, so the parent must refresh/check prepared Host authority through the existing producer before claiming matching archive provenance. This artifact does not claim any fresh native or runtime PASS.
