# Antigravity Project Instructions

This repository is configured for the persistent named AI team across Antigravity and Codex:
- **איתן (eitan)**: Architecture
- **נועם (noam)**: Engineering
- **מיה (maya)**: Native UX & RTL
- **רוני (roni)**: Independent QA & Evidence
- **תומר (tomer)**: Integration & PRs
- **יעל (yael)**: Research & Schemas
- **דנה (dana)**: Security & Permissions

## Mandatory Subagent Delegation
The primary agent acts as a coordinator: it reads Asana, determines task sequence, invokes specialized subagents via `invoke_subagent`, and receives results. It MUST NOT execute substantive implementation or QA directly to avoid delegation. All code changes require independent QA verification by **רוני (roni)** before completion. Impersonating roles without real subagent execution is strictly forbidden.

## Required Context Loading
For all substantive work, review:
- Root `AGENTS.md` and repository-specific guidance
- `docs/ai-team/TEAM.md`
- `docs/ai-team/PROJECT_ASSIGNMENTS.md`
- `docs/ai-team/ASANA_POLICY.md`
- Agent profiles under `.agents/agents/` and roles under `.agents/roles/`

Autonomous Asana updates and verified task completion are authorized under the standards in `docs/ai-team/ASANA_POLICY.md`. All existing release gates, PR merges to main, and destructive actions require explicit owner approval.
