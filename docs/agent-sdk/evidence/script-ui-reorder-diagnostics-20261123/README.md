# Accurate ScriptUI duplicate diagnostics — 2026-11-23

This follow-up to `dcc017c0` fixes a review finding in invalid-input error reporting. Both original diff guards and the initial reorder admission fix used the first key as the `duplicateKey` payload; `[a,b,b]` therefore reported `a`. The actual repeated key is `b`.

One private `validateUniqueKeys` now walks the existing `Set<String>` identity rule and throws the existing `HanlinScriptUIError.duplicateKey` for the first key actually repeated. The old/new diff trees and current/requested reorder keys share it. The missing-key guard, key-set comparison, public error signature, patch construction, dictionary construction and valid output implementation are unchanged. `source-preservation.json` proves that restoring those four calls and removing the private helper restores the entire prior source byte-for-byte.

## Exact newly affected execution

Four new regressions assert `duplicateKey("b")` for `[a,b,b]` at each of the four admission boundaries. The existing valid reorder/property-update/empty-tree control also ran because its admission implementation changed. **All five selected cases passed**, zero compiler warnings, Swift6.4.3 with complete concurrency checking on Oracle arm64 Linux. Total33.75s includes a fresh32.60s build. The raw filtered command, original source inputs, XML and log are retained.

The original six-case receipt at `../script-ui-reorder-admission-20261123/` is unchanged, including its original SIGTRAP reproduction. Its evidence files were hash-checked before and after this follow-up. Those six results remain bound to `dcc017c0`; they are not relabeled as a fresh six-case run. No unrelated previous methods or broad suite were replayed.

The proof compiles complete canonical PlatformContracts and the entire Foundation-only ScriptUI contract/reconciler files with the actual test source. Full SwiftUI/Charts/WebKit, the Apple model and native UI were not run; no CI was dispatched.
