# Personal Host action lifetime

[נועם | DEV] [MAIN_SESSION]. INT-03/SDK/Runtime consumer acceptance remains open.

The canonical MiniApp Host constructed its action broker with the library's
implicit15-second deadline. A valid NativeScript action calling the real Node,
TypeScript or Python backend could outlive that deadline even when the underlying
runtime request had no timeout. This was separate from the Runtime Core's already
verified305-second obligation.

HanlinMiniAppRequestBroker now accepts an optional timeout. Its library default
is still15s, and explicit deadlines retain the existing cancellation/draining
behavior. The personal Host explicitly selects Limits.personalHost, whose timeout
is nil. That path directly awaits the actual handler without creating a timer;
caller cancellation checks remain before and after the handler drains. Actual
CancellationError is reported as the canonical cancelled outcome.

Authorization/routes/capability checks, typed payload/response budgets (1MiB/4MiB)
and audit retention are unchanged. This does not claim unbounded inline values
or remove HanlinValue structural validation. Owned files/results remain the path
for large attachments; larger text/values need the appropriate reference contract,
with explicit errors instead of truncation. No engine or permission gate is added.

Three new production tests prove an actual16-second action beyond the old15s
deadline, explicit deadline/size rejection, and actual cancellation/handler drain.
The existing affected broker authorization case is also selected. Production
broker source passed portable Swift6.3.3 strict concurrency/warnings-as-errors
module compilation against the actual PlatformContracts module. Direct local
test typechecking lacked the Testing module search path; no local test execution
or Apple-framework proof is credited. Focused actual Apple execution and Host
consumer compilation are still required. The305s Core case is not rerun for this
separate action-boundary change.
