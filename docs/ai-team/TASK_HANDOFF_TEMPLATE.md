# Task Handoff Template

Use this envelope to record status transitions, reviewer handoffs, and verification evidence:

```yaml
task_id: "<Asana-GID>"
repository: "<owner/repo>"
branch: "<branch-name>"
commit_sha: "<commit-sha>"
acting_role: "[נועם | DEV] / [רוני | QA] / [איתן | ARCH] / [תומר | INT] / [יעל | RES] / [מיה | UX] / [דנה | SEC]"
execution_mode: "MAIN_SESSION | SUBAGENT"
subagent_invocation:
  subagent_type: "<eitan | noam | maya | roni | tomer | yael | dana | NONE>"
  conversation_id: "<subagent-conversation-id or NONE (MAIN_SESSION)>"
next_reviewer: "[רוני | QA] / [תומר | INT] / [איתן | ARCH] / [דנה | SEC] / Owner"
status: "BACKLOG | READY | IN_PROGRESS | READY_FOR_QA | VERIFIED | BLOCKED | AWAITING_OWNER_APPROVAL | DONE"
goal: "<Concise description of the task objective>"
implemented_scope:
  - "<Component / file modified and why>"
excluded_scope:
  - "<Frozen files, out-of-scope items, or preserved upstream code>"
acceptance_criteria:
  - "<Criterion 1>: <VERIFIED / PENDING / FAILED>"
evidence:
  tests_executed: "<Named test suites, number of tests passed/failed>"
  ci_run_url: "<GitHub Actions run URL if applicable>"
  local_run_output: "<Log summary or artifact reference>"
  hardware_proof: "<Physical device logs/screenshots, or NONE if simulator/unit only>"
blockers_or_risks:
  - "<Blocker description and unblock condition, or None>"
```
