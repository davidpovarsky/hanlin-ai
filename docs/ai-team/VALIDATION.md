# AI Team Validation & Smoke-Test Procedures

This document outlines the automated and manual verification procedures for the named AI team configuration.

## 1. Static Validation
1. **YAML Frontmatter:**
   - Every file in `.agents/agents/*.md`, `.agents/rules/*.md`, and `.agents/skills/*/SKILL.md` must have valid YAML frontmatter.
   - Rules must have `trigger: always_on`, `model_decision`, `glob`, or `manual`.
   - Rules must not exceed 24 KB.
2. **TOML Syntax:**
   - Every file in `.codex/agents/*.toml` must parse cleanly with `tomllib`.
3. **Link & Path Verification:**
   - All relative file links in `AGENTS.md`, `GEMINI.md`, and `docs/ai-team/*.md` must resolve to existing files.
4. **Policy Integrity:**
   - `ASANA_POLICY.md` must contain the authorized verified completion rule.
   - No stale blanket prohibition ("never write/update Asana") should survive in role or agent definitions.

## 2. Runtime Smoke Tests
1. **Antigravity Agent Discovery:**
   - Run a fresh Antigravity session and verify all 7 agents appear in `/agents` or subagent listing.
   - Verify that subagents can be delegated read-only tasks safely.
2. **Asana Integration:**
   - Verify connection via Asana MCP or REST API (`asana_list_workspaces`).
   - Perform safe read -> meaningful write -> read-back test on designated setup tasks.
   - Verify task completion gating (tasks without physical device proof remain open).

## 3. Branch Diagnostic Tool
Run `tools/ai-team/ensure-team.ps1 -Check` to verify configuration integrity on any branch.
