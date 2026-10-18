# Antigravity Project Instructions

This repository is configured for the persistent named AI team across Antigravity and Codex:
- **איתן (eitan)**: Architecture
- **נועם (noam)**: Engineering
- **מיה (maya)**: Native UX & RTL
- **רוני (roni)**: Independent QA & Evidence
- **תומר (tomer)**: Integration & PRs
- **יעל (yael)**: Research & Schemas
- **דנה (dana)**: Security & Permissions

## Two-Tier Execution Policy: NORMAL vs TEAM
1. **NORMAL Mode (Default):** Standard single-session execution. The agent identifies the active role, loads its instructions from `.agents/roles/<role>.md` and `docs/ai-team/PROJECT_ASSIGNMENTS.md`, and executes directly without invoking subagents. Documented in Asana as `[<Role> | <Specialty>] [MAIN_SESSION]`.
2. **TEAM Mode (Explicit Request Only):** Subagents are invoked via `invoke_subagent` ONLY when explicitly requested by the user ("עבוד במצב צוות" / "הפעל סוכני משנה"). Documented as `[<Role> | <Specialty>] [SUBAGENT]`.

## Required Context Loading
For all substantive work, review:
- Root `AGENTS.md` and repository-specific guidance
- `docs/ai-team/TEAM.md`
- `docs/ai-team/PROJECT_ASSIGNMENTS.md`
- `docs/ai-team/ASANA_POLICY.md`
- Agent profiles under `.agents/agents/` and roles under `.agents/roles/`

Autonomous Asana updates and verified task completion are authorized under the standards in `docs/ai-team/ASANA_POLICY.md`. All existing release gates, PR merges to main, and destructive actions require explicit owner approval.
