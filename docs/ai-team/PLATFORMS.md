# Platforms: Antigravity & Codex Integration

This repository supports unified persistent named roles across both Google Antigravity and Codex platforms.

## 1. Google Antigravity Integration
Antigravity automatically discovers and activates the named team via:
- **Global Router:** `~/.gemini/config/rules/named-team-router.md` (`trigger: always_on`), filtering by repository remote URL and enforcing two-tier execution policy (NORMAL default vs TEAM explicit request).
- **Repository Entrypoint:** Root `AGENTS.md` and `GEMINI.md`.
- **Repository Rule Router:** `.agents/rules/ai-team-router.md` (`trigger: always_on`).
- **Custom Agent Definitions:** `.agents/agents/<name>.md` with YAML frontmatter (`name`, `description`, `mainAgent`, `subagent`, `model`).
- **Role Profiles:** `.agents/roles/<name>.md` defining scope, ownership, and handoff boundaries.
- **Skills:** `.agents/skills/asana-team-coordination/SKILL.md` for verified task coordination.

## 2. Two-Tier Execution Policy: NORMAL vs TEAM
- **NORMAL Mode (Default):** The main session agent directly executes the task while adopting the appropriate logical role and loading its instructions from `.agents/roles/<name>.md`. Subagents are not invoked. Documented as `[MAIN_SESSION]`.
- **TEAM Mode (Explicit Request Only):** When requested explicitly by the user ("עבוד במצב צוות" / "הפעל סוכני משנה"), the main agent acts as coordinator and delegates to specialized subagents via `invoke_subagent`. Documented as `[SUBAGENT]`.

## 3. Codex Integration
Codex operates with identical role definitions via:
- **Repository Entrypoint:** Root `AGENTS.md`.
- **Agent Definitions:** `.codex/agents/<name>.toml` with valid TOML syntax.
- **Shared Contracts:** `docs/ai-team/TEAM.md`, `PROJECT_ASSIGNMENTS.md`, and `ASANA_POLICY.md`.

## 4. Precedence & Boundaries
- Repository-specific instructions (`CLAUDE.md`, `PROJECT_AGENT_GUIDANCE.md`), frozen UI rules, and explicit approval gates take strict precedence over generic team behavior.
- Team definitions provide identity and routing; they do not authorize bypassing security, CI, or release gates.
