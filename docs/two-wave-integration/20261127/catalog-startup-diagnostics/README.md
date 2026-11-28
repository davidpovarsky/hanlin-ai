# Catalog startup diagnostics

The existing MiniApps catalog readiness failure occurs after storage bootstrap and before the catalog becomes available. The actual suspended operation has not yet been identified.

This change adds DEBUG/HANLIN_TESTING-only phase records around the original provider refresh and platform restore operations. Each invocation records its own generated UUID, process ID, and monotonic elapsed time. The messages contain fixed phase names, without package contents, user text or credentials. Notice-level logging improves retrospective availability; OS log retention and quotas still apply.

The paired acceptance runner captures only the MiniApps catalog records after an existing failure, from the same owned simulator, using the existing 30-second diagnostic command limit and a 15-minute retrospective range. This observation never changes the original acceptance status.

## Verified source boundary

Removing only the added guarded trace scopes recovers both original async method bodies byte for byte. Guards, awaits, throws, operation order, counters, cleanup, test assertions and test waits are unchanged. The original runner is recovered by removing the one added failure-only capture command. No diagnostic is a readiness shortcut or a product fix.

Each method has an independent UUID. Any association between a catalog refresh and a restore must use the actual PID, timestamps and event order; no parent-child link is asserted. Logging can perturb timing and cannot guarantee retained output.

The platform source is one of the SDK's 396 recorded inputs. Its exact fingerprint must be refreshed through the original producer before claiming current-SDK acceptance. Native compilation, actual trace capture and the catalog cause remain unverified by this source-only packet.
