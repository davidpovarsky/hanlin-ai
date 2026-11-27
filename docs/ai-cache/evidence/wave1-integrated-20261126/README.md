# Integrated Wave 1 cache validation — 2026-11-26

All current executions here use immutable integrated source
a30c8267c1f5ce2a122889b81dc9fffc0f295758.

| Scope | Result | Evidence |
| --- | --- | --- |
| Original native ChatCore and producer cache suites | Fresh PASS: Swift Testing reported 4 + 44 = 48 tests | core/acceptance.json, original-runner-receipt.json and compressed raw log |
| Original public assistant/facade JavaScript tests | Fresh PASS: 7 + 8 = 15 tests, no failures, cancellations or skips | js/receipt.json and original command logs |
| Strict NativeScript facade generation and declarations | Fresh PASS: TypeScript 5.9.3 compiler and generated-output drift check | js/nativescript-generated-check.log |
| Original local cache and usage accounting | REUSE_ACCEPTED for 18 prior tests; no new execution | local-cache-reuse.json |
| Application cache acceptance | Current source inventory ready; native app gate pending | app-cache-source-inventory.json: 46 methods / 48 invocations |

The native run used the unmodified original run_cache_native.py script and its
original test filter, complete canonical production/test source targets,
original producer fixtures at SwiftAI SDK abf0921c6e89e6521cc2b510ff11016b45a0ef08,
and the exact four canonical dependency pins. Every recorded source hash
remained unchanged and the source checkout remained clean. The current routing
test retains its original function selector with a changed display name and four
explicit saved-dialect arguments. The raw log records all four arguments and
the passing parameterized result. This difference from the older evidence is
recorded in core/acceptance.json.

The JavaScript run compiled the original public facade without rewriting any
source or generated output. Only the exact consumed dependencies from the
canonical npm lockfiles were installed in isolated validation folders:
TypeScript 5.9.3, the locked TypeScript 6.0.3 VM implementation through its original
wrapper, and base64-js 1.5.1. All snapshot source hashes were checked after
execution. These tests exercise original facades with the original test fixtures;
they do not establish native runtime or live-provider acceptance.

Local reuse is narrowly justified by identical bytes for all nine production
files and two original tests, the same LRUCache 1.3.0 revision, the same Apple
Swift toolchain, and the preserved original raw-log hash. It does not certify
the application, SwiftData, UI, live cache hits or billing.

The parent queue owns the full native app gates. The exact Composer selectors,
source hashes, per-device UI selections, native editor argument selector and
current-cache runner route are prepared in
docs/composer-capabilities/evidence/wave1-integrated-20261126/native-handoff.json.
Prior Composer native-engine and UI failures remain failures until those
affected gates run against the current source.
