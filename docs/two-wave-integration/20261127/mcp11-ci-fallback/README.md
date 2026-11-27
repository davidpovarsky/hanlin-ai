# Original MCP11 CI continuation

The existing `agent-sdk-proof` job now routes only the explicit
`agent_sdk_exact_source_proof` / `HostMCPWireComparisonTests` request to the
reviewed original SwiftPM controller. No workflow, runner, shipping source,
test assertion, test selection, or package pin changes.

The original command remains
`/usr/bin/swift test --package-path Packages/HanlinAgentSDK --filter HostMCPWireComparisonTests --jobs 2`.
All eleven methods, both 120-second large controls, the serialized suite, the
3600-second phase ceiling, complete process topology/ownership guards and
same exact reconciliation remain required. The existing 60-minute GitHub job
includes preparation; the phase ceiling does not add time to that job.

The source admission binds the complete AgentSDK and Platform package trees,
their sources/tests, and six exact source/pin hashes. The original source
body differs only in its two CI lock paths, replacement of historical Git
object ancestry checks with fixed complete-closure checks for shallow CI
checkouts, and removal of a private Mac PATH. The source record and original
body diff identify these changes precisely.

Sixteen existing portable supervision controls passed. W1 independently
reviewed the exact source, inverse comparisons, original controls and raw
result. Native execution on the new route is NOT_RUN at this source seal.

All three earlier shared-Mac attempts remain infrastructure failures with
zero native test starts. The third timeout occurred during complete process
topology observation; neither an inherited-pipe issue nor memory pressure
was established as its cause. The recorded owned process was subsequently
verified, sent one SIGINT and observed absent, with no source-CWD processes
remaining. There is no fourth Mac attempt.

Original R3 packet:
`handoff/mcp-wire-78ec8f97-r3-infrastructure-failure`
(manifest SHA256
`fe47f0fd0235e32f58e183b3ecd3716adddefcceba314be398aaaf8c6592742e`).
Verified owned recovery SHA256
`cc6c2cad2cefc838506d3c3b13d76bc8a6193f814324bef0aeab173fa37e1934`.

The existing always-run upload retains source/capacity admission, raw output,
native identity reconciliation and failure records. If process observation
also fails during cleanup, cleanup remains unqualified until actual liveness
is resolved; a separate outer error record preserves that failure.

Before dispatch, bind the final published integration SHA and confirm no
active same-ref AgentSDK group will be cancelled by the existing concurrency
policy. Use `composer_validation_only=false`. The original real >8 MiB app
transport/render/store acceptance remains a separate required gate.
