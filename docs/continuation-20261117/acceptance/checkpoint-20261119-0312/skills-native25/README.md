# Native Skills and offline policy verification — run 44429654565

Status: VERIFIED_NATIVE_SUBSET_PASS. GitHub run and full artifact digest were independently matched; all ZIP member CRCs passed.

- Run: https://github.com/davidpovarsky/hanlin-ai/actions/runs/44429654565
- Recorded source: 3a87634b8b478833ddd90c896fe494bd4becda82
- Runtime producer: 42926628418
- Artifact: 14494480413, 2,592,144 bytes, SHA256 a1a893e852f679288f523de367bd2ae1b33b664656ca7847e71b0748d9a653e1
- Device: iPad Pro 13-inch (M5), iOS 27.2 Simulator, arm64.
- Exact selected methods: 4; expanded native cases: 25 passed, 0 failed.

The raw tree includes all 22 generated ZIP argument cases plus the three unparameterized methods. These generated fixtures are not counted as maintained real Skills. native-tests.json retains the exact selectors, arguments and original durations.

The embedded Node 24.5.0 witness records ios/arm64, --jitless and --wasm-jitless; all 28 original policy cases / 64 assertions and 11 adapter contracts pass. Its offline boundary was installed before importing the policy; all six self-checks pass, network/installer/process attempt counters remain zero, and restoration succeeds. This is scoped policy-boundary evidence, not whole-app airplane-mode or physical-device acceptance.

Both hidden-resource and reinstall native cases pass after requiring VERIFIED with the same real receipt before mutation, identical argv after mutation, and preservation of historical receipt. The original instruction policy-failure isolation and current load/read/SDK continuation tests also pass. The raw witnesses and exact line numbers are retained.

The authenticated diagnostics build provenance records sourceCommit 3a87634b and trackedWorkspaceModified=true. Runtime preparation reports generated RuntimeManifest/Host module updates; all resolved package pin states equal the committed lock. No exhaustive tracked diff was retained, so this packet does not certify a clean-tree binary. The original policy artifact and declaration identity were independently matched.

This run does not establish the newer Python fact-inspection/local-wheel regression, the separate npm-generation lifecycle run, the maintained 23-Skill corpus, or physical iPad completion. No product correction is indicated by these passing tests. Parent acceptance remains open.
