# Agent Diagnostics

Agent diagnostics are independent from the user-facing activity timeline. Detailed recording is opt-in and records the final sanitized request object immediately before serialization, visible provider output, tool calls/results, timing, and provider-reported or explicitly estimated token usage.

Files are written atomically to the existing `Documents/Diagnostics` directory as paired JSON and readable text snapshots. They are visible through Files because the existing app target enables document sharing. Full logs never use Application Support, CloudKit, analytics, or automatic export.

The central redactor is applied before persistence and again to the readable export. Hidden chain-of-thought is never reconstructed; only provider-visible reasoning content already exposed by the API may be recorded.
