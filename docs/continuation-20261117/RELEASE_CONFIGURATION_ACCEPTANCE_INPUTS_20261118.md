# Original simulator acceptance configuration correction

Status: source fix; native verification pending.

## Actual evidence
Run 44243185407 at 00a932d63db76549dff0a228a6b75711fcad8a22 built and tested Release with the existing explicit HANLIN_TESTING compilation condition. It did not compile DEBUG. The raw xcodebuild command and recorded configuration establish this directly.

Newer isolated native A2UI inputs, the original persisted phase-2 test store/status, contextual Canvas/text inputs and retained engine-component entry used DEBUG-only guards. The classic fixture remained enabled on the simulator, so actual CPython produced its expected nonce/result, but its new identity/reopen proof was absent. All seven native A2UI cases stopped before the isolated seeded chat; engine component cases stopped before the host catalog. These are not successful product acceptance results.

## Correction
Use the workflow's existing HANLIN_TESTING condition, still restricted to the simulator and explicit per-case environment opt-in, for those already-isolated acceptance inputs and diagnostics. MainTabView preserves the prior DEBUG behavior and additionally recognizes that simulator test configuration. Ordinary device Release builds retain no such entry or fixture. No model output, consent grant, runtime result or UI assertion is manufactured; production engines, storage adapters and native controls are unchanged.

The App Group ingress fixture receives the same consistent condition. The separate live-account input remains blocked by credential-export approval; compiling it does not authorize or run it.

## Other failures remain separate
The original conversation ownership crash, native iPad navigation queries, Skill Center/resource assertions and Motion simulator selection require their own diagnosis and evidence. This correction does not label them fixed.
