# Asana Team Coordination & Verified Completion Policy

**Owner Authorization Date:** 2026-10-18  
**Scope:** Approved project management hub across five repositories:
- `davidpovarsky/Maktabah` (Asana Project: `1219602719070493` — אוצריא)
- `davidpovarsky/TorahInspectorKit` (Shared across Maktabah and Pinkha)
- `davidpovarsky/hanlin-ai` (Asana Project: `1219603102275846`)
- `davidpovarsky/cherri` (Asana Project: `1219603572114432`)
- `davidpovarsky/anytype-swift` (Asana Project: `1219604672449660`)
- `davidpovarsky/onebusaway-ios` (Asana Project: `1219605677718919`)

---

## 1. Core Operating Principle: Autonomous Verified Writes

When carrying out owner-assigned development, research, QA, review, or integration work, Antigravity agents may autonomously create and update relevant Asana tasks and subtasks, label the logical owner and reviewer, add meaningful coordination comments, update progress and blockers, adjust dependencies, and set `completed=true` when — and **ONLY** when — that exact task's defined acceptance conditions have verifiably passed.

Per-task owner confirmation is not required for these routine project-management actions. Record exact evidence (repository, branch, commit SHA, named tests/run IDs, real-device proof when required, and remaining scope).

If requirements are not met, leave the task open with `IN_PROGRESS`, `READY_FOR_QA`, or `BLOCKED`, including the next action. **No false completion is permitted.**

Existing explicit owner gates for PR merges, releases, external publication, signing credentials, destructive migrations, and sensitive production operations still strictly require explicit owner approval.

---

## 2. Logical Roles & Comment Attribution

The 7 permanent roles are logical identities operating under the single authenticated user account:
- `[איתן | ARCH]` — Principal architect
- `[נועם | DEV]` — Engineering & implementation
- `[מיה | UX]` — Native UX, interactions, RTL
- `[רוני | QA]` — Independent verification & evidence
- `[תומר | INT]` — Integration, PRs, worktrees
- `[יעל | RES]` — Research, APIs, schemas
- `[דנה | SEC]` — Security, privacy, permissions

All comments and updates must explicitly attribute the acting role in the comment body or task title (e.g. `[נועם | DEV]`). Never claim or imply a comment was made by a separate provisioned human user.

---

## 3. Task Lifecycle States

Tasks transition through explicit text-based states:
- `BACKLOG`: Scoped and awaiting start.
- `READY`: Blockers cleared, ready for active implementation.
- `IN_PROGRESS`: Actively worked on by the assigned role.
- `READY_FOR_QA`: Implementation committed, ready for independent verification by Roni.
- `VERIFIED`: Verification passed with documented evidence.
- `BLOCKED`: Blocked by external dependencies, missing hardware, or missing credentials.
- `AWAITING_OWNER_APPROVAL`: Awaiting explicit owner release/merge decision.
- `DONE`: Completed after meeting all verification criteria.

---

## 4. Acceptance Criteria & Completion Standard

To mark a task `completed=true`:
1. **Full Scope Verified**: Every item in the task's acceptance criteria must pass. Partial implementation is not completion.
2. **Technical Proof**: Record the exact repository, branch, and commit SHA.
3. **Execution Evidence**: Record named test suites, assertion results, and CI run URLs or local logs.
4. **Physical Hardware Gate**: Tasks explicitly addressing physical iPad/iPhone behavior must remain open (`BLOCKED_DEVICE`) until verified on physical hardware. A green simulator build or unsigned IPA is never a substitute for hardware acceptance.
5. **Research Tasks**: A research-only task completes when its documented findings, schema, or RFC is verified and reviewed, without implying the overall software feature is done.

---

## 5. Cross-Role Handoff Envelope

When handing off work, post a concise coordination comment:
```
[<ActingRole> | <Action> -> <NextRole> | <NextAction>] <STATUS>
Branch: <branch-name> | Commit: <commit-sha> | PR: <url>
Tests: <test results summary>
Known Risks: <risks or remaining gaps>
Next Action: <what next reviewer should verify>
```

---

## 6. Operational Guardrails

- **No Continuous Polling**: Never run a background polling loop or webhook daemon. Read and update Asana on demand at task start, significant phase handoff, and completion only.
- **Rate Limit Handling**: Respect HTTP 429 with bounded exponential backoff.
- **Idempotency & Secret Protection**: Perform targeted field updates. Never overwrite entire task descriptions unnecessarily. Never log tokens, commit PATs, or store credentials in repository files.
- **Scope Discipline**: Do not invent new unrelated feature tasks or broaden project scope without explicit user authorization.
