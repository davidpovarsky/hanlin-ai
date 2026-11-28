# Full-app native runner admission — run45156789463

[The run](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45156789463) binds source `646b22918b1c56e5a6a16addcb1d3ebd982d3846`. The actual planner passed. Native job137631863565 waited from10:31:18 to10:46:19UTC, then ended cancelled without a runner: runner_id0, empty name, zero steps. The original GitHub annotation says the hosted runner was not acquired after multiple attempts.

**App compilation, native artifact export and all26 selected test groups are NOT_RUN.** There is no new compiler error or product failure from this attempt. The later summary job cannot manufacture absent native test results; it reports failure. The original artifact inventory contains only the plan, performance and provider-summary artifacts, with no simulator logs or native payload.

The sole finite watcher ended10:46:52UTC. No second watcher or immediate full-app retry was started. C-only run45157020895 independently failed the same hosted-runner admission with zero steps. Anytype's approved original native1/UI1 source is held before dispatch; its previous failed gate and completed source repair remain separate.

The earlier actual Hanlin compile job137611700396 and accepted Lorvex job137603310142 used the same `xcode-27` label and had assigned runners. This is a new allocation failure, not evidence that those earlier native results were invalid.

GitHub's [live status API](https://www.githubstatus.com/api/v2/summary.json) reported Actions operational with no incidents during this readback. That broad report does not establish current availability of this runner label. The official [macOS26 image inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md) lists Xcode26 toolchains, so it does not supply the required Xcode27/iOS27 replacement. An existing read-only five-minute simulator-environment job can qualify current allocation/toolchain state without rebuilding an app or executing a product test.
