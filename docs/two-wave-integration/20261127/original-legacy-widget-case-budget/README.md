# Preserve the original legacy Widget case allowance

The original 90-selector run executed HanlinExpoProductionE2ETests/testNativeLegacyWidgetWithHostTerminated with a 600-second allowance. That cohort also included ScriptUI, which selected the existing 600-second workflow branch. Selecting the legacy Widget method alone previously fell through to the generic 300-second default.

This change maps only target_validation_group=exact_test_selector with the exact single legacy Widget method to its observed original 600-second allowance. It enables the authorized fresh-simulator diagnostic without adding another test or enabling full validation. It does not replace the original full90 gate.

The default300, live-provider420, ScriptUI600 and full-validation600 paths remain unchanged. Class-level, sibling, comma-combined, whitespace-suffixed and wrong-group requests retain their original behavior. No original assertion, action, fixture, selector or product source changes.

Two controls in the existing CI discovery execute only the original workflow's pure Bash budget-selection block. All 13 actual mappings passed. They neither invoke Xcode nor recreate the budget logic in a replacement implementation. Removing the one additive conditional and its explanatory comment recovers the complete original YAML; all other parsed values are identical.

The workflow, controls and proof are separate commits because the owner publishes the workflow through the existing GitHub Contents API. Native execution remains pending the final source-bound diagnostic request and the original complete gate.
