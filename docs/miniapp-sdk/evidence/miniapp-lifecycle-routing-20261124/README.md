# Registered route for one MiniApp store lifecycle method

This routing-only descendant follows rollback fix 98ce6516. It adds miniapp_lifecycle to the existing paired_test_scope choice in validate-app-split.yml; workflow_dispatch still has 10 inputs.

The intended root-owned dispatch uses paired_product_acceptance=true and paired_test_scope=miniapp_lifecycle. A local reusable job calls ./.github/workflows/validate-scripting-runtime.yml at the caller's commit with exactly:

    runtime_job_foundation_only=false
    force_clean_build=true
    test_filter=HanlinAtomicScriptStoreTests/lifecycle

The original contracts job remains byte-for-byte equivalent in parsed configuration. The main application job excludes only the two explicit isolated paired scopes, miniapp_contracts and miniapp_lifecycle. Registration/audit precedence, default modes, main-job steps, callee, permissions, secrets convention, concurrency expression and cancel-in-progress remain unchanged.

The existing group resolves to paired-miniapp_lifecycle, separately from paired-miniapp_authoring and paired-miniapp_contracts on the same branch. Source validation records 192 unchanged existing flag/scope combinations and eight new-mode combinations, plus the exact selector's presence in the real test source.

These are YAML and source-expression checks only. No store test was rerun, and no workflow was dispatched or polled in this lane. Root owns the one-method Apple run. Require one actual Swift Testing method pass and no failure/cancellation/skip; an exit code or a zero-test XCTest wrapper alone does not prove execution. The reusable workflow's normal path has no dedicated artifact upload, so preserve its completed raw job log and exact source SHA.
