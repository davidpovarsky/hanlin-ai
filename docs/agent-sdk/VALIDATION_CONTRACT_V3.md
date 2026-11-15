# Package-contract acceptance v3

This extends v2's authenticated per-case aggregation to the native schema adapter suite. It
preserves every prior assertion and adds the new Host minor/Session/provider controls. Scope is
**package contracts plus the real native model catalog**. It is not complete SDK/application/UI,
live-model or release acceptance. The actual app Host/SwiftData/row controls remain required OPEN.

At exact consumer `3e7ef6996da9f0c024019305536a3c8795c1e8a7`, producer remains
`e7bf34111e603ca977becd007dd4e5bb109af857`. Package Sources/tests/manifests/locks are unchanged
from8b6106ef. The separately proposed producer schema correction is not part of this tested graph.

Required coverage: every actual method in AgentSessionTests18, ContextTests6, StoreTests2,
HanlinInjectedProviderTests, HanlinAISDKProviderFactoryTests, HanlinAISDKAgentEngineTests,
HanlinNativeStructuredResponseTests (the four Core suites total25), and NativeModelCatalogTests3.
Also require actual iOS AgentCore and catalog compilation. This is54 case identities, all retained
in `evidence/package-contracts-v3-aggregate.json` with original source/run classification.

| Classification | Count | Actual evidence |
| --- | ---: | --- |
| EXECUTED_PASS |45|8b6106ef, run43735446863:18 Session +1 minor-version +1 checkpoint +25 Core; iOS SDK compile passed |
| EXECUTED_PASS |3|04addc76, run43737633194: actual AllModels/catalog/availability controls; iOS catalog compile passed |
| REUSED_VERIFIED_PASS |6|9a864b3c, run43725502988: five pure context/replay methods and in-memory namespace method |

The reuse audit compares each test's own evidence SHA9a through the complete target range,
unchanged assertion bodies/imports, all PlatformContracts sources, record/replay and in-memory
store source, and namespace/context/Session declarations. New Host guarantee enum/catalog validation
is outside those six closures; the new minor control executed freshly. Xcode27.2/27B52,
Swift6.4.2, both SDK27.2, macOS27.0.1/26A434 and arm64 match original evidence exactly.
No producer/Core/Session test was substituted for UI, business effects or performance obligations.
The six reused cases did not execute in the new runs. Their original workflow still had one real
checkpoint failure; that historical run is not relabelled green.

The bounded private-store traversal now passes the original checkpoint/history assertions and
actual symbolic-link rejection on Mac. Earlier failures and the cancelled first-save hang remain
in their own ledgers. Run43735446863's green workflow hid a Bash3.2 native child failure: its three
catalog cases were NOT_RUN. Only that missing phase was repaired/reexecuted43737633194 with the
same shared-source branch and mandatory actual xcresult/summary/build artifacts. Do not call that
original workflow full validation success or claim the45 package cases reexecuted in the catalog run.

Actual APIManager/Host schema fidelity, canonical app storage/row-collision controls, SDK-enabled
whole app/Composer, live model-to-official-renderer flow, XCUITest, physical device, RTL/AX and
distribution remain OPEN. A later source/dependency change must redo its impact audit and execute
affected/uncertain cases; this contract does not authorize blanket reuse at a newer pin.
