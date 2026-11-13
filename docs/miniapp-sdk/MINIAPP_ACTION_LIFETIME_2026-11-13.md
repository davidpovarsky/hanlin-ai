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

## Actual focused Apple result

Run [43412862197](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43412862197)
at660f5b45fe41af70d259eb3818de4da956e6c4bc succeeded:4/4 selected cases in2 suites,
16.406s. The actual action completed after16.405s; explicit deadline/size,
cancellation/drain and original broker authorization/route checks passed.
Xcode27.2/27B52, Swift6.4.2, macOS arm64; job3m48s.
Downloaded artifact14030092982/3398B, GitHub SHA256
`1411c0ed070fb2c67366298e5ebc58afee9b8faff740036bdd94e854b9fc463d`.
This is package execution evidence; physical and full app consumer gates remain open.
