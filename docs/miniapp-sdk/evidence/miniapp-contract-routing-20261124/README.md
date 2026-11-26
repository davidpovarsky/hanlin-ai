# Registered routing for the eight modern MiniApp contract methods

Root's direct preflight lookup of validate-scripting-runtime.yml returned HTTP 404 because that workflow is not registered on the default branch. The authenticated registry listed 16 workflows; validate-app-split.yml is registered as 419196373. Root did not dispatch a workflow and no new run ID exists from this failed preflight. root-preflight.json is copied verbatim from the root-owned receipt.

This patch extends the existing paired_test_scope choice with miniapp_contracts. It does not add an eleventh workflow_dispatch input. With paired_product_acceptance=true and this scope, the registered caller executes its conditional miniapp-contracts job. That job uses ./.github/workflows/validate-scripting-runtime.yml at the same caller commit, passes the exact eight-method filter, runtime_job_foundation_only=false and force_clean_build=true, and inherits secrets using the existing reusable-call convention.

The original miniapps job skips this explicit new mode. Registration and resource-audit precedence stays intact. All existing main-job commands, signing logic, timeouts, and steps are byte-identical. The callee is unchanged. Caller/callee read-only permissions match.

The existing concurrency expression remains unchanged and produces separate paired-miniapp_contracts and paired-miniapp_authoring suffixes on the same branch. cancel-in-progress was not modified. No claim about the cause of any earlier cancellation is made.

## Executed validation

source-validation.json and source-validation.txt record YAML parsing and source-only comparisons. The actual existing job expressions were evaluated for 160 existing flag/scope combinations and eight new-mode combinations. All existing behavior remained unchanged; the new mode selects the contracts job exclusively when registration/audit are absent. The exact eight selected method names exist in the current Analyzer test source. Main job body, callee, permissions and concurrency are unchanged.

These checks establish the patch's source routing, not GitHub service acceptance, a workflow dispatch, native compilation, or passing contract tests. Root owns the next dispatch. The callee's normal path has no dedicated artifact upload: retain its completed raw job log plus exact source SHA and require all eight actual Swift Testing passes with no failures/cancellations/skips.

The existing SDK02/SDK06 gap map and README now identify this registered route instead of the unavailable direct dispatch. No runtime, test method or acceptance selector was changed in this routing commit. No native workflow was dispatched.
