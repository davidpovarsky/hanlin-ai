# Bounded native calendar privacy preparation

Run45283504095/attempt1 on4cfa52348e80cf635caf04c541fd84ee1ddb50bd built the original arm64 application and test products. Its original app install succeeded, then the original calendar permission command exceeded its20s allowance and returned124. Reminders and test execution were never reached. Current acceptance is0PASS/0FAIL/37NOT_RUN; no product assertion failed or passed in that run.

This change gives the two privacy grant commands120s each and records the configured timeout and monotonic elapsed duration for each attempted command. The original command ordering, owned-simulator and bundle guards, install180s, and stop-on-nonzero remain unchanged. There is no retry or reset. Original application test deadlines are unchanged.

Source syntax and exact inverse-diff review passed. All13 protected test/harness inputs remain byte-identical. A separate reviewer checked the precise diff and those hashes, without rerunning unchanged controls. Native validation after this allowance change is NOT_RUN until a new frozen same37 attempt executes.

The preserved source review and production diff describe preparation, not evidence of TCC causation or successful runtime recovery. Original run evidence is retained separately in ../main37-staging-45283504095/.
