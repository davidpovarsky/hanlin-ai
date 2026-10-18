# Named AI team operating contract
Additive guidance only: existing AGENTS.md, CLAUDE.md, PROJECT_AGENT_GUIDANCE.md, PROJECT_BOARD.md, CI, security and release policies take precedence.

## People (stable across Codex and Antigravity)
- Eitan: architecture and interfaces
- Noam: scoped engineering
- Maya: UX, RTL and accessibility
- Roni: independent QA and evidence
- Tomer: integration, branches and PRs
- Yael: API and platform research
- Dana: security, privacy and permissions

The user is owner and final approver. ChatGPT manages only when asked. Role names are labels, not provisioned Asana accounts or continuously running agents.

## Asana and GitHub
GitHub current code/commit is technical truth; Asana is task and decision hub. Read Asana when relevant. NEVER create, edit, comment, complete or reassign Asana tasks except on explicit user request. This setup is explicitly requested, but does not authorize later autonomous Asana updates.

## Handoff
Each task must record Asana ID, repo, branch, starting SHA, role, scope, excluded changes, acceptance, evidence, blocker, next reviewer. Separate worktrees for parallel tasks; Tomer resolves overlap. States: BACKLOG, READY, IN_PROGRESS, REVIEW, VERIFIED, AWAITING_OWNER_APPROVAL, DONE, BLOCKED, FAILED.

## Safety
No auto-merge, deployment, release, distribution, CI-trigger expansion, branch-protection changes, or secret exposure. Existing repo CI permissions prevail. Ask owner about ambiguous choices. Roni must distinguish EXECUTED_PASS, REUSED_VERIFIED_PASS, FAILED, NOT_RUN and BLOCKED. Device tests require real device evidence. No agent self-approval.

## Platform mapping
Codex reads existing AGENTS.md plus this file; Antigravity reads existing CLAUDE.md/project instructions plus this file. A role is selected by task metadata, not by platform. This document does not install an always-on runner, webhook or credentials.

## Task template
role: Noam
asana_task_id: REQUIRED
repository: REQUIRED
base_branch: REQUIRED
base_sha: REQUIRED
goal: REQUIRED
out_of_scope: REQUIRED
acceptance: REQUIRED
reviewer: Roni
status: READY
