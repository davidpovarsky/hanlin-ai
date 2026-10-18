# Platforms: Antigravity & Codex Integration

This repository supports unified persistent named roles across both Google Antigravity and Codex platforms.

## 1. Google Antigravity Integration
Antigravity automatically discovers and activates the named team via:
- **Global Router:** `~/.gemini/config/rules/named-team-router.md` (`trigger: always_on`), filtering by repository remote URL and enforcing mandatory subagent delegation.
- **Repository Entrypoint:** Root `AGENTS.md` and `GEMINI.md`.
- **Repository Rule Router:** `.agents/rules/ai-team-router.md` (`trigger: always_on`).
- **Custom Agent Definitions:** `.agents/agents/<name>.md` with YAML frontmatter (`name`, `description`, `mainAgent`, `subagent`, `model`).
- **Role Profiles:** `.agents/roles/<name>.md` defining scope, ownership, and handoff boundaries.
- **Skills:** `.agents/skills/asana-team-coordination/SKILL.md` for verified task coordination.

## 2. Mandatory Subagent Delegation
The primary Antigravity session agent functions as the **coordinator**:
- It identifies required roles and invokes them via `invoke_subagent`.
- It defines subagents via `define_subagent` if not already registered in the session.
- It MUST NOT substitute itself for a specialist agent to avoid delegation.
- It MUST route development tasks to **רוני (roni)** for independent QA verification before completion.

## 3. Codex Integration
Codex operates with identical role definitions via:
- **Repository Entrypoint:** Root `AGENTS.md`.
- **Agent Definitions:** `.codex/agents/<name>.toml` with valid TOML syntax.
- **Shared Contracts:** `docs/ai-team/TEAM.md`, `PROJECT_ASSIGNMENTS.md`, and `ASANA_POLICY.md`.

## 4. Precedence & Boundaries
- Repository-specific instructions (`CLAUDE.md`, `PROJECT_AGENT_GUIDANCE.md`), frozen UI rules, and explicit approval gates take strict precedence over generic team behavior.
- Team definitions provide identity and routing; they do not authorize bypassing security, CI, or release gates.
