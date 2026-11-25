# Installed Expo notification action acceptance source

The existing `HanlinExpoHostServicesAcceptanceTests/testInstalledExpoActionsReturnActualReplyAndFailure` retains its original real-handler success/error/recovery assertions and adds the notification route. The original selected 27 AI tests and 240-second case allowance are unchanged.

The real fixture is imported into the shared owning platform and product extension store used by the production request broker. Its actual published intent identity constructs a typed notification event with a fresh UUID and challenge. The new ingress must persist the event, dispatch the installed Hermes handler, and return a durable receipt containing the actual payload, computed42, caller, ID and verified storage result. Reopening the store and repeated delivery must retain the same terminal receipt. A real rejecting JavaScript handler must produce the distinct actionFailed receipt. Both native receipts are attached as JSON. Each additional receipt wait is bounded to60 seconds.

No broker handler is stubbed or replaced. The test refuses to replace a pre-existing same-name fixture; only newly installed IDs matching the actual import manifest are registered for asynchronous teardown before further assertions, and removal is checked. The separate original widget test continues using its isolated fixture.

Read-only peer review caught and corrected the initial isolated-platform versus global-broker ownership mismatch. A subsequent review confirmed the real owner route and requested earlier failure-path teardown registration; that correction is present in the bound final source.

This is source review only. Native compile/execution, operating-system notification delivery/service callbacks, push/tap, and physical-device behavior are NOT established by this packet. Native execution awaits integration of the notification implementation and the original paired acceptance run.
