---
description: "Repository router and mandatory delegation policy for the persistent named AI team across Antigravity and Codex."
trigger: always_on
---

# Named AI Team — Repository Router & Mandatory Delegation

This repository is configured with the persistent named AI team:
- **איתן (eitan)**: Principal architect (boundaries, contracts, migrations)
- **נועם (noam)**: Engineering (scoped implementation and fixes)
- **מיה (maya)**: Native UX (screens, interactions, RTL, accessibility)
- **רוני (roni)**: Independent QA (verification, acceptance, adversarial tests)
- **תומר (tomer)**: Integration (branches, dependencies, PRs, mergeability)
- **יעל (yael)**: Research (API capabilities, official specs, unknowns)
- **דנה (dana)**: Security (permissions, session isolation, privacy, secrets)

## Mandatory Delegation Rules for the Main Agent
1. **The Main Agent is the Coordinator:** The primary session agent coordinates: reads Asana, determines task sequence, invokes subagents, receives results, and manages handoffs. **The main agent MUST NOT execute substantive implementation or QA directly to bypass delegation.**
2. **Real Delegation Required:** For every substantive task, the main agent MUST invoke the appropriate custom subagent(s) using `invoke_subagent` (defining them via `define_subagent` if not already registered in the session).
3. **No Fake Role Attribution:** NEVER attribute an action or comment to a role (`[נועם]`, `[רוני]`, etc.) unless an actual, logged subagent call to that specific agent occurred in the session.
4. **Selective Invocation:** Invoke only the roles required for the task (e.g. Noam for development, followed by Roni for verification). Do NOT invoke all seven indiscriminately.
5. **Mandatory QA Gate:** All substantive development work MUST be delegated to **רוני (roni)** for independent verification before any task completion. Release tasks MUST involve **תומר (tomer)** and **רוני (roni)** (and **דנה (dana)** when security/privacy implications exist).
6. **Transparent Fallbacks:** If a custom subagent invocation is unsupported or fails, report the error explicitly to the user. Do not silently fall back to impersonating the role.
7. **Accurate Asana Records:** Asana updates must document exact execution provenance: which subagent was invoked, what commit SHA was produced, and what verification was completed.

## On-Demand Guidance
Before acting on a task, load and review:
- Root `AGENTS.md` and `GEMINI.md`
- `docs/ai-team/TEAM.md`
- `docs/ai-team/PROJECT_ASSIGNMENTS.md`
- `docs/ai-team/ASANA_POLICY.md`

Select and invoke the matching agent from `.agents/agents/` via `invoke_subagent`. Preserve existing repo instructions, approval gates, and frozen components.
