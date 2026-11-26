# Exact-source original CI dispatch

The original affected planner passed on 3f7c4a6f3cafa3919301750086cd1abf5c459955 after explicit routing of 14 previously unmapped paths. It selects 80 original app unit suites and 10 original UI selectors; no unknown-path full-validation fallback was used.

Original build-ios26-unsigned-ipa.yml run [45870248837](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45870248837) was accepted at 2026-11-26T17:44:20Z. The run was observed in progress, not passed. Final native/archive/device acceptance is separate.

The two incoming documentation-only matrices were independently checked against all 137 exact source hashes. They do not invalidate the production source used by this run.
