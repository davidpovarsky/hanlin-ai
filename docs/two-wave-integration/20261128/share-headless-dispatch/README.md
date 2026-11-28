# Preserve the owned headless path for Share delivery

The source commit adds one Share-source exclusion to the existing generic NativeScript foreground-application launch condition. Share continues in the host foreground, as its unchanged invocation envelope requires, while its existing canPresentUI=false and owned headless dispatch remain in force. Other delivery sources, including absent delivery metadata, keep the original behavior.

## Why this condition is needed

The original real two-session Share acceptance failed at the second iteration's unchanged 120-second terminal-receipt wait. Its retained failure-only observation showed the current installed generation/source/artifact, an active application/native session, and a queued receipt at attempt 0 with no lease or result. These sequential reads do not establish an atomic ownership snapshot.

The existing Share drain and dispatch guards defer delivery while a foreground NativeScript session owns the isolate. The generic foreground launch branch could recreate that session after the deliberate dismissal and before the intended Share handler dispatch. Excluding Share from that branch corrects this source-level contradiction. A repaired native outcome has not been observed for this source.

## What is preserved

Removing the single added condition recovers the whole original production file byte-for-byte. Existing generation, enabled-state, replay, cancellation, host-foreground and one-VM guards, handler invocation, adapter/session cleanup, and all original await/throw/defer/task lines remain unchanged. The original two-iteration acceptance still uses five real runtime calls per iteration, the original 120-second wait, 25 ms polling, full payload/result assertions, replay check and disabled-target rejection. No test file changed.

## Verification and remaining gates

The frozen packet and actual committed source blob were hashed, the whole-file inverse was verified, and git diff --check passed. The independent root review is retained verbatim. No test, Swift compilation, native invocation or SDK producer phase was executed for this candidate.

The one modified platform file belongs to the actual 396-input SDK closure. The other 395 inputs and all 99 direct Host inputs match the accepted base; the Packages tree is unchanged. A fresh SDK qualification on the eventual integrated source and the original real Share acceptance remain required. The old native failure stays retained and is not relabeled as a pass.

The manifest binds this compact proof, the lossless source patch, the exact source/input hashes, the independent review and the unchanged native-verification plan. The complete historical job log remains in its immutable technical evidence packet and is referenced by both raw and gzip SHA-256.
