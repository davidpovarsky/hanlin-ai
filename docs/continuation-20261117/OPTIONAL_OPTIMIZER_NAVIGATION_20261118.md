# Optional optimizer and ordinary conversation creation

Historical obligation: PARITY-NAV-25 in docs/product-split/feature-delta-278.json.

The original ListView rejected every new conversation when UserInfo.optimizationTextModel was empty, even with an enabled provider and ordinary chat model. Both the compact toolbar and Home first-turn path call this same function. Remove only that unrelated optimizer prerequisite; existing provider validation and optimizer-specific actions retain their own behavior.

The added original-app XCUITest seeds a real SwiftData configuration with empty text/visual optimizer choices, creates a new chat through the real toolbar, sends through the existing SDK/provider/schema path, and reopens the same UUID and canonical read-only result without another model request. Only HTTP response bytes are fixtures. This tests same-process SwiftData persistence; it does not claim a live provider or cold-relaunch proof.

Native acceptance: PENDING. Windows Swift syntax parsing is not Apple compilation or execution.

Related parity investigation: the old Canvas remote endpoint is Piston. Its authoritative README now requires provider-issued authorization (effective 2026-02-15): https://github.com/engineer-man/piston/blob/master/readme.md . No authorization credential is configured in CodeServices.swift. Remote Canvas success must not be assumed from source presence. Local Python remains the existing separate embedded runtime.
