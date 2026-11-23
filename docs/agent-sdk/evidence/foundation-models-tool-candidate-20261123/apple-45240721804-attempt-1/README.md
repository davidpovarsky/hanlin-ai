# Candidate Apple attempt 1: runner acquisition blocked

Authorized run [45240721804](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45240721804) used exact source f31147911a74e8984f2a510d6e11aec0bfb12975 and only the HanlinNativeToolCandidate selector in the existing agent_sdk_exact_source_proof route.

GitHub ended the run with failure on 2026-11-23 at 18:56:22 UTC. Selected job 137924304553 was cancelled at 18:56:21 with runner_id=0, no runner name, and zero steps. Its original check annotation states: “The job was not acquired by Runner of type hosted even after multiple attempts”. No compilation or test execution began. The sole finite watcher ended normally and its original response is retained.

**BLOCKED:** hosted runner acquisition. **NOT_RUN:** all 32 candidate invocations, all 12 baseline invocations, Apple compilation and actual SystemLanguageModel execution. The terminal artifacts endpoint returned an empty list; there was no artifact to download or verify. No test results are inferred from the run's queued start timestamp.

This evidence does not identify a code failure and calls for no production-code or runner-label change. A further attempt requires the coordinating agent's explicit run authorization; none was dispatched while recording this result. Public native-tool capability gates remain closed. Source hashes bind the unchanged candidate implementation and tests to f3114791. This evidence commit changes documentation only.
