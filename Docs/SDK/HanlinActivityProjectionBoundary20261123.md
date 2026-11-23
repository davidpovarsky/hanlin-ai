# Original activity projection boundary repair

The full native SDK build at `ab46931b776f1701d554b230aa3dd7d8166dfa76`, [run45150840748](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45150840748), failed during app compilation. Its original compiler log identifies one source error: the streaming checkpoint adapter still calls `ClassicChatAgentProjection.isToolProjectionStep` after that helper moved into the canonical `HanlinAgentActivityCore.AgentActivityToolProjection`.

The repair exposes the existing original helper as public and sends the one remaining app call to that shared helper. No second predicate, forwarding implementation or changed classification is introduced. The entire SDK file is unchanged after normalizing that one access modifier; the entire app file is unchanged after normalizing the one call target. The helper body is also byte-identical to the original app helper before extraction.

## Evidence and scope

The original 1,329,748-byte artifact14807767611 has SHA-256 `c95eb7b9af4eea50de1207e97ace4ff7c2e1baeb2a67cac477c5da524cd08198`. Its size, complete digest and all ZIP member CRCs were verified. The unmodified 10,596,484-byte original simulator compiler log has SHA-256 `d08647bc877a6cca0251a6f449f6595ecaa08521e605418e6ac511153116a64b`. Both originals remain on Oracle in `build/sdk-native-sendability-retry-20261123/compiler-failure/`; the [compact receipt](../../docs/agent-sdk/evidence/activity-projection-boundary-45150840748/receipt.json) binds their provenance and exact source hashes.

Both complete changed Swift files pass syntax parsing. This is not native compilation or a test result. All 26 selected app/UI test groups remain **NOT_RUN**, so the next native continuation must retain that still-unexecuted scope. The 184,426,397-byte native-prepared artifact from this failed producer was not downloaded or published. The prior Widget import and navigation Sendable diagnostics are absent from this run's original compiler errors.

This two-line source correction preserves every original step classification, including calendar, native app, document, source and code execution. The SDK remains the single implementation for both UI projection and app streaming checkpoint selection.
